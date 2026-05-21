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

    // MARK: - Setup

    /// Fetch the signed-in user's ID (needed for the Teams pending-chat heuristic)
    func fetchUserID() async throws {
        let data: UserResponse = try await get("/me", query: ["$select": "id"])
        userID = data.id
    }

    // MARK: - Calendar

    /// Fetch the next meeting in the next 24 hours using calendarView
    /// (not /events, so recurring meetings are properly expanded)
    func nextMeeting() async throws -> Meeting? {
        let now = Date()
        let end = now.addingTimeInterval(24 * 3600)
        let formatter = ISO8601DateFormatter()

        let data: GraphList<CalendarEventResponse> = try await get("/me/calendarView", query: [
            "startDateTime": formatter.string(from: now),
            "endDateTime": formatter.string(from: end),
            "$top": "1",
            "$orderby": "start/dateTime",
            "$select": "subject,organizer,location,start,end,isOnlineMeeting,onlineMeeting,attendees"
        ])

        guard let event = data.value.first else { return nil }

        let start = parseGraphDate(event.start.dateTime, timeZone: event.start.timeZone)
        let meetingEnd = parseGraphDate(event.end.dateTime, timeZone: event.end.timeZone)

        let organizerName = event.organizer.emailAddress.name
        let attendees = event.attendees
            .filter { $0.type == "required" }
            .map { $0.emailAddress.name }
            .filter { !$0.isEmpty && $0 != organizerName }

        return Meeting(
            subject: event.subject,
            organizer: organizerName,
            location: event.location.displayName,
            start: start,
            end: meetingEnd,
            isOnline: event.isOnlineMeeting,
            attendees: attendees,
            joinUrl: event.onlineMeeting?.joinUrl
        )
    }

    // MARK: - Email

    func unreadEmails() async throws -> [Email] {
        let data: GraphList<EmailResponse> = try await get("/me/messages", query: [
            "$filter": "isRead eq false",
            "$orderby": "receivedDateTime desc",
            "$top": "10",
            "$select": "id,subject,from,bodyPreview,receivedDateTime"
        ])

        return data.value.map { e in
            let received = parseISO8601(e.receivedDateTime) ?? Date()
            return Email(
                id: e.id,
                subject: e.subject,
                from: e.from.emailAddress.name,
                fromAddress: e.from.emailAddress.address ?? "",
                preview: e.bodyPreview,
                received: received
            )
        }
    }

    // MARK: - Email mutations

    /// Mark a single message read. Mail.ReadWrite scope required.
    /// Idempotent — re-marking an already-read message is a no-op on
    /// Graph's side. Caller must confirm with the user before calling.
    func markEmailRead(id: String) async throws {
        try await patch("/me/messages/\(id)", body: MarkReadBody(isRead: true))
    }

    /// Add a follow-up flag to a single message. Mail.ReadWrite scope
    /// required. Already-flagged messages can be re-flagged without
    /// changing state. Caller must confirm with the user before calling.
    func flagEmail(id: String) async throws {
        try await patch("/me/messages/\(id)",
                        body: FlagBody(flag: FlagStatusBody(flagStatus: "flagged")))
    }

    /// Move a single message to Deleted Items. Mail.ReadWrite scope
    /// required. The `deleteditems` destination is one of Graph's
    /// well-known folder identifiers; recoverable from the user's
    /// Outlook Deleted Items folder until they empty it. Caller must
    /// confirm with the user before calling.
    func softDeleteEmail(id: String) async throws {
        _ = try await post("/me/messages/\(id)/move",
                           body: MoveBody(destinationId: "deleteditems"))
    }

    // MARK: - Teams

    /// Fetch pending chats: chats where someone else sent the last message within 24 hours.
    func pendingChats() async throws -> [ChatMessage] {
        let data: GraphList<ChatResponse> = try await get("/me/chats", query: [
            "$select": "id,topic,chatType,webUrl,lastMessagePreview",
            "$expand": "lastMessagePreview",
            "$top": "50"
        ])

        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var messages: [ChatMessage] = []

        for chat in data.value {
            guard let preview = chat.lastMessagePreview else { continue }

            // Skip system messages (meeting recordings, etc.)
            if !preview.messageType.isEmpty && preview.messageType != "message" {
                continue
            }

            // Skip if sender is unknown
            guard let from = preview.from?.user else { continue }

            // Skip if you sent the last message (not pending)
            if from.id == userID { continue }

            // Parse sent time, skip if older than 24 hours
            guard let sent = parseISO8601(preview.createdDateTime),
                  sent > cutoff else { continue }

            // Determine topic
            var topic = chat.topic ?? ""
            if topic.isEmpty { topic = from.displayName }
            if topic.isEmpty { topic = "Chat" }

            messages.append(ChatMessage(
                chatID: chat.id,
                topic: topic,
                from: from.displayName,
                preview: stripHTML(preview.body.content),
                sent: sent,
                webUrl: chat.webUrl
            ))
        }

        return messages
    }

    // MARK: - HTTP Layer

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

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
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

    @discardableResult
    private func post(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request = try await authorize(request)

        let (data, response) = try await session.data(for: request)
        try checkResponse(response, data: data, method: "POST", path: path)
        return data
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

// MARK: - ISO8601 Date Parsing

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

// MARK: - Graph Date Parsing

/// Graph API returns datetimes as a naive string plus a separate timezone string.
private func parseGraphDate(_ dateString: String, timeZone: String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
    formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
    return formatter.date(from: dateString) ?? Date()
}

// MARK: - Errors

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

// MARK: - API Response Types (private Codable structs)

private struct UserResponse: Decodable {
    let id: String
}

private struct GraphList<T: Decodable>: Decodable {
    let value: [T]
}

private struct CalendarEventResponse: Decodable {
    let subject: String
    let organizer: OrganizerResponse
    let location: LocationResponse
    let start: DateTimeResponse
    let end: DateTimeResponse
    let isOnlineMeeting: Bool
    let onlineMeeting: OnlineMeetingResponse?
    let attendees: [AttendeeResponse]
}

private struct OnlineMeetingResponse: Decodable {
    let joinUrl: String?
}

private struct OrganizerResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

private struct AttendeeResponse: Decodable {
    let type: String
    let emailAddress: EmailAddressResponse
}

private struct LocationResponse: Decodable {
    let displayName: String
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
}

private struct EmailFromResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

private struct BodyContentResponse: Decodable {
    let contentType: String
    let content: String
}

private struct ChatResponse: Decodable {
    let id: String
    let topic: String?
    let chatType: String
    let webUrl: String?
    let lastMessagePreview: ChatPreviewResponse?
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

// MARK: - Mutation Request Bodies

private struct MarkReadBody: Encodable {
    let isRead: Bool
}

private struct FlagBody: Encodable {
    let flag: FlagStatusBody
}

private struct FlagStatusBody: Encodable {
    let flagStatus: String
}

private struct MoveBody: Encodable {
    let destinationId: String
}
