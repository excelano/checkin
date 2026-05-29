// CheckInWidget.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import WidgetKit
import SwiftUI
import AppIntents
import CheckInGraph
import CheckInKit

struct CheckInEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckInSnapshot?
}

struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry {
        CheckInEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        completion(CheckInEntry(date: Date(), snapshot: readSnapshot() ?? previewSnapshot))
    }

    /// Generate one entry per minute up to 60 minutes out so the
    /// "in X min" countdown stays accurate without requiring a widget
    /// refresh. After 60 entries, iOS reloads; the main app also reloads
    /// us proactively on every refresh. On each reload we fetch a fresh
    /// snapshot (next meeting, counts, presence, OOO) straight from Graph,
    /// so the widget stays current between app launches.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        Task {
            let snapshot = await liveSnapshot()
            let now = Date()
            var entries: [CheckInEntry] = []
            for minute in 0...60 {
                let date = now.addingTimeInterval(TimeInterval(minute * 60))
                entries.append(CheckInEntry(date: date, snapshot: snapshot))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// A snapshot fetched directly from Graph in the extension. On any failure
    /// (no token, offline, Graph error) we fall back to the last snapshot the
    /// app wrote to the App Group, so the widget never blocks or blanks on the
    /// network.
    private func liveSnapshot() async -> CheckInSnapshot? {
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        if let fresh = try? await core.fetchSnapshot() {
            return fresh
        }
        return readSnapshot()
    }

    private func readSnapshot() -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier),
              let data = defaults.data(forKey: CheckInSnapshot.userDefaultsKey),
              let snapshot = try? JSONDecoder().decode(CheckInSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private var previewSnapshot: CheckInSnapshot {
        CheckInSnapshot(
            updatedAt: Date(),
            nextMeetingSubject: "Status Meeting",
            nextMeetingStart: Date().addingTimeInterval(30 * 60),
            nextMeetingOrganizer: "David Anderson",
            nextMeetingJoinUrl: "https://teams.microsoft.com/l/meetup-join/preview",
            unreadEmailCount: 5,
            chatCount: 2,
            presence: .available,
            isOutOfOffice: false
        )
    }
}

/// Lead time before a meeting's start at which the Join button replaces the
/// time + organizer line. Outside this window the row shows "in N min"; inside
/// it the button takes the row.
private let joinPillLeadTime: TimeInterval = 5 * 60

/// Mirrors `untilTime` in the main app's RelativeTime.swift — formats
/// the gap to a future date as "now", "Starting soon", "in N min",
/// "in N hour(s)", or "in Nh Mm". `referenceDate` is the entry's
/// timeline date so the result stays correct across timeline entries.
private func untilTime(_ date: Date, referenceDate: Date) -> String {
    let seconds = date.timeIntervalSince(referenceDate)
    if seconds < 0 { return "now" }
    if seconds <= 180 { return "Starting soon" }
    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 { return minutes == 1 ? "in 1 min" : "in \(minutes) min" }
    if minutes == 0 { return hours == 1 ? "in 1 hour" : "in \(hours) hours" }
    return "in \(hours)h \(minutes)m"
}

private func isMeetingImminent(_ date: Date, referenceDate: Date) -> Bool {
    let seconds = date.timeIntervalSince(referenceDate)
    return seconds >= 0 && seconds <= 180
}

