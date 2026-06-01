// GraphClient.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInGraph
import CheckInKit
import Foundation
import os

/// Bridges the app's `AuthService` to `GraphCore`'s token-provider seam.
/// Keeps Graph's HTTP layer free of any MSAL dependency: `GraphCore` asks for
/// a token, this hands back whatever the app's auth flow produces.
private struct AppTokenProvider: GraphTokenProvider {
    let authService: AuthService
    let enableTeams: Bool

    func graphAccessToken() async throws -> String {
        try await authService.acquireTokenSilently(enableTeams: enableTeams)
    }
}

final class GraphClient {
    /// Shared Graph access layer (HTTP plumbing, auth-header injection,
    /// transient-retry, presence/OOO writes). The app's rich reads ride its
    /// HTTP primitives; the presence/OOO methods below forward to it.
    private let core: GraphCore
    private var userID = ""
    private var userMail = ""

    init(authService: AuthService, enableTeams: Bool) {
        self.core = GraphCore(
            tokenProvider: AppTokenProvider(authService: authService, enableTeams: enableTeams)
        )
    }

    /// Fetch the signed-in user's ID and mail address. ID powers the Teams
    /// pending-chat self-filter; mail powers external-sender detection.
    /// Some accounts (personal/MSA, occasionally) don't populate `mail`,
    /// so we fall back to `userPrincipalName`.
    func fetchUserID() async throws {
        let data: UserResponse = try await core.get("/me", query: ["$select": "id,mail,userPrincipalName"])
        userID = data.id
        userMail = data.mail ?? data.userPrincipalName ?? ""
    }

    /// Drop the cached user identity. Called when the signed-in account
    /// changes so the next refresh re-fetches the new user's id/mail
    /// instead of reusing the previous user's.
    func clearUser() {
        userID = ""
        userMail = ""
    }

    /// Domain portion of the signed-in user's mail address (lowercased).
    /// Empty until `fetchUserID` runs successfully.
    var userMailDomain: String {
        guard let atIdx = userMail.firstIndex(of: "@") else { return "" }
        return String(userMail[userMail.index(after: atIdx)...]).lowercased()
    }

    /// Graph user id of the signed-in account. Empty until `fetchUserID`
    /// runs. Exposed for callers (Inbox) that need to assemble a
    /// `teamworkUserIdentity` body — see `markChatRead` / `markChatUnread`.
    var currentUserID: String { userID }

    /// Mail address of the signed-in account. Empty until `fetchUserID`
    /// runs. Used to filter the user out of recipient lists in the UI
    /// so they don't see themselves in the "also to" line.
    var currentUserMail: String { userMail }

