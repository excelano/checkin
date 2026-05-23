// CheckInWidget.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import WidgetKit
import SwiftUI

// Brand colors mirrored from the main app's Brand.swift. Kept in sync
// manually because the widget extension is a separate target.
private enum WidgetBrand {
    static let bg        = Color(red: 0x0D / 255, green: 0x2D / 255, blue: 0x5B / 255)
    static let bgDarker  = Color(red: 0x06 / 255, green: 0x14 / 255, blue: 0x2A / 255)
    static let accent    = Color(red: 0x00 / 255, green: 0xAD / 255, blue: 0xEE / 255)
    static let textMuted = Color(red: 0x6A / 255, green: 0x88 / 255, blue: 0x99 / 255)
}

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
    /// refresh. After 60 entries, iOS reloads — the main app also
    /// reloads us proactively on every refresh.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        let snapshot = readSnapshot()
        let now = Date()
        var entries: [CheckInEntry] = []
        for minute in 0...60 {
            let date = now.addingTimeInterval(TimeInterval(minute * 60))
            entries.append(CheckInEntry(date: date, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
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
            chatCount: 2
        )
    }
}

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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                meetingBlock
                Spacer(minLength: 0)
                joinPillIfAvailable
            }
            .frame(maxHeight: .infinity)
            Spacer(minLength: 0)
            countsColumn
        }
    }

    @ViewBuilder
    private var joinPillIfAvailable: some View {
        if let urlString = entry.snapshot?.nextMeetingJoinUrl,
           let url = teamsJoinURL(from: urlString) {
            joinPill(url: url)
        }
    }

    @ViewBuilder
    private var meetingBlock: some View {
        if let subject = entry.snapshot?.nextMeetingSubject,
           let start = entry.snapshot?.nextMeetingStart {
            HStack(spacing: 6) {
                Text("NEXT MEETING")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetBrand.accent)
                Text(start, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(WidgetBrand.textMuted)
            }
            Text(subject)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.tail)
            organizerLine(start: start, organizer: entry.snapshot?.nextMeetingOrganizer)
        } else if entry.snapshot != nil {
            Text("CALENDAR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetBrand.accent)
            Text("No more meetings today.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        } else {
            Text("CheckIn")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Open CheckIn to refresh.")
                .font(.subheadline)
                .foregroundStyle(WidgetBrand.textMuted)
        }
    }

    private func organizerLine(start: Date, organizer: String?) -> some View {
        let imminent = isMeetingImminent(start, referenceDate: entry.date)
        return HStack(spacing: 8) {
            Text(untilTime(start, referenceDate: entry.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(imminent ? .orange : WidgetBrand.accent)
            if let organizer, !organizer.isEmpty {
                Text("with \(organizer)")
                    .font(.subheadline)
                    .foregroundStyle(WidgetBrand.textMuted)
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
            .background(WidgetBrand.accent)
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
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
            Text("\(count)")
                .font(.title2.weight(.semibold))
        }
        .foregroundStyle(WidgetBrand.accent)
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background(WidgetBrand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CheckInWidget: Widget {
    let kind: String = "CheckInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CheckInProvider()) { entry in
            CheckInWidgetEntryView(entry: entry)
                .containerBackground(WidgetBrand.bg, for: .widget)
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
            chatCount: 2
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
            chatCount: 0
        )
    )
    CheckInEntry(date: .now, snapshot: nil)
}
