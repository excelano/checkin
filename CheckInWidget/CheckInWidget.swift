// CheckInWidget.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import WidgetKit
import SwiftUI
import AppIntents
import CheckInGraph
import CheckInKit
import os

private let log = Logger(subsystem: "com.excelano.checkin", category: "widget")

/// Furthest minute the timeline pre-renders, so the "in N min" countdown
/// updates without a Graph round-trip until WidgetKit reloads us.
private let timelineHorizonMinutes = 60

struct CheckInEntry: TimelineEntry {
    let date: Date
    let snapshot: CheckInSnapshot?
}

struct CheckInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CheckInEntry {
        CheckInEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CheckInEntry) -> Void) {
        completion(CheckInEntry(date: Date(), snapshot: CheckInSnapshot.loadFromAppGroup() ?? previewSnapshot))
    }

    /// Generate one entry per minute up to `timelineHorizonMinutes` out so the
    /// "in X min" countdown stays accurate without requiring a widget refresh.
    /// At the horizon, iOS reloads; the main app also reloads us proactively on
    /// every refresh. On each reload we fetch a fresh snapshot (next meeting,
    /// counts, presence, OOO) straight from Graph, so the widget stays current
    /// between app launches.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CheckInEntry>) -> Void) {
        Task {
            let snapshot = await liveSnapshot()
            let now = Date()
            var seen = Set<Date>()
            var entries: [CheckInEntry] = []
            for minute in 0...timelineHorizonMinutes {
                let date = now.addingTimeInterval(TimeInterval(minute * 60))
                entries.append(CheckInEntry(date: date, snapshot: snapshot))
                seen.insert(date)
            }
            // Splice in extra entries at each upcoming meeting start so
            // the meeting block flips to the right meeting at the exact
            // transition moment rather than waiting for the next minute
            // boundary. Skip any that already fall on a minute tick.
            if let snapshot {
                for date in snapshot.upcomingMeetingStartDates(after: now) where !seen.contains(date) {
                    entries.append(CheckInEntry(date: date, snapshot: snapshot))
                }
                entries.sort { $0.date < $1.date }
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    /// Lead time inside which a cached snapshot still counts as "fresh enough"
    /// to skip a Graph round-trip. iOS may call `getTimeline` more often than
    /// the app refreshes — when the app just wrote a snapshot, that cached
    /// copy beats an immediate refetch that would otherwise burn battery and
    /// Graph quota for the same data.
    private static let cachedSnapshotMaxAge: TimeInterval = 60

    /// A snapshot for the widget timeline. Prefers the cached App Group copy
    /// when it's recent enough; otherwise fetches directly from Graph in the
    /// extension and persists the result so future reads share the same
    /// "last refresh" view as the app. On any Graph failure (no token,
    /// offline, server error) we fall back to whatever cached copy exists,
    /// so the widget never blocks or blanks on the network.
    private func liveSnapshot() async -> CheckInSnapshot? {
        let cached = CheckInSnapshot.loadFromAppGroup()
        if let cached, Date().timeIntervalSince(cached.updatedAt) < Self.cachedSnapshotMaxAge {
            return cached
        }
        let core = GraphCore(tokenProvider: WidgetTokenProvider())
        do {
            let fresh = try await core.fetchSnapshot()
            fresh.saveToAppGroup()
            return fresh
        } catch {
            log.error("widget self-fetch failed: \(error.localizedDescription, privacy: .public)")
            return cached
        }
    }

    private var previewSnapshot: CheckInSnapshot {
        CheckInSnapshot(
            updatedAt: Date(),
            nextMeetingSubject: "Status Meeting",
            nextMeetingStart: Date().addingTimeInterval(30 * 60),
            nextMeetingEnd: Date().addingTimeInterval(60 * 60),
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

    /// Bottom row of the meeting block: the countdown + organizer until
    /// the meeting is within `joinPillLeadTime` of starting, then the
    /// Join button takes the row (dropping the organizer). In-person
    /// meetings (no join URL) keep showing the countdown + organizer
    /// all the way through.
    @ViewBuilder
    private func meetingBottomRow(_ meeting: SnapshotMeeting) -> some View {
        let secondsToStart = meeting.start.timeIntervalSince(entry.date)
        if secondsToStart <= joinPillLeadTime,
           let urlString = meeting.joinUrl,
           let url = teamsJoinURL(from: urlString) {
            joinPill(url: url)
        } else {
            let imminent = isMeetingImminent(meeting.start, referenceDate: entry.date)
            let inProgress = meeting.start <= entry.date
            HStack(spacing: 8) {
                Text(untilTime(meeting.start, referenceDate: entry.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(imminent || inProgress ? .orange : Brand.accent)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let organizer = meeting.organizer, !organizer.isEmpty {
                    Text("with \(organizer)")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private var meetingBlock: some View {
        // Pick the currently-active or next meeting from the cached
        // today list using the entry's date — back-to-back meetings
        // transition at the per-minute timeline tick without needing
        // a refresh.
        if let snapshot = entry.snapshot,
           let meeting = snapshot.currentOrNextMeeting(referenceDate: entry.date) {
            meetingHeader(meeting)
            Text(meeting.subject)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.tail)
            meetingBottomRow(meeting)
        } else if entry.snapshot != nil {
            Text("No more meetings today")
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

    /// Top row of the meeting block: calendar icon + the meeting's time
    /// range. Matches the watch glance and rectangular widget so the
    /// surfaces read alike. The calendar tints orange once the meeting
    /// is imminent or live, matching the countdown's orange below.
    private func meetingHeader(_ meeting: SnapshotMeeting) -> some View {
        let inProgress = meeting.start <= entry.date
        let imminent = isMeetingImminent(meeting.start, referenceDate: entry.date)
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(inProgress || imminent ? .orange : Brand.accent)
            Text(meetingTimeRange(start: meeting.start, end: meeting.end))
                .font(.subheadline)
                .foregroundStyle(Brand.textMuted)
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
                intent: SetPresenceIntent(status: isAvailable ? .busy : .available)
            ) {
                HStack(spacing: 6) {
                    if isOutOfOffice {
                        OutOfOfficeGlyph()
                            .font(.subheadline)
                    } else {
                        PresenceGlyph(presence)
                            .font(.subheadline)
                    }
                    Text(isOutOfOffice ? "Out of Office" : presence.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .toggleStyle(AvailabilityToggleStyle())
            .accessibilityLabel(isOutOfOffice
                ? "Out of office"
                : "Presence: \(presence.displayName)")
            .accessibilityHint(isAvailable
                ? "Set your status to Busy"
                : "Set your status to Available")
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
            nextMeetingEnd: .now.addingTimeInterval(38 * 60),
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
            nextMeetingEnd: nil,
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
