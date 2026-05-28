// GraphClient.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

final class GraphClient {
    private let authService: AuthService
    private let session = URLSession.shared
    private let enableTeams: Bool
    private var userID = ""
    private var userMail = ""

    init(authService: AuthService, enableTeams: Bool) {
        self.authService = authService
        self.enableTeams = enableTeams
    }

    /// Fetch the signed-in user's ID and mail address. ID powers the Teams
    /// pending-chat self-filter; mail powers external-sender detection.
    /// Some accounts (personal/MSA, occasionally) don't populate `mail`,
    /// so we fall back to `userPrincipalName`.
    func fetchUserID() async throws {
        let data: UserResponse = try await get("/me", query: ["$select": "id,mail,userPrincipalName"])
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
        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let formatter = ISO8601DateFormatter()

        let data: GraphList<CalendarEventResponse> = try await get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: now),
            "endDateTime": formatter.string(from: endOfDay),
            "$top": "10",
            "$orderby": "start/dateTime",
            "$select": "id,subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled,iCalUId"
        ])

        // Skip cancelled events (they stay in calendarView until removed)
        // and declined events (some tenants/users keep declined invites on
        // the calendar rather than auto-removing them). Done client-side
        // because calendarView's `$filter` support is narrow and undocumented
        // for these fields.
        let isAttendable: (CalendarEventResponse) -> Bool = { e in
            !(e.isCancelled ?? false) && e.responseStatus?.response != "declined"
        }
        let attendable = data.value
            .filter(isAttendable)
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
    /// conflict detection on Phase 2 invite-email RSVP — so a plain
    /// calendar event that overlaps an invite can flag the invite as
    /// conflicting. Not displayed anywhere in the UI. Caps at 100
    /// events as a guard against multi-week ranges with very dense
    /// calendars.
    func eventsInRange(start: Date, end: Date) async throws -> [Meeting] {
        let formatter = ISO8601DateFormatter()
        let data: GraphList<CalendarEventResponse> = try await get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: start),
            "endDateTime": formatter.string(from: end),
            "$top": "100",
            "$orderby": "start/dateTime",
            "$select": "id,subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled,iCalUId"
        ])

        return data.value
            .filter { !($0.isCancelled ?? false) && $0.responseStatus?.response != "declined" }
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
        try await delete("/me/events/\(id)")
    }

    /// Current Microsoft 365 presence (collapsed to our smaller enum) plus the
    /// short custom status message that shows under the user's name in
    /// Teams. Empty string when no message is set. Presence.ReadWrite
    /// required for both.
    func fetchPresence() async throws -> (presence: Presence, statusMessage: String) {
        let data: PresenceResponse = try await get("/me/presence", query: [:])
        let message = data.statusMessage?.message?.content ?? ""
        return (Presence(graphAvailability: data.availability), message)
    }

    /// Pin the user's preferred presence — overrides Teams' own
    /// auto-detection (which would otherwise flip the user to "In a
    /// meeting" or "Available" based on the calendar). Stays for
    /// `expirationDuration` (4 hours here, matching Graph's default)
    /// or until cleared by `clearUserPreferredPresence`.
    func setUserPreferredPresence(_ presence: Presence) async throws {
        guard let availability = presence.graphAvailability,
              let activity = presence.graphActivity else { return }
        try await post(
            "/me/presence/setUserPreferredPresence",
            body: SetPresenceBody(
                availability: availability,
                activity: activity,
                expirationDuration: "P1D"
            )
        )
    }

    /// Drop the user-preferred presence so Teams resumes auto-detection.
    /// POSTs an empty body.
    func clearUserPreferredPresence() async throws {
        try await emptyPost("/me/presence/clearUserPreferredPresence")
    }

    /// Set (or clear) the user's Teams status message — the short text
    /// shown under the user's name in Teams, independent of presence.
    /// Passing an empty string clears it.
    func setStatusMessage(_ content: String) async throws {
        try await post(
            "/me/presence/setStatusMessage",
            body: SetStatusMessageBody(content: content)
        )
    }

    /// Register CheckIn as an active presence-session source so the
    /// user's preferred presence keeps applying even when no other
    /// Microsoft client (Teams) holds a session. Max expiration is
    /// `PT1H`; callers re-up on every refresh.
    /// `.offline` is not a valid combination for this endpoint —
    /// the caller must route .offline / .unknown through
    /// `clearSessionPresence` instead.
    func setSessionPresence(sessionId: String, presence: Presence) async throws {
        guard let availability = presence.graphAvailability,
              let activity = presence.graphActivity,
              availability != "Offline" else { return }
        try await post(
            "/me/presence/setPresence",
            body: SetSessionPresenceBody(
                sessionId: sessionId,
                availability: availability,
                activity: activity,
                expirationDuration: "PT1H"
            )
        )
    }

    /// Drop CheckIn's presence session. Used when the user resets to
    /// auto or chooses Offline (which we want to express via the
    /// preferred-presence override, not a session).
    func clearSessionPresence(sessionId: String) async throws {
        try await post(
            "/me/presence/clearPresence",
            body: ClearSessionPresenceBody(sessionId: sessionId)
        )
    }

    /// Read the user's auto-reply settings. Used to drive the OOO indicator
    /// and to preserve any existing auto-reply text when toggling.
    func fetchAutomaticReplies() async throws -> AutomaticRepliesResponse {
        try await get("/me/mailboxSettings/automaticRepliesSetting", query: [:])
    }

    /// Turn the user's auto-reply on. If their existing internal/external
    /// message is empty, fills in a generic default so people don't get
    /// blank auto-replies. Otherwise preserves whatever they already had
    /// (likely set via Outlook web).
    func enableAutomaticReplies(defaultMessage: String) async throws {
        let current = try await fetchAutomaticReplies()
        let internalMsg = current.internalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultMessage
        let externalMsg = current.externalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultMessage
        let body = MailboxSettingsFull(
            automaticRepliesSetting: AutomaticRepliesFull(
                status: "alwaysEnabled",
                externalAudience: current.externalAudience ?? "all",
                internalReplyMessage: internalMsg,
                externalReplyMessage: externalMsg
            )
        )
        try await patch("/me/mailboxSettings", body: body)
    }

    /// Turn the user's auto-reply off. PATCHes status only so existing
    /// messages are preserved for next time.
    func disableAutomaticReplies() async throws {
        let body = MailboxSettingsStatusOnly(
            automaticRepliesSetting: AutomaticRepliesStatusOnly(status: "disabled")
        )
        try await patch("/me/mailboxSettings", body: body)
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
        try await post("/me/events/\(id)/\(action)", body: RsvpBody(sendResponse: true))
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
            let response: MessageSingleValueExtPropResponse = try await get(
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
        let data: GraphList<EmailResponse> = try await get(
            "/me/mailFolders/inbox/messages",
            query: [
                "$filter": "isRead eq false",
                "$orderby": "receivedDateTime desc",
                "$top": "\(top)",
                "$count": "true",
                "$select": "id,subject,from,toRecipients,ccRecipients,bodyPreview,receivedDateTime,flag,inferenceClassification,internetMessageHeaders,microsoft.graph.eventMessage/meetingMessageType,microsoft.graph.eventMessage/startDateTime,microsoft.graph.eventMessage/endDateTime"
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
                ccRecipients: ccRecipients
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
        try await patch("/me/messages/\(id)", body: MarkReadBody(isRead: true))
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

        let data: GraphList<EmailIdResponse> = try await get(
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
        let data: GraphList<EmailIdResponse> = try await get(
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
        try await patch("/me/messages/\(id)", body: MarkReadBody(isRead: false))
    }

    /// Fetch the full plain-text body of a message for the preview sheet.
    /// `Prefer: outlook.body-content-type="text"` tells Graph to return
    /// text in `body.content` rather than HTML, which avoids us having
    /// to render HTML for the preview. Mail.Read or Mail.ReadWrite
    /// covers this.
    func fetchEmailBody(id: String) async throws -> String {
        let data: EmailBodyResponse = try await get(
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
        try await post("/me/messages/\(id)/replyAll", body: ReplyCommentBody(comment: comment))
    }

    /// Post a new message into an existing chat thread. Chat.ReadWrite
    /// covers this — `ChatMessage.Send` is a more granular scope but
    /// the broader one we already request is a superset.
    func sendChatMessage(chatId: String, content: String) async throws {
        try await post(
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
        try await post(
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
        try await post(
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

        let data: GraphList<ChatResponse> = try await get("/me/chats", query: [
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
        try await patch("/me/messages/\(id)",
                        body: FlagBody(flag: FlagStatusBody(flagStatus: "flagged")))
    }

    /// Mail.ReadWrite required. Idempotent.
    func unflagEmail(id: String) async throws {
        try await patch("/me/messages/\(id)",
                        body: FlagBody(flag: FlagStatusBody(flagStatus: "notFlagged")))
    }

/// Bulk mark-read via `/$batch`. Chunks larger inputs into 20-op
    /// batches (Graph's per-batch ceiling). Avoids the 429 Too Many
    /// Requests bursts we'd see firing concurrent PATCHes directly.
    /// Returns the IDs that came back non-2xx so the caller can
    /// selectively revert.
    func batchMarkRead(ids: [String]) async throws -> Set<String> {
        try await batchSetReadState(ids: ids, isRead: true)
    }

    /// Bulk mark-unread via `/$batch`. Used by the undo path so a
    /// "Marked 20 read" action can be reversed in one round trip.
    func batchMarkUnread(ids: [String]) async throws -> Set<String> {
        try await batchSetReadState(ids: ids, isRead: false)
    }

    private func batchSetReadState(ids: [String], isRead: Bool) async throws -> Set<String> {
        var failed: Set<String> = []
        for chunk in ids.batched(by: 20) {
            let requests = chunk.enumerated().map { (i, id) in
                BatchRequest(
                    id: "\(i)",
                    method: "PATCH",
                    url: "/me/messages/\(id)",
                    headers: ["Content-Type": "application/json"],
                    body: MarkReadBody(isRead: isRead)
                )
            }
            let response: BatchResponse = try await postDecoded(
                "/$batch",
                body: BatchEnvelope(requests: requests)
            )
            failed.formUnion(failedIds(in: response, against: chunk))
        }
        return failed
    }

    /// Bulk flag/unflag via `/$batch`. Same chunking rationale as
    /// `batchMarkRead`.
    func batchSetFlagged(ids: [String], flagged: Bool) async throws -> Set<String> {
        let status = flagged ? "flagged" : "notFlagged"
        var failed: Set<String> = []
        for chunk in ids.batched(by: 20) {
            let requests = chunk.enumerated().map { (i, id) in
                BatchRequest(
                    id: "\(i)",
                    method: "PATCH",
                    url: "/me/messages/\(id)",
                    headers: ["Content-Type": "application/json"],
                    body: FlagBody(flag: FlagStatusBody(flagStatus: status))
                )
            }
            let response: BatchResponse = try await postDecoded(
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
    /// - Skip messages older than 24h so the list stays focused on
    ///   recent activity (an unread message from last week shouldn't
    ///   linger forever in the panel).
    /// - Skip non-message events (joins, leaves, renames).
    ///
    /// We intentionally do NOT skip chats where the last message is
    /// from the signed-in user — Teams reliably advances
    /// `lastMessageReadDateTime` on send, so the viewpoint check
    /// already handles that case. Adding a `from.id == userID` skip
    /// here would fight against the "Mark today's chats unread" bulk
    /// action (which flips viewpoint back to unread; the explicit
    /// skip would re-hide those chats).
    func pendingChats() async throws -> [ChatMessage] {
        let data: GraphList<ChatResponse> = try await get("/me/chats", query: [
            "$select": "id,topic,webUrl,lastMessagePreview,viewpoint",
            "$expand": "lastMessagePreview,members",
            "$top": "50"
        ])

        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var messages: [ChatMessage] = []

        for chat in data.value {
            if chat.viewpoint?.isHidden == true { continue }
            guard let preview = chat.lastMessagePreview else { continue }
            // Keep regular messages (and the rare empty-string `messageType`)
            // and drop everything else — joins, leaves, renames, etc.
            guard preview.messageType.isEmpty || preview.messageType == "message" else { continue }
            guard let from = preview.from?.user else { continue }
            guard let sent = parseISO8601(preview.createdDateTime),
                  sent > cutoff else { continue }

            // The real read-state check. `lastMessageReadDateTime` may be
            // `"0001-01-01T00:00:00Z"` (never read) — parseISO8601 returns
            // nil for that in some configurations, so fall back to
            // `.distantPast`, which is unread vs. any real `sent` date.
            let lastRead = (chat.viewpoint?.lastMessageReadDateTime)
                .flatMap(parseISO8601) ?? .distantPast
            guard sent > lastRead else { continue }

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

    private func makeURL(path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(string: Constants.graphBaseURL + path) else {
            throw GraphError.invalidURL(path: path)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw GraphError.invalidURL(path: path)
        }
        return url
    }

    private func get<T: Decodable>(_ path: String,
                                   query: [String: String],
                                   headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: true)
        try checkResponse(response, data: data, method: "GET", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: true)
        try checkResponse(response, data: data, method: "PATCH", path: path)
    }

    /// Used for both idempotent operations (presence sets, mark-read) and
    /// non-idempotent sends (replyAll). Retry is OFF here — see the
    /// `performRequest` doc comment for why doubling a sent message is a
    /// worse default than asking the user to retry manually.
    private func post(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: false)
        try checkResponse(response, data: data, method: "POST", path: path)
    }

    private func emptyPost(_ path: String) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: true)
        try checkResponse(response, data: data, method: "POST", path: path)
    }

    /// Used for `sendChatMessage` — non-idempotent. Retry OFF.
    private func postDecoded<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: false)
        try checkResponse(response, data: data, method: "POST", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "DELETE"
        request = try await authorize(request)

        let (data, response) = try await performRequest(request, retryOnTransient: true)
        try checkResponse(response, data: data, method: "DELETE", path: path)
    }

    private func authorize(_ request: URLRequest) async throws -> URLRequest {
        let token = try await authService.acquireTokenSilently(enableTeams: enableTeams)
        var req = request
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func checkResponse(_ response: URLResponse, data: Data, method: String, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GraphError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GraphError.httpError(method: method, path: path, status: http.statusCode, body: body)
        }
    }

    /// Send a request through URLSession, optionally retrying once on
    /// transient connection failures. The common case `retryOnTransient`
    /// solves is the iOS quirk where URLSession's connection pool holds
    /// dead sockets across an app suspend — the first call after resume
    /// fails with `.networkConnectionLost` even though the network is
    /// fine, and a single retry succeeds against a fresh connection.
    ///
    /// Idempotent methods (GET, PATCH, DELETE, mark-read POSTs)
    /// opt in. Non-idempotent sends (replyAll, sendChatMessage) opt
    /// out — `.networkConnectionLost` doesn't disambiguate "request
    /// never arrived" from "response was lost," and double-sending a
    /// message is worse than asking the user to tap Send again.
    private func performRequest(_ request: URLRequest,
                                retryOnTransient: Bool) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where retryOnTransient && Self.isTransient(error.code) {
            try await Task.sleep(for: .milliseconds(250))
            return try await session.data(for: request)
        }
    }

    /// URLError codes that indicate a dropped or stale connection where
    /// a single retry is the standard remedy. `.notConnectedToInternet`
    /// is intentionally omitted — that's a real user-offline state and
    /// hiding it would just delay the same error.
    private static func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

/// Parse ISO8601 dates from Graph API, handling fractional seconds.
/// Graph returns varying formats like "2026-04-08T18:55:28.844Z" or "2026-04-08T16:54:51.17Z".
/// The default ISO8601DateFormatter doesn't handle fractional seconds.
private func parseISO8601(_ dateString: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) { return date }
    // Fallback without fractional seconds
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: dateString)
}

/// Graph API returns datetimes as a naive string plus a separate timezone string.
private func parseGraphDate(_ dateString: String, timeZone: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
    formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
    if let date = formatter.date(from: dateString) { return date }
    // Falling back to `Date()` here used to be silent; logging so a
    // bad date string is debuggable when a meeting renders at the
    // wrong time.
    Logger(subsystem: "com.excelano.checkin", category: "graph")
        .error("parseGraphDate failed: '\(dateString, privacy: .public)' tz='\(timeZone, privacy: .public)'")
    return Date()
}

enum GraphError: LocalizedError {
    case invalidURL(path: String)
    case invalidResponse
    case httpError(method: String, path: String, status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Could not construct Graph URL for path \(path)."
        case .invalidResponse:
            return "Invalid response from Microsoft Graph."
        case .httpError(let method, let path, let status, let body):
            return "Graph API \(method) \(path) returned \(status): \(body)"
        }
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