    /// Fetch today's remaining meetings using calendarView (not /events,
    /// so recurring meetings are properly expanded). Returns the next
    /// meeting plus the rest of today's attendable meetings, ordered by
    /// start time. Window is `[now, start of tomorrow local]`, so we
    /// don't bleed into tomorrow's calendar.
    func todaysMeetings() async throws -> (next: Meeting?, laterToday: [Meeting]) {
        let window = todayMeetingWindow()
        let formatter = ISO8601DateFormatter()

        let data: GraphList<CalendarEventResponse> = try await core.get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: window.start),
            "endDateTime": formatter.string(from: window.end),
            "$top": "10",
            "$orderby": "start/dateTime",
            "$select": "id,subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled,iCalUId"
        ])

        // `isAttendableMeeting` (CheckInGraph) skips cancelled and declined
        // events; shared with the widget/watch snapshot so both agree.
        let attendable = data.value
            .filter { isAttendableMeeting(isCancelled: $0.isCancelled, response: $0.responseStatus?.response) }
            .map { e -> (event: CalendarEventResponse, start: Date, end: Date) in
                (e,
                 parseGraphDate(e.start.dateTime, timeZone: e.start.timeZone),
                 parseGraphDate(e.end.dateTime, timeZone: e.end.timeZone))
            }
        guard !attendable.isEmpty else { return (nil, []) }

        // Conflict = any other attendable event whose time range overlaps
        // this one. Half-open intervals so back-to-back meetings (one
        // ending exactly when the next starts) don't count. Computed for
        // every meeting (n²/2 with n ≤ 10).
        let meetings: [Meeting] = attendable.enumerated().map { (i, t) in
            let response = MeetingResponse(rawValue: t.event.responseStatus?.response ?? "") ?? .none
            let hasConflict = attendable.enumerated().contains { (j, other) in
                i != j && other.start < t.end && t.start < other.end
            }
            return Meeting(
                id: t.event.id,
                subject: t.event.subject,
                organizer: t.event.organizer.emailAddress.name,
                organizerEmail: t.event.organizer.emailAddress.address,
                start: t.start,
                end: t.end,
                joinUrl: t.event.onlineMeeting?.joinUrl,
                responseStatus: response,
                hasConflict: hasConflict,
                iCalUId: t.event.iCalUId
            )
        }

        return (meetings.first, Array(meetings.dropFirst()))
    }

    /// Calendar events overlapping the given range, plain mapping (no
    /// conflict computation). Used purely as a reference pool for
    /// conflict detection on invite-email RSVP — so a plain calendar
    /// event that overlaps an invite can flag the invite as
    /// conflicting. Not displayed anywhere in the UI. Caps at 100
    /// events as a guard against multi-week ranges with very dense
    /// calendars.
    func eventsInRange(start: Date, end: Date) async throws -> [Meeting] {
        let formatter = ISO8601DateFormatter()
        let data: GraphList<CalendarEventResponse> = try await core.get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: start),
            "endDateTime": formatter.string(from: end),
            "$top": "100",
            "$orderby": "start/dateTime",
            "$select": "id,subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled,iCalUId"
        ])

        return data.value
            .filter { isAttendableMeeting(isCancelled: $0.isCancelled, response: $0.responseStatus?.response) }
            .map { e in
                Meeting(
                    id: e.id,
                    subject: e.subject,
                    organizer: e.organizer.emailAddress.name,
                    organizerEmail: e.organizer.emailAddress.address,
                    start: parseGraphDate(e.start.dateTime, timeZone: e.start.timeZone),
                    end: parseGraphDate(e.end.dateTime, timeZone: e.end.timeZone),
                    joinUrl: e.onlineMeeting?.joinUrl,
                    responseStatus: MeetingResponse(rawValue: e.responseStatus?.response ?? "") ?? .none,
                    hasConflict: false,
                    iCalUId: e.iCalUId
                )
            }
    }

    /// DELETE an event. For invitation/personal events this removes it
    /// from the user's calendar. For events the user organizes Graph
    /// also sends cancellations to attendees — the caller is expected to
    /// gate that case.
    func deleteEvent(id: String) async throws {
        try await core.delete("/me/events/\(id)")
    }

    /// Current Microsoft 365 presence plus the custom status message.
    /// Forwards to `GraphCore`.
    func fetchPresence() async throws -> (presence: Presence, statusMessage: String) {
        try await core.fetchPresence()
    }

    /// Pin the user's preferred presence (pass `.unknown` plus
    /// `clearUserPreferredPresence` to drop it). Forwards to `GraphCore`.
    func setUserPreferredPresence(_ presence: Presence) async throws {
        try await core.setUserPreferredPresence(presence)
    }

    /// Drop the user-preferred presence so Teams resumes auto-detection.
    func clearUserPreferredPresence() async throws {
        try await core.clearUserPreferredPresence()
    }

    /// Set (or clear, with an empty string) the user's Teams status message.
    func setStatusMessage(_ content: String) async throws {
        try await core.setStatusMessage(content)
    }

    /// Re-up CheckIn's presence session so Graph keeps honoring the
    /// preferred-presence override. Offline is skipped inside `GraphCore`.
    func setSessionPresence(sessionId: String, presence: Presence) async throws {
        try await core.setSessionPresence(sessionId: sessionId, presence: presence)
    }

    /// Whether Out-of-Office (Outlook automatic replies) is currently on.
    func fetchOutOfOfficeEnabled() async throws -> Bool {
        try await core.fetchAutomaticRepliesEnabled()
    }

    /// Turn auto-replies on, preserving any existing reply text.
    func enableAutomaticReplies(defaultMessage: String) async throws {
        try await core.enableAutomaticReplies(defaultMessage: defaultMessage)
    }

    /// Turn auto-replies off.
    func disableAutomaticReplies() async throws {
        try await core.disableAutomaticReplies()
    }

    /// Accept/tentative/decline an event. Graph returns 202 with no body.
    /// `sendResponse: true` matches Outlook's default behavior — the
    /// organizer's tracking is updated.
    func respondToMeeting(id: String, response: MeetingResponse) async throws {
        let action: String
        switch response {
        case .accepted: action = "accept"
        case .tentativelyAccepted: action = "tentativelyAccept"
        case .declined: action = "decline"
        case .none, .notResponded, .organizer:
            return
        }
        try await core.post("/me/events/\(id)/\(action)", body: RsvpBody(sendResponse: true))
    }

    /// Pull the iCalUId of the meeting referenced by an invite email.
    /// Reads `PidLidGlobalObjectId` (MAPI named property
    /// {6ED8DA90-…}/0x3) via `singleValueExtendedProperties` and
    /// converts its base64 binary to the uppercase hex form Graph uses
    /// for `event.iCalUId`. Used as the deterministic join key from an
    /// invitation eventMessage to its calendar event — replaces the
    /// fragile subject+time match for cases the matcher can't resolve.
    /// Returns nil on any failure or when Graph omits the property.
    func fetchInviteICalUId(messageId: String) async -> String? {
        do {
            let response: MessageSingleValueExtPropResponse = try await core.get(
                "/me/messages/\(messageId)",
                query: [
                    "$expand": "singleValueExtendedProperties($filter=id eq 'Binary {6ED8DA90-450B-101B-98DA-00AA003F1305} Id 0x3')"
                ]
            )
            guard let base64 = response.singleValueExtendedProperties?.first?.value,
                  let data = Data(base64Encoded: base64) else { return nil }
            return data.map { String(format: "%02X", $0) }.joined()
        } catch {
            Logger(subsystem: "com.excelano.checkin", category: "graph")
                .error("fetchInviteICalUId failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Returns the newest unread emails (up to `top`, default 20) along
    /// with the total unread count. `$count=true` requires the
    /// `ConsistencyLevel: eventual` header. The
    /// `microsoft.graph.eventMessage/*` casts pull subtype fields for
    /// invite/response messages — `meetingMessageType` distinguishes them
    /// and `startDateTime`/`endDateTime` provide the meeting time without
    /// needing a second fetch. `$expand=event` is intentionally avoided:
    /// Graph rejects it in combination with the advanced-query trio
    /// (`$filter` + `$count` + `ConsistencyLevel: eventual`), and even
    /// in a single-resource GET it returns empty-stub events for
    /// future-dated invitations (observed via diagnostic). Matching the
    /// resulting `meetingStart` against `calendarView` recovers the real
    /// event id.
    func unreadEmails(top: Int = 20) async throws -> (emails: [Email], totalCount: Int) {
        let data: GraphList<EmailResponse> = try await core.get(
            "/me/mailFolders/inbox/messages",
            query: [
                "$filter": "isRead eq false",
                "$orderby": "receivedDateTime desc",
                "$top": "\(top)",
                "$count": "true",
                "$select": "id,subject,from,toRecipients,ccRecipients,bodyPreview,receivedDateTime,flag,inferenceClassification,internetMessageHeaders,hasAttachments,microsoft.graph.eventMessage/meetingMessageType,microsoft.graph.eventMessage/startDateTime,microsoft.graph.eventMessage/endDateTime"
            ],
            headers: ["ConsistencyLevel": "eventual"]
        )

        let emails = data.value.map { e in
            let isMailingList = (e.internetMessageHeaders ?? []).contains { h in
                h.name.caseInsensitiveCompare("List-Unsubscribe") == .orderedSame
            }
            let meetingStart = e.startDateTime.map { parseGraphDate($0.dateTime, timeZone: $0.timeZone) }
            let meetingEnd = e.endDateTime.map { parseGraphDate($0.dateTime, timeZone: $0.timeZone) }
            let toRecipients = (e.toRecipients ?? []).compactMap(Self.makeRecipient)
            let ccRecipients = (e.ccRecipients ?? []).compactMap(Self.makeRecipient)
            return Email(
                id: e.id,
                subject: e.subject,
                from: e.from.emailAddress.name,
                fromAddress: e.from.emailAddress.address ?? "",
                preview: cleanEmailPreview(e.bodyPreview),
                received: parseISO8601(e.receivedDateTime) ?? Date(),
                isFlagged: e.flag?.flagStatus == "flagged",
                inferenceClassification: e.inferenceClassification,
                meetingMessageType: e.meetingMessageType,
                meetingStart: meetingStart,
                meetingEnd: meetingEnd,
                isMailingList: isMailingList,
                toRecipients: toRecipients,
                ccRecipients: ccRecipients,
                hasAttachments: e.hasAttachments ?? false
            )
        }
        return (emails, data.count ?? emails.count)
    }

    /// Map a Graph recipient envelope into our `Recipient` model. Skips
    /// envelopes that carry no address — those are unusable for both
    /// reply targeting and display.
    private static func makeRecipient(_ envelope: EmailAddressEnvelope) -> Recipient? {
        guard let address = envelope.emailAddress.address, !address.isEmpty else { return nil }
        return Recipient(name: envelope.emailAddress.name, address: address)
    }

    /// Mail.ReadWrite required. Idempotent.
    func markEmailRead(id: String) async throws {
        try await core.patch("/me/messages/\(id)", body: MarkReadBody(isRead: true))
    }

    /// IDs of Inbox messages already marked read whose `receivedDateTime`
    /// falls within today (local midnight → tomorrow's local midnight).
    /// Used by the "Mark today's emails unread" bulk action so the user
    /// can re-surface a day's worth of mail that got cleared elsewhere
    /// (Outlook on the web, another mobile client). Scoped to the Inbox
    /// folder so Sent Items, Drafts, and Archive are excluded. Caps at
    /// 200 — that covers any normal day with margin and keeps the
    /// response small.
    func idsOfReadEmailsReceivedToday() async throws -> [String] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: todayStart)
        let end = formatter.string(from: tomorrowStart)

        let data: GraphList<EmailIdResponse> = try await core.get(
            "/me/mailFolders/inbox/messages",
            query: [
                "$filter": "isRead eq true and receivedDateTime ge \(start) and receivedDateTime lt \(end)",
                "$top": "200",
                "$select": "id"
            ]
        )
        return data.value.map(\.id)
    }

    /// IDs of read, flagged messages in the Inbox. Backs the "Mark unread:
    /// flagged emails" bulk action, which resurfaces follow-up items that
    /// were read elsewhere (Outlook web, another client) so they reappear
    /// in CheckIn's unread list. Same Inbox scoping and 200-item cap as
    /// `idsOfReadEmailsReceivedToday`.
    func idsOfReadFlaggedEmails() async throws -> [String] {
        let data: GraphList<EmailIdResponse> = try await core.get(
            "/me/mailFolders/inbox/messages",
            query: [
                "$filter": "isRead eq true and flag/flagStatus eq 'flagged'",
                "$top": "200",
                "$select": "id"
            ]
        )
        return data.value.map(\.id)
    }

    /// Mail.ReadWrite required. Used to undo an accidental Mark Read or
    /// to drive the explicit Mark Unread button on the preview sheet.
    func markEmailUnread(id: String) async throws {
        try await core.patch("/me/messages/\(id)", body: MarkReadBody(isRead: false))
    }

    /// Fetch the full plain-text body of a message for the preview sheet.
    /// `Prefer: outlook.body-content-type="text"` tells Graph to return
    /// text in `body.content` rather than HTML, which avoids us having
    /// to render HTML for the preview. Mail.Read or Mail.ReadWrite
    /// covers this.
    func fetchEmailBody(id: String) async throws -> String {
        let data: EmailBodyResponse = try await core.get(
            "/me/messages/\(id)",
            query: ["$select": "body"],
            headers: ["Prefer": "outlook.body-content-type=\"text\""]
        )
        return data.body.content
    }

    /// Send a reply-all to a message. Graph stitches the user's comment
    /// onto the original conversation with proper `In-Reply-To` /
    /// `References` headers and includes the quoted history. For
    /// single-recipient messages this degrades gracefully to reply-to-
    /// sender. Mail.Send required.
    func replyAllToEmail(id: String, comment: String) async throws {
        try await core.post("/me/messages/\(id)/replyAll", body: ReplyCommentBody(comment: comment))
    }

    /// Post a new message into an existing chat thread. Chat.ReadWrite
    /// covers this — `ChatMessage.Send` is a more granular scope but
    /// the broader one we already request is a superset.
    func sendChatMessage(chatId: String, content: String) async throws {
        try await core.post(
            "/me/chats/\(chatId)/messages",
            body: ChatMessageSendBody(
                body: ChatMessageSendContent(contentType: "text", content: content)
            )
        )
    }

    /// Mark a chat as read for the signed-in user — advances the
    /// per-user `viewpoint.lastMessageReadDateTime`, which is what we
    /// now key the chat-list filter off. Chat.ReadWrite required.
    func markChatRead(chatId: String, userId: String, tenantId: String) async throws {
        try await core.post(
            "/chats/\(chatId)/markChatReadForUser",
            body: MarkChatReadBody(
                user: TeamworkUserIdentityBody(id: userId, tenantId: tenantId)
            )
        )
    }

    /// Mark a chat as unread for the signed-in user. Setting
    /// `lastMessageReadDateTime` to a distant past timestamp marks the
    /// whole chat unread (Graph's filter then treats the latest message
    /// as newer than the read mark). Chat.ReadWrite required.
    func markChatUnread(chatId: String, userId: String, tenantId: String) async throws {
        try await core.post(
            "/chats/\(chatId)/markChatUnreadForUser",
            body: MarkChatUnreadBody(
                user: TeamworkUserIdentityBody(id: userId, tenantId: tenantId)
            )
        )
    }

    /// Chat ids whose last message arrived within today (local midnight
    /// to tomorrow's local midnight) and are currently read for the
    /// signed-in user. Drives the "Mark today's chats unread" empty-
    /// state action. Filtering is client-side because Graph doesn't
    /// expose `viewpoint.lastMessageReadDateTime` as a $filter field.
    func idsOfReadChatsToday() async throws -> [String] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()

        let data: GraphList<ChatResponse> = try await core.get("/me/chats", query: [
            "$select": "id,lastMessagePreview,viewpoint",
            "$expand": "lastMessagePreview",
            "$top": "50"
        ])

        var ids: [String] = []
        for chat in data.value {
            if chat.viewpoint?.isHidden == true { continue }
            guard let preview = chat.lastMessagePreview else { continue }
            guard preview.messageType.isEmpty || preview.messageType == "message" else { continue }
            guard let created = parseISO8601(preview.createdDateTime),
                  created >= todayStart, created < tomorrowStart else { continue }
            let lastRead = (chat.viewpoint?.lastMessageReadDateTime)
                .flatMap(parseISO8601) ?? .distantPast
            // Already-read chats only — pulling an unread one back to
            // unread is a no-op and just wastes a round-trip.
            guard lastRead >= created else { continue }
            ids.append(chat.id)
        }
        return ids
    }

    /// Mail.ReadWrite required. Idempotent.
    func flagEmail(id: String) async throws {
        try await core.patch("/me/messages/\(id)",
                        body: FlagBody(flag: FlagStatusBody(flagStatus: "flagged")))
    }

    /// Mail.ReadWrite required. Idempotent.
    func unflagEmail(id: String) async throws {
        try await core.patch("/me/messages/\(id)",
                        body: FlagBody(flag: FlagStatusBody(flagStatus: "notFlagged")))
    }

