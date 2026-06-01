// GraphSnapshot.swift
// CheckInGraph
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation

/// Assembles a `CheckInSnapshot` directly from Graph, so the widget extension
/// can refresh itself between app launches instead of only showing what the
/// app last wrote. Decodes lean shapes (only the fields the snapshot needs)
/// rather than the app's rich `Meeting`/`Email`/`ChatMessage` models, which
/// stay app-side. Field semantics match `Inbox.publishStatusSnapshot` so a
/// self-fetched snapshot reads the same as an app-written one.
public extension GraphCore {
    /// Fetch everything the snapshot surfaces (today's meetings, unread email
    /// count, pending chat count, presence, Out of Office) and assemble it.
    /// Calls run sequentially; the widget's timeline-reload budget, not these
    /// round-trips, is the binding constraint.
    func fetchSnapshot() async throws -> CheckInSnapshot {
        let meetings = try await fetchTodayMeetings()
        let unreadEmailCount = try await fetchUnreadEmailCount()
        let chatCount = try await fetchPendingChatCount()
        let presence = try await fetchPresence().presence
        let isOutOfOffice = try await fetchAutomaticRepliesEnabled()

        let nextMeeting = meetings.first
        let later = Array(meetings.dropFirst())

        return CheckInSnapshot(
            updatedAt: Date(),
            nextMeetingSubject: nextMeeting?.subject,
            nextMeetingStart: nextMeeting?.start,
            nextMeetingEnd: nextMeeting?.end,
            nextMeetingOrganizer: nextMeeting?.organizer,
            nextMeetingJoinUrl: nextMeeting?.joinUrl,
            unreadEmailCount: unreadEmailCount,
            chatCount: chatCount,
            presence: presence,
            isOutOfOffice: isOutOfOffice,
            laterMeetings: later
        )
    }

    /// Attendable meetings remaining today in chronological order, mirroring
    /// `GraphClient.todaysMeetings`'s window and filters (skip cancelled and
    /// declined). Returns enough info to populate both the "next meeting"
    /// slot and the "later today" tail, with end times so consumers can
    /// advance through the list as meetings pass.
    private func fetchTodayMeetings() async throws -> [CheckInKit.SnapshotMeeting] {
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let formatter = ISO8601DateFormatter()

        let data: GraphList<SnapshotEvent> = try await get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: now),
            "endDateTime": formatter.string(from: endOfDay),
            "$top": "10",
            "$orderby": "start/dateTime",
            "$select": "subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled"
        ])

        return data.value
            .filter { !($0.isCancelled ?? false) && $0.responseStatus?.response != "declined" }
            .map { event -> CheckInKit.SnapshotMeeting in
                CheckInKit.SnapshotMeeting(
                    subject: event.subject,
                    start: parseGraphDate(event.start.dateTime, timeZone: event.start.timeZone),
                    end: parseGraphDate(event.end.dateTime, timeZone: event.end.timeZone),
                    organizer: event.organizer.emailAddress.name,
                    joinUrl: event.onlineMeeting?.joinUrl
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// Total unread inbox count. `$count=true` requires the
    /// `ConsistencyLevel: eventual` header; `$top=1` keeps the body tiny since
    /// only the count is used.
    private func fetchUnreadEmailCount() async throws -> Int {
        let data: GraphList<SnapshotID> = try await get(
            "/me/mailFolders/inbox/messages",
            query: [
                "$filter": "isRead eq false",
                "$top": "1",
                "$count": "true",
                "$select": "id"
            ],
            headers: ["ConsistencyLevel": "eventual"]
        )
        return data.count ?? data.value.count
    }

    /// Count of chats with unread activity, applying the same filter as
    /// `GraphClient.pendingChats`: skip hidden chats and non-message events,
    /// and count a chat only when it's unread per the user's viewpoint. No
    /// age cutoff — an unread chat counts however old its last message is.
    /// The self-filter on participant names that `pendingChats` does isn't
    /// needed here — it affects display, not the count.
    private func fetchPendingChatCount() async throws -> Int {
        let data: GraphList<SnapshotChat> = try await get("/me/chats", query: [
            "$select": "id,lastMessagePreview,viewpoint",
            "$expand": "lastMessagePreview",
            "$top": "50"
        ])

        var count = 0
        for chat in data.value {
            if chat.viewpoint?.isHidden == true { continue }
            guard let preview = chat.lastMessagePreview else { continue }
            guard preview.messageType.isEmpty || preview.messageType == "message" else { continue }
            guard preview.from?.user != nil else { continue }
            guard let sent = parseISO8601(preview.createdDateTime) else { continue }
            let lastRead = (chat.viewpoint?.lastMessageReadDateTime)
                .flatMap(parseISO8601) ?? .distantPast
            guard sent > lastRead else { continue }
            count += 1
        }
        return count
    }
}

// MARK: - Lean decode shapes (module-internal)

struct SnapshotID: Decodable {
    let id: String
}

struct SnapshotEvent: Decodable {
    let subject: String
    let organizer: SnapshotOrganizer
    let start: SnapshotDateTime
    let end: SnapshotDateTime
    let onlineMeeting: SnapshotOnlineMeeting?
    let responseStatus: SnapshotResponseStatus?
    let isCancelled: Bool?
}

struct SnapshotOrganizer: Decodable {
    let emailAddress: SnapshotEmailAddress
}

struct SnapshotEmailAddress: Decodable {
    let name: String
}

struct SnapshotDateTime: Decodable {
    let dateTime: String
    let timeZone: String
}

struct SnapshotOnlineMeeting: Decodable {
    let joinUrl: String?
}

struct SnapshotResponseStatus: Decodable {
    let response: String
}

struct SnapshotChat: Decodable {
    let lastMessagePreview: SnapshotChatPreview?
    let viewpoint: SnapshotViewpoint?
}

struct SnapshotChatPreview: Decodable {
    let createdDateTime: String
    let messageType: String
    let from: SnapshotChatFrom?
}

struct SnapshotChatFrom: Decodable {
    let user: SnapshotChatUser?
}

struct SnapshotChatUser: Decodable {
    let id: String
}

struct SnapshotViewpoint: Decodable {
    let isHidden: Bool?
    let lastMessageReadDateTime: String?
}