struct CheckInWidgetEntryView: View {
    var entry: CheckInProvider.Entry

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    meetingBlock
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                Spacer(minLength: 0)
                countsColumn
            }
            if entry.snapshot != nil {
                actionBar
            }
        }
    }

    /// Below the subject: the time + organizer until the meeting is within
    /// `joinPillLeadTime` of starting, then the Join button takes the row
    /// (dropping the organizer). In-person meetings (no join URL) keep showing
    /// the time + organizer.
    @ViewBuilder
    private func meetingDetailLine(start: Date) -> some View {
        let secondsToStart = start.timeIntervalSince(entry.date)
        if secondsToStart <= joinPillLeadTime,
           let urlString = entry.snapshot?.nextMeetingJoinUrl,
           let url = teamsJoinURL(from: urlString) {
            joinPill(url: url)
        } else {
            organizerLine(start: start, organizer: entry.snapshot?.nextMeetingOrganizer)
        }
    }

    @ViewBuilder
    private var meetingBlock: some View {
        if let subject = entry.snapshot?.nextMeetingSubject,
           let start = entry.snapshot?.nextMeetingStart {
            meetingHeader(start: start)
            Text(subject)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.tail)
            meetingDetailLine(start: start)
        } else if entry.snapshot != nil {
            Text("No more meetings today.")
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("CheckIn")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Open CheckIn to refresh.")
                .font(.subheadline)
                .foregroundStyle(Brand.textMuted)
        }
    }

    /// "NEXT MEETING" until the meeting starts, then "IN PROGRESS" once
    /// `start` is at or before the entry's date. The label is computed against
    /// `entry.date`, so the per-minute timeline flips it on its own without a
    /// refetch. In progress reads orange to signal the meeting is live.
    private func meetingHeader(start: Date) -> some View {
        let inProgress = start <= entry.date
        return HStack(spacing: 6) {
            Text(inProgress ? "IN PROGRESS" : "NEXT MEETING")
                .font(.caption.weight(.semibold))
                .foregroundStyle(inProgress ? .orange : Brand.accent)
            Text(start, style: .time)
                .font(.subheadline)
                .foregroundStyle(Brand.textMuted)
        }
    }

    private func organizerLine(start: Date, organizer: String?) -> some View {
        let imminent = isMeetingImminent(start, referenceDate: entry.date)
        return HStack(spacing: 8) {
            Text(untilTime(start, referenceDate: entry.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(imminent ? .orange : Brand.accent)
                .lineLimit(1)
                .layoutPriority(1)
            if let organizer, !organizer.isEmpty {
                Text("with \(organizer)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// Rewrite the Graph-supplied `https://teams.microsoft.com/...` URL
    /// to the `msteams:` scheme so iOS routes the tap directly to the
    /// Teams app via the registered deep-link scheme instead of going
    /// through Universal Link resolution (which can fall back to the
    /// host app from a widget context).
    private func teamsJoinURL(from raw: String) -> URL? {
        if raw.hasPrefix("https://teams.microsoft.com/") {
            let rewritten = raw.replacingOccurrences(
                of: "https://teams.microsoft.com/",
                with: "msteams:/"
            )
            return URL(string: rewritten)
        }
        return URL(string: raw)
    }

    private func joinPill(url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                Text("Join meeting")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Brand.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var countsColumn: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .trailing, spacing: 8) {
                countPill(systemImage: "bubble.left.fill", count: snapshot.chatCount)
                countPill(systemImage: "envelope.fill", count: snapshot.unreadEmailCount)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func countPill(systemImage: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline)
            Text("\(count)")
                .font(.headline)
        }
        .foregroundStyle(Brand.accent)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Interactive availability toggle. WidgetKit gives `Toggle(intent:)` a
    /// built-in optimistic flip: the knob moves the instant you tap, before
    /// the Graph call returns, which a plain `Button` can't do and which is
    /// not gated by the timeline reload budget. On sets Available; off sets
    /// Busy. The label shows the live status, so any other state (Away, DND,
    /// Out of Office) reads as off.
    private var actionBar: some View {
        let presence = entry.snapshot?.presence ?? .unknown
        let isOutOfOffice = entry.snapshot?.isOutOfOffice ?? false
        let isAvailable = presence == .available && !isOutOfOffice
        return VStack(spacing: 6) {
            Rectangle()
                .fill(Brand.textMuted.opacity(0.25))
                .frame(height: 1)
            Toggle(
                isOn: isAvailable,
                intent: SetStatusIntent(status: isAvailable ? .busy : .available)
            ) {
                HStack(spacing: 6) {
                    PresenceGlyph(presence)
                        .font(.subheadline)
                    Text(isOutOfOffice ? "Out of Office" : presence.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .toggleStyle(AvailabilityToggleStyle())
        }
    }
}

/// A switch-style toggle drawn entirely with shapes, so it renders inside a
/// widget (the native `.switch` style shows iOS's "unsupported view"
/// placeholder there). The knob position follows `configuration.isOn`, which
/// WidgetKit flips optimistically the instant the toggle is tapped.
struct AvailabilityToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Brand.accent : Brand.textMuted.opacity(0.4))
                    .frame(width: 46, height: 28)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
        }
    }
}

struct CheckInWidget: Widget {
    let kind: String = "CheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CheckInProvider()) { entry in
            CheckInWidgetEntryView(entry: entry)
                .containerBackground(Brand.bg, for: .widget)
        }
        .configurationDisplayName("CheckIn")
        .description("Your next meeting and unread counts at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    CheckInWidget()
} timeline: {
    CheckInEntry(
        date: .now,
        snapshot: CheckInSnapshot(
            updatedAt: .now,
            nextMeetingSubject: "Status Meeting",
            nextMeetingStart: .now.addingTimeInterval(8 * 60),
            nextMeetingOrganizer: "David Anderson",
            nextMeetingJoinUrl: "https://teams.microsoft.com/l/meetup-join/preview",
            unreadEmailCount: 5,
            chatCount: 2,
            presence: .busy,
            isOutOfOffice: false
        )
    )
    CheckInEntry(
        date: .now,
        snapshot: CheckInSnapshot(
            updatedAt: .now,
            nextMeetingSubject: nil,
            nextMeetingStart: nil,
            nextMeetingOrganizer: nil,
            nextMeetingJoinUrl: nil,
            unreadEmailCount: 0,
            chatCount: 0,
            presence: .unknown,
            isOutOfOffice: true
        )
    )
    CheckInEntry(date: .now, snapshot: nil)
}
