// CheckInWatchWidget.swift
// CheckInWatchWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI
import WidgetKit

/// Timeline entry holding the watch-side snapshot. Nil when the phone
/// hasn't pushed a snapshot yet (fresh install, paired-but-never-synced).
struct WatchStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckInSnapshot?
}

/// Reads the snapshot the `WatchSessionReceiver` last wrote to the watch
/// App Group. No Graph calls, no MSAL — the watch widget extension holds
/// no credentials and never speaks to Microsoft.
struct WatchStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchStatusEntry {
        WatchStatusEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchStatusEntry) -> Void) {
        completion(WatchStatusEntry(date: .now, snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchStatusEntry>) -> Void) {
        let snapshot = load()
        let now = Date()
        // Always emit a "now" entry, then one at each upcoming meeting
        // start so the widget swaps to the next meeting at the exact
        // moment one ends and another begins back-to-back. Without
        // these explicit transition entries, the widget would sit on
        // a stale meeting until the 15-minute reload tick.
        var entries: [WatchStatusEntry] = [WatchStatusEntry(date: now, snapshot: snapshot)]
        if let snapshot {
            for date in snapshot.upcomingMeetingStartDates(after: now) {
                entries.append(WatchStatusEntry(date: date, snapshot: snapshot))
            }
        }
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func load() -> CheckInSnapshot? {
        CheckInSnapshot.loadFromAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
    }
}

// MARK: - Corner

struct WatchCornerView: View {
    let entry: WatchStatusEntry

    var body: some View {
        cornerGlyph
            .widgetLabel { Text(cornerLabel) }
    }

    @ViewBuilder
    private var cornerGlyph: some View {
        if let snapshot = entry.snapshot, snapshot.isOutOfOffice {
            cornerBadge("arrow.up.forward")
        } else if let presence = entry.snapshot?.presence,
                  presence == .beRightBack || presence == .away {
            Image(systemName: "clock.fill")
                .font(.system(size: 32, weight: .semibold))
        } else {
            cornerBadge(cornerSymbol(for: entry.snapshot?.presence ?? .unknown))
        }
    }

    /// Curved label text on the corner edge. Prefers the countdown when
    /// a meeting is coming up so the glyph still reflects presence while
    /// the words tell you when you're up next; otherwise falls back to
    /// the OOO or presence name. Uses `currentOrNextMeeting` so the
    /// countdown picks the right meeting after a back-to-back transition.
    private var cornerLabel: String {
        if let meeting = entry.snapshot?.currentOrNextMeeting(referenceDate: entry.date) {
            return untilTime(meeting.start, referenceDate: entry.date)
        }
        if let snapshot = entry.snapshot, snapshot.isOutOfOffice {
            return "Out of office"
        }
        return entry.snapshot?.presence.displayName ?? "—"
    }

    /// Inverted treatment for the non-clock states: a solid tinted circle
    /// with the glyph punched through as transparent so the watch face
    /// shows through. The corner complication forces a single tint on
    /// both `foregroundStyle` layers, so a stacked dark glyph collapses
    /// into a solid dot — `destinationOut` cuts the glyph shape out
    /// of the circle instead.
    private func cornerBadge(_ symbol: String) -> some View {
        Circle()
            .foregroundStyle(.primary)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .heavy))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: 32, height: 32)
    }

    /// BRB and Away are handled above with a bare `clock.fill` outside
    /// the cutout badge, so they fall through to the question mark here
    /// (defensive; they never actually reach this branch).
    private func cornerSymbol(for presence: Presence) -> String {
        switch presence {
        case .available: return "checkmark"
        case .busy, .doNotDisturb: return "minus"
        case .offline: return "xmark"
        case .beRightBack, .away, .unknown: return "questionmark"
        }
    }
}

struct CheckInWatchCornerWidget: Widget {
    let kind = "CheckInWatchCorner"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchCornerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryCorner])
        .configurationDisplayName("CheckIn Countdown")
        .description("Time until your next meeting.")
    }
}

// MARK: - Rectangular (Smart Stack)

struct WatchRectangularView: View {
    let entry: WatchStatusEntry

    var body: some View {
        if let snapshot = entry.snapshot,
           let meeting = snapshot.currentOrNextMeeting(referenceDate: entry.date) {
            meetingLayout(meeting: meeting, snapshot: snapshot)
        } else if let snapshot = entry.snapshot {
            noMeetingLayout(snapshot: snapshot)
        }
    }