/// Microsoft Graph's per-batch ceiling for `/$batch` operations.
    /// Chunking at this size keeps us inside the limit and avoids the
    /// 429 Too Many Requests bursts we'd see firing concurrent PATCHes.
    private static let graphBatchSize = 20

    /// Bulk mark-read via `/$batch`. Chunks larger inputs into
    /// `graphBatchSize`-op batches. Returns the IDs that came back
    /// non-2xx so the caller can selectively revert.
    func batchMarkRead(ids: [String]) async throws -> Set<String> {
        try await batchSetReadState(ids: ids, isRead: true)
    }

    /// Bulk mark-unread via `/$batch`. Used by the undo path so a
    /// "Marked 20 read" action can be reversed in one round trip.
    func batchMarkUnread(ids: [String]) async throws -> Set<String> {
        try await batchSetReadState(ids: ids, isRead: false)
    }

    private func batchSetReadState(ids: [String], isRead: Bool) async throws -> Set<String> {
        try await batchPatch(ids: ids) { _ in MarkReadBody(isRead: isRead) }
    }

    /// Bulk flag/unflag via `/$batch`. Same chunking rationale as
    /// `batchMarkRead`.
    func batchSetFlagged(ids: [String], flagged: Bool) async throws -> Set<String> {
        let status = flagged ? "flagged" : "notFlagged"
        return try await batchPatch(ids: ids) { _ in
            FlagBody(flag: FlagStatusBody(flagStatus: status))
        }
    }

    /// Bulk PATCH `/me/messages/{id}` over `/$batch`, chunked to Graph's
    /// per-batch ceiling. Returns the ids whose sub-response wasn't 2xx.
    /// `makeBody` supplies each message's PATCH body, so mark-read and
    /// flag/unflag share one chunk-and-collect-failures loop.
    private func batchPatch<B: Encodable>(
        ids: [String],
        makeBody: (String) -> B
    ) async throws -> Set<String> {
        var failed: Set<String> = []
        for chunk in ids.batched(by: Self.graphBatchSize) {
            let requests = chunk.enumerated().map { (i, id) in
                BatchRequest(
                    id: "\(i)",
                    method: "PATCH",
                    url: "/me/messages/\(id)",
                    headers: ["Content-Type": "application/json"],
                    body: makeBody(id)
                )
            }
            let response: BatchResponse = try await core.postDecoded(
                "/$batch",
                body: BatchEnvelope(requests: requests)
            )
            failed.formUnion(failedIds(in: response, against: chunk))
        }
        return failed
    }

    private func failedIds(in response: BatchResponse, against ids: [String]) -> Set<String> {
        var failed: Set<String> = []
        for r in response.responses where !(200..<300).contains(r.status) {
            if let idx = Int(r.id), idx < ids.count {
                failed.insert(ids[idx])
            }
        }
        return failed
    }

    /// Fetch chats with unread activity. "Unread" here uses Graph's
    /// per-user `viewpoint.lastMessageReadDateTime`: a chat is unread
    /// when the last message's `createdDateTime` is newer than the
    /// user's last-read timestamp. This replaces the older heuristic of
    /// "the last message wasn't from me" (which was a workaround from
    /// when Graph didn't expose read state for chats).
    ///
    /// Additional filters:
    /// - Skip chats the user hid in Teams (`viewpoint.isHidden`).
    /// - Skip non-message events (joins, leaves, renames).
    ///
    /// There is no age cutoff: a genuinely unread chat surfaces however
    /// old its last message is, so nothing unread is silently dropped.
    ///
    /// We intentionally do NOT skip chats where the last message is
    /// from the signed-in user — Teams reliably advances
    /// `lastMessageReadDateTime` on send, so the viewpoint check
    /// already handles that case. Adding a `from.id == userID` skip
    /// here would fight against the "Mark today's chats unread" bulk
    /// action (which flips viewpoint back to unread; the explicit
    /// skip would re-hide those chats).
    func pendingChats() async throws -> [ChatMessage] {
        let data: GraphList<ChatResponse> = try await core.get("/me/chats", query: [
            "$select": "id,topic,webUrl,lastMessagePreview,viewpoint",
            "$expand": "lastMessagePreview,members",
            "$top": "50"
        ])

        var messages: [ChatMessage] = []

        for chat in data.value {
            guard let preview = chat.lastMessagePreview,
                  let sent = parseISO8601(preview.createdDateTime) else { continue }
            // `isUnreadChat` (CheckInGraph) is the single authority on what
            // counts as unread, shared with the widget/watch snapshot count.
            guard isUnreadChat(
                isHidden: chat.viewpoint?.isHidden,
                messageType: preview.messageType,
                hasSenderUser: preview.from?.user != nil,
                sent: sent,
                lastRead: chat.viewpoint?.lastMessageReadDateTime.flatMap(parseISO8601)
            ), let from = preview.from?.user else { continue }

            let others: [String] = (chat.members ?? []).compactMap { m in
                guard let uid = m.userId, let name = m.displayName, !name.isEmpty else { return nil }
                if uid == userID || uid == from.id { return nil }
                return name
            }

            messages.append(ChatMessage(
                chatId: chat.id,
                topic: chat.topic ?? "",
                from: from.displayName,
                preview: stripHTML(preview.body.content),
                sent: sent,
                otherParticipants: others,
                webUrl: chat.webUrl
            ))
        }

        return messages
    }
}

private extension Array {
    /// Split into contiguous sub-arrays of at most `size` elements.
    func batched(by size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
