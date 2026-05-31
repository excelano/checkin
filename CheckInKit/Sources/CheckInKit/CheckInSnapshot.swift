// CheckInSnapshot.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import WidgetKit

/// Snapshot of CheckIn state written to the App Group on every refresh,
/// for the widget and Control Center controls to read. Trimmed to just
/// what those surfaces can render — they can't authenticate or call
/// Graph, so anything not in this struct is invisible to them.
///
/// Lives in CheckInKit so the app, the widget extension, and any future
/// surface share one definition instead of byte-identical copies.
/// A meeting in the snapshot's today list. Carries enough for any
/// surface to render it as either the active meeting or a later one,
/// so the "current meeting" can advance through the cached list as
/// time passes without a fresh refresh.
public struct SnapshotMeeting: Codable, Hashable {
    public let subject: String
    public let start: Date
    public let end: Date
    public let organizer: String?
    public let joinUrl: String?

    public init(
        subject: String,
        start: Date,
        end: Date,
        organizer: String? = nil,
        joinUrl: String? = nil
    ) {
        self.subject = subject
        self.start = start
        self.end = end
        self.organizer = organizer
        self.joinUrl = joinUrl
    }

    private enum CodingKeys: String, CodingKey {
        case subject, start, end, organizer, joinUrl
    }

    /// Backward-compat decode for snapshots written before `end`,
    /// `organizer`, and `joinUrl` existed. `end` falls back to
    /// `start + 30 min` so meetings still transition at approximately
    /// the right moment during the upgrade window; the optional
    /// fields fall back to nil.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decode(String.self, forKey: .subject)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
            ?? start.addingTimeInterval(30 * 60)
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer)
        joinUrl = try c.decodeIfPresent(String.self, forKey: .joinUrl)
    }
}

public struct CheckInSnapshot: Codable {
    /// When the main app last refreshed and wrote this snapshot.
    public let updatedAt: Date
    /// Subject of the next meeting today, or nil if none remain.
    public let nextMeetingSubject: String?
    /// Start time of the next meeting, or nil if none remain.
    public let nextMeetingStart: Date?
    /// End time of the next meeting, or nil if none remain or the
    /// publisher predates the field. Used to advance the active
    /// meeting through `laterMeetings` as time passes.
    public let nextMeetingEnd: Date?
    /// Organizer name for the next meeting (drives the "with X" line).
    public let nextMeetingOrganizer: String?
    /// Teams join URL for the next meeting (drives the Join pill).
    /// Nil for events without an online meeting attached.
    public let nextMeetingJoinUrl: String?
    /// Number of unread emails in the inbox (total, not just the visible ones).
    public let unreadEmailCount: Int
    /// Number of pending Teams chats waiting on a reply.
    public let chatCount: Int
    /// Last-known Microsoft 365 presence, so controls can show the
    /// current state without a Graph call.
    public let presence: Presence
    /// Whether Outlook automatic replies (Out of Office) are on, so the
    /// OOO control can reflect live state.
    public let isOutOfOffice: Bool
    /// The remaining meetings today after `nextMeeting*`, in chronological
    /// order. Empty when none remain or when an older publisher wrote the
    /// snapshot before this field existed.
    public let laterMeetings: [SnapshotMeeting]

    public init(
        updatedAt: Date,
        nextMeetingSubject: String?,
        nextMeetingStart: Date?,
        nextMeetingEnd: Date?,
        nextMeetingOrganizer: String?,
        nextMeetingJoinUrl: String?,
        unreadEmailCount: Int,
        chatCount: Int,
        presence: Presence,
        isOutOfOffice: Bool,
        laterMeetings: [SnapshotMeeting] = []
    ) {
        self.updatedAt = updatedAt
        self.nextMeetingSubject = nextMeetingSubject
        self.nextMeetingStart = nextMeetingStart
        self.nextMeetingEnd = nextMeetingEnd
        self.nextMeetingOrganizer = nextMeetingOrganizer
        self.nextMeetingJoinUrl = nextMeetingJoinUrl
        self.unreadEmailCount = unreadEmailCount
        self.chatCount = chatCount
        self.presence = presence
        self.isOutOfOffice = isOutOfOffice
        self.laterMeetings = laterMeetings
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case nextMeetingSubject
        case nextMeetingStart
        case nextMeetingEnd
        case nextMeetingOrganizer
        case nextMeetingJoinUrl
        case unreadEmailCount
        case chatCount
        case presence
        case isOutOfOffice
        case laterMeetings
    }