    private func meetingLayout(meeting: SnapshotMeeting, snapshot: CheckInSnapshot) -> some View {
        let start = meeting.start
        let subject = meeting.subject
        let inProgress = start <= entry.date
        let imminent = isMeetingImminent(start, referenceDate: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(inProgress ? .orange : Brand.accent)
                Text(meetingTimeRange(start: meeting.start, end: meeting.end))
                    .foregroundStyle(Brand.textMuted)
                Spacer(minLength: 0)
                presenceGlyph(for: snapshot)
            }
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            Spacer(minLength: 0)
            Text(subject)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(untilTime(start, referenceDate: entry.date))
                    .foregroundStyle(imminent || inProgress ? .orange : Brand.accent)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Label {
                    Text("\(snapshot.unreadEmailCount)")
                } icon: {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Brand.accent)
                }
                Label {
                    Text("\(snapshot.chatCount)")
                } icon: {
                    Image(systemName: "bubble.left.fill")
                        .foregroundStyle(Brand.accent)
                }
            }
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            .monospacedDigit()
        }
    }

    private func noMeetingLayout(snapshot: CheckInSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(Brand.accent)
                Text("No meetings")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                presenceGlyph(for: snapshot)
            }
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Label {
                    Text("\(snapshot.unreadEmailCount)")
                } icon: {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(Brand.accent)
                }
                Label {
                    Text("\(snapshot.chatCount)")
                } icon: {
                    Image(systemName: "bubble.left.fill")
                        .foregroundStyle(Brand.accent)
                }
            }
            .font(.caption2.weight(.semibold))
            .imageScale(.small)
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func presenceGlyph(for snapshot: CheckInSnapshot) -> some View {
        Group {
            if snapshot.isOutOfOffice {
                OutOfOfficeGlyph()
            } else {
                PresenceGlyph(snapshot.presence)
            }
        }
        .font(.subheadline)
        .imageScale(.medium)
    }
}

struct CheckInWatchRectangularWidget: Widget {
    let kind = "CheckInWatchRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchRectangularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryRectangular])
        .configurationDisplayName("CheckIn Status")
        .description("Presence, next meeting, and counts at a glance.")
    }
}

// MARK: - Circular

struct WatchCircularView: View {
    let entry: WatchStatusEntry

    var body: some View {
        ZStack {
            ringForPresence
            Text(unreadDisplay)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
        }
    }

    private var unreadDisplay: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return "\(snapshot.unreadEmailCount)"
    }

    @ViewBuilder
    private var ringForPresence: some View {
        Circle()
            .stroke(ringColor, lineWidth: 3)
    }

    private var ringColor: Color {
        if let snapshot = entry.snapshot, snapshot.isOutOfOffice { return .purple }
        switch entry.snapshot?.presence ?? .unknown {
        case .available: return .green
        case .busy, .doNotDisturb: return .red
        case .beRightBack, .away: return .yellow
        case .offline: return .gray
        case .unknown: return .gray
        }
    }
}

struct CheckInWatchCircularWidget: Widget {
    let kind = "CheckInWatchCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchCircularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryCircular])
        .configurationDisplayName("CheckIn Unread")
        .description("Unread email count in a presence-colored ring.")
    }
}

// MARK: - Inline

struct WatchInlineView: View {
    let entry: WatchStatusEntry

    var body: some View {
        Text(text)
    }

    private var text: String {
        guard let snapshot = entry.snapshot else { return "CheckIn — waiting" }
        if let start = snapshot.nextMeetingStart {
            return "Next meeting \(untilTime(start, referenceDate: entry.date))"
        }
        if snapshot.unreadEmailCount > 0 {
            return "Inbox: \(snapshot.unreadEmailCount) unread"
        }
        return "All clear today"
    }
}

struct CheckInWatchInlineWidget: Widget {
    let kind = "CheckInWatchInline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchStatusProvider()) { entry in
            WatchInlineView(entry: entry)
                .widgetURL(URL(string: "checkin://open"))
        }
        .supportedFamilies([.accessoryInline])
        .configurationDisplayName("CheckIn Line")
        .description("A one-line CheckIn summary across the top of the face.")
    }
}
