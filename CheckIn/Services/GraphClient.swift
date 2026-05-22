// GraphClient.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

final class GraphClient {
    private let authService: AuthService
    private let session = URLSession.shared
    private let enableTeams: Bool
    private var userID = ""

    init(authService: AuthService, enableTeams: Bool) {
        self.authService = authService
        self.enableTeams = enableTeams
    }

    /// Fetch the signed-in user's ID (needed for the Teams pending-chat heuristic)
    func fetchUserID() async throws {
        let data: UserResponse = try await get("/me", query: ["$select": "id"])
        userID = data.id
    }

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
            "$select": "id,subject,organizer,start,end,onlineMeeting,responseStatus,isCancelled"
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
                hasConflict: hasConflict
            )
        }

        return (meetings.first, Array(meetings.dropFirst()))
    }

    /// DELETE an event. For invitation/personal events this removes it
    /// from the user's calendar. For events the user organizes Graph
    /// also sends cancellations to attendees — the caller is expected to
    /// gate that case.
    func deleteEvent(id: String) async throws {
        try await delete("/me/events/\(id)")
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

    /// Returns the newest unread emails (up to `top`, default 20) along
    /// with the total unread count. `$count=true` requires the
    /// `ConsistencyLevel: eventual` header. The
    /// `microsoft.graph.eventMessage/meetingMessageType` cast fetches the
    /// meeting-subtype field for invite/response messages without changing
    /// the base collection type.
    func unreadEmails(top: Int = 20) async throws -> (emails: [Email], totalCount: Int) {
        let data: GraphList<EmailResponse> = try await get(
            "/me/messages",
            query: [
                "$filter": "isRead eq false",
                "$orderby": "receivedDateTime desc",
                "$top": "\(top)",
                "$count": "true",
                "$select": "id,subject,from,bodyPreview,receivedDateTime,flag,inferenceClassification,internetMessageHeaders,microsoft.graph.eventMessage/meetingMessageType"
            ],
            headers: ["ConsistencyLevel": "eventual"]
        )

        let emails = data.value.map { e in
            let isMailingList = (e.internetMessageHeaders ?? []).contains { h in
                h.name.caseInsensitiveCompare("List-Unsubscribe") == .orderedSame
            }
            return Email(
                id: e.id,
                subject: e.subject,
                from: e.from.emailAddress.name,
                fromAddress: e.from.emailAddress.address ?? "",
                preview: e.bodyPreview,
                received: parseISO8601(e.receivedDateTime) ?? Date(),
                isFlagged: e.flag?.flagStatus == "flagged",
                inferenceClassification: e.inferenceClassification,
                meetingMessageType: e.meetingMessageType,
                isMailingList: isMailingList
            )
        }
        return (emails, data.count ?? emails.count)
    }

    /// Mail.ReadWrite required. Idempotent.
    func markEmailRead(id: String) async throws {
        try await patch("/me/messages/\(id)", body: MarkReadBody(isRead: true))
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

    /// Mail.ReadWrite required. Graph moves the message to the user's
    /// Deleted Items folder; this is the same behavior as Outlook's trash
    /// button. Tenant retention policy controls how long it stays
    /// recoverable.
    func deleteEmail(id: String) async throws {
        try await delete("/me/messages/\(id)")
    }

    /// Bulk mark-read via `/$batch`. Chunks larger inputs into 20-op
    /// batches (Graph's per-batch ceiling). Avoids the 429 Too Many
    /// Requests bursts we'd see firing concurrent PATCHes directly.
    /// Returns the IDs that came back non-2xx so the caller can
    /// selectively revert.
    func batchMarkRead(ids: [String]) async throws -> Set<String> {
        var failed: Set<String> = []
        for chunk in ids.batched(by: 20) {
            let requests = chunk.enumerated().map { (i, id) in
                BatchRequest(
                    id: "\(i)",
                    method: "PATCH",
                    url: "/me/messages/\(id)",
                    headers: ["Content-Type": "application/json"],
                    body: MarkReadBody(isRead: true)
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

    /// Fetch pending chats: chats where someone else sent the last message within 24 hours.
    func pendingChats() async throws -> [ChatMessage] {
        let data: GraphList<ChatResponse> = try await get("/me/chats", query: [
            "$select": "topic,webUrl,lastMessagePreview",
            "$expand": "lastMessagePreview,members",
            "$top": "50"
        ])

        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var messages: [ChatMessage] = []

        for chat in data.value {
            guard let preview = chat.lastMessagePreview else { continue }
            if !preview.messageType.isEmpty && preview.messageType != "message" {
                continue
            }
            guard let from = preview.from?.user else { continue }
            if from.id == userID { continue }
            guard let sent = parseISO8601(preview.createdDateTime),
                  sent > cutoff else { continue }

            let others: [String] = (chat.members ?? []).compactMap { m in
                guard let uid = m.userId, let name = m.displayName, !name.isEmpty else { return nil }
                if uid == userID || uid == from.id { return nil }
                return name
            }

            messages.append(ChatMessage(
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

        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data, method: "GET", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data, method: "PATCH", path: path)
    }

    private func post(_ path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data, method: "POST", path: path)
    }

    private func postDecoded<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data, method: "POST", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "DELETE"
        request = try await authorize(request)

        let (data, response) = try await session.data(for: request)
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
    return formatter.date(from: dateString) ?? Date()
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

private struct UserResponse: Decodable {
    let id: String
}

private struct GraphList<T: Decodable>: Decodable {
    let value: [T]
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case count = "@odata.count"
    }
}

private struct CalendarEventResponse: Decodable {
    let id: String
    let subject: String
    let organizer: OrganizerResponse
    let start: DateTimeResponse
    let end: DateTimeResponse
    let onlineMeeting: OnlineMeetingResponse?
    let responseStatus: EventResponseStatus?
    let isCancelled: Bool?
}

private struct EventResponseStatus: Decodable {
    let response: String
}

private struct OnlineMeetingResponse: Decodable {
    let joinUrl: String?
}

private struct OrganizerResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

private struct DateTimeResponse: Decodable {
    let dateTime: String
    let timeZone: String
}

private struct EmailAddressResponse: Decodable {
    let name: String
    let address: String?
}

private struct EmailResponse: Decodable {
    let id: String
    let subject: String
    let from: EmailFromResponse
    let bodyPreview: String
    let receivedDateTime: String
    let flag: FlagResponse?
    let inferenceClassification: String?
    let meetingMessageType: String?
    let internetMessageHeaders: [InternetMessageHeader]?
}

private struct InternetMessageHeader: Decodable {
    let name: String
    let value: String
}

private struct FlagResponse: Decodable {
    let flagStatus: String?
}

private struct EmailFromResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

private struct BodyContentResponse: Decodable {
    let contentType: String
    let content: String
}

private struct ChatResponse: Decodable {
    let topic: String?
    let webUrl: String?
    let lastMessagePreview: ChatPreviewResponse?
    let members: [ChatMemberResponse]?
}

private struct ChatMemberResponse: Decodable {
    let userId: String?
    let displayName: String?
}

private struct ChatPreviewResponse: Decodable {
    let body: BodyContentResponse
    let from: ChatFromResponse?
    let createdDateTime: String
    let messageType: String
}

private struct ChatFromResponse: Decodable {
    let user: ChatUserResponse?
}

private struct ChatUserResponse: Decodable {
    let id: String
    let displayName: String
}

private struct MarkReadBody: Encodable {
    let isRead: Bool
}

private struct FlagBody: Encodable {
    let flag: FlagStatusBody
}

private struct FlagStatusBody: Encodable {
    let flagStatus: String
}

private struct RsvpBody: Encodable {
    let sendResponse: Bool
}

private struct BatchRequest<B: Encodable>: Encodable {
    let id: String
    let method: String
    let url: String
    let headers: [String: String]
    let body: B
}

private struct BatchEnvelope<B: Encodable>: Encodable {
    let requests: [BatchRequest<B>]
}

private struct BatchResponse: Decodable {
    let responses: [BatchResponseItem]
}

private struct BatchResponseItem: Decodable {
    let id: String
    let status: Int
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