    /// Custom decode so a snapshot written before `laterMeetings` or
    /// `nextMeetingEnd` existed still decodes — those fields fall back
    /// to empty / nil. Without this, the watch (or any consumer)
    /// sitting on an older cached payload would fail to load on the
    /// first launch after the upgrade.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        nextMeetingSubject = try c.decodeIfPresent(String.self, forKey: .nextMeetingSubject)
        nextMeetingStart = try c.decodeIfPresent(Date.self, forKey: .nextMeetingStart)
        nextMeetingEnd = try c.decodeIfPresent(Date.self, forKey: .nextMeetingEnd)
        nextMeetingOrganizer = try c.decodeIfPresent(String.self, forKey: .nextMeetingOrganizer)
        nextMeetingJoinUrl = try c.decodeIfPresent(String.self, forKey: .nextMeetingJoinUrl)
        unreadEmailCount = try c.decode(Int.self, forKey: .unreadEmailCount)
        chatCount = try c.decode(Int.self, forKey: .chatCount)
        presence = try c.decode(Presence.self, forKey: .presence)
        isOutOfOffice = try c.decode(Bool.self, forKey: .isOutOfOffice)
        laterMeetings = try c.decodeIfPresent([SnapshotMeeting].self, forKey: .laterMeetings) ?? []
    }

    /// A copy with only the presence and Out-of-Office fields replaced.
    /// Lets the app patch the last-written snapshot after an intent
    /// mutation — including when it was background-launched and has no
    /// fresh summary to build a full snapshot from.
    public func settingStatus(presence: Presence, isOutOfOffice: Bool) -> CheckInSnapshot {
        CheckInSnapshot(
            updatedAt: updatedAt,
            nextMeetingSubject: nextMeetingSubject,
            nextMeetingStart: nextMeetingStart,
            nextMeetingEnd: nextMeetingEnd,
            nextMeetingOrganizer: nextMeetingOrganizer,
            nextMeetingJoinUrl: nextMeetingJoinUrl,
            unreadEmailCount: unreadEmailCount,
            chatCount: chatCount,
            presence: presence,
            isOutOfOffice: isOutOfOffice,
            laterMeetings: laterMeetings
        )
    }

    /// Today's full meeting list reconstructed from the snapshot —
    /// the original `nextMeeting*` fields packaged as a `SnapshotMeeting`,
    /// followed by `laterMeetings` in chronological order. Empty when no
    /// meetings were recorded. Internal building block for the helpers
    /// that pick the currently-active meeting and the remaining list.
    private func todayMeetings() -> [SnapshotMeeting] {
        var all: [SnapshotMeeting] = []
        if let subject = nextMeetingSubject, let start = nextMeetingStart {
            let end = nextMeetingEnd ?? start.addingTimeInterval(30 * 60)
            all.append(SnapshotMeeting(
                subject: subject,
                start: start,
                end: end,
                organizer: nextMeetingOrganizer,
                joinUrl: nextMeetingJoinUrl
            ))
        }
        all.append(contentsOf: laterMeetings)
        return all
    }

    /// The meeting that's currently active or coming up next, given a
    /// reference date. Walks `todayMeetings()` and returns the first
    /// entry whose end is in the future. Lets surfaces advance through
    /// the cached meeting list as the day progresses without needing
    /// a fresh Graph refresh — back-to-back meetings transition the
    /// moment the previous one ends.
    public func currentOrNextMeeting(referenceDate: Date) -> SnapshotMeeting? {
        todayMeetings().first { $0.end > referenceDate }
    }

    /// The meetings remaining after the currently-active or next one —
    /// drives the "Later Today" list. Returns whatever's left in the
    /// future-tense slice once the active meeting has been removed.
    public func remainingLaterMeetings(referenceDate: Date) -> [SnapshotMeeting] {
        let upcoming = todayMeetings().filter { $0.end > referenceDate }
        return Array(upcoming.dropFirst())
    }

    /// Future meeting start times today, used by widget timeline
    /// providers to add re-render entries at each transition point so
    /// the widget swaps to the right meeting at the exact moment one
    /// starts. Filters to dates strictly after `referenceDate`.
    public func upcomingMeetingStartDates(after referenceDate: Date) -> [Date] {
        todayMeetings()
            .map(\.start)
            .filter { $0 > referenceDate }
    }

    /// Decode the snapshot last written to an App Group, or nil if none
    /// is stored yet (or it can't be opened/decoded). The single read
    /// path shared by the widget timeline, the widget's status actions,
    /// the Control Center value providers, and the app's intent-driven
    /// patch. Watch surfaces pass `watchAppGroupIdentifier` to read the
    /// snapshot pushed from the phone over WatchConnectivity.
    public static func loadFromAppGroup(suite: String = appGroupIdentifier) -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: suite),
              let data = defaults.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
    }

    /// Encode and write the snapshot to an App Group. Returns `true` on
    /// success so callers can log a failure with their own logger. The
    /// single write path shared by the app's refresh, the app's
    /// intent-driven patch, the widget's status actions, and the watch's
    /// session receiver (which passes `watchAppGroupIdentifier`).
    @discardableResult
    public func saveToAppGroup(suite: String = appGroupIdentifier) -> Bool {
        guard let data = try? JSONEncoder().encode(self),
              let defaults = UserDefaults(suiteName: suite) else {
            return false
        }
        defaults.set(data, forKey: Self.userDefaultsKey)
        return true
    }

    /// Reload the widget timelines and (iOS 18+) the Out-of-Office Control
    /// Center toggle. Surfaces drive themselves from the App Group snapshot,
    /// so a reload after a write is what makes a change visible.
    public static func reloadStatusSurfaces() {
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlKind.outOfOffice)
        }
        #endif
    }

    /// Patch the last-written snapshot's presence/OOO fields and reload
    /// surfaces. Used after an intent-driven mutation when the caller
    /// doesn't have a full summary to rebuild the snapshot from — it
    /// updates the fields the surfaces care about and leaves the rest
    /// alone. Reloads even if no snapshot was found, so an empty App
    /// Group at least nudges the surfaces to refetch.
    public static func patchAndReload(presence: Presence, isOutOfOffice: Bool) {
        if let existing = loadFromAppGroup() {
            existing
                .settingStatus(presence: presence, isOutOfOffice: isOutOfOffice)
                .saveToAppGroup()
        }
        reloadStatusSurfaces()
    }

    /// Default auto-reply text used only when Graph reports an empty
    /// message at OOO toggle-on time. Anything the user previously set
    /// (via Outlook web, for instance) is preserved.
    public static let defaultOutOfOfficeMessage =
        "I'm currently out of the office and will respond when I return."

    /// Identifier shared between the main app and the widget extension
    /// for the App Group container both can read/write.
    public static let appGroupIdentifier = "group.com.excelano.checkin"
    /// Identifier shared between the watch app and its widget extension.
    /// Distinct from the phone's group because App Groups don't sync
    /// across devices — the watch keeps its own copy of the snapshot
    /// after `WatchSessionReceiver` decodes the WatchConnectivity push.
    public static let watchAppGroupIdentifier = "group.com.excelano.checkin.watch"
    /// Key inside the App Group's UserDefaults where the encoded
    /// snapshot is stored.
    public static let userDefaultsKey = "snapshot"
    /// App Group keys for the MSAL config the widget needs to build an
    /// instance matching the app's, so it can read the shared token cache.
    /// The app writes these; a custom Azure registration set in the app's
    /// private UserDefaults wouldn't otherwise be visible to the extension.
    public static let effectiveClientIDKey = "effectiveClientID"
    public static let effectiveAuthorityKey = "effectiveAuthority"
}
