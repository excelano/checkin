// GraphTypes.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Wire-format types for Microsoft Graph requests and responses. These
// are intentionally minimal — only the fields CheckIn reads or sends.
// `internal` access so GraphClient can reference them from a sibling
// file; nothing outside Services/ should need to.

import Foundation

struct UserResponse: Decodable {
    let id: String
    let mail: String?
    let userPrincipalName: String?
}

struct GraphList<T: Decodable>: Decodable {
    let value: [T]
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case value
        case count = "@odata.count"
    }
}

struct CalendarEventResponse: Decodable {
    let id: String
    let subject: String
    let organizer: OrganizerResponse
    let start: DateTimeResponse
    let end: DateTimeResponse
    let onlineMeeting: OnlineMeetingResponse?
    let responseStatus: EventResponseStatus?
    let isCancelled: Bool?
}

struct EventResponseStatus: Decodable {
    let response: String
}

struct OnlineMeetingResponse: Decodable {
    let joinUrl: String?
}

struct OrganizerResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

struct DateTimeResponse: Decodable {
    let dateTime: String
    let timeZone: String
}

struct EmailAddressResponse: Decodable {
    let name: String
    let address: String?
}

struct EmailResponse: Decodable {
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

struct InternetMessageHeader: Decodable {
    let name: String
    let value: String
}

struct FlagResponse: Decodable {
    let flagStatus: String?
}

struct EmailFromResponse: Decodable {
    let emailAddress: EmailAddressResponse
}

struct BodyContentResponse: Decodable {
    let contentType: String
    let content: String
}

struct ChatResponse: Decodable {
    let topic: String?
    let webUrl: String?
    let lastMessagePreview: ChatPreviewResponse?
    let members: [ChatMemberResponse]?
}

struct ChatMemberResponse: Decodable {
    let userId: String?
    let displayName: String?
}

struct ChatPreviewResponse: Decodable {
    let body: BodyContentResponse
    let from: ChatFromResponse?
    let createdDateTime: String
    let messageType: String
}

struct ChatFromResponse: Decodable {
    let user: ChatUserResponse?
}

struct ChatUserResponse: Decodable {
    let id: String
    let displayName: String
}

struct MarkReadBody: Encodable {
    let isRead: Bool
}

struct FlagBody: Encodable {
    let flag: FlagStatusBody
}

struct FlagStatusBody: Encodable {
    let flagStatus: String
}

struct RsvpBody: Encodable {
    let sendResponse: Bool
}

struct BatchRequest<B: Encodable>: Encodable {
    let id: String
    let method: String
    let url: String
    let headers: [String: String]
    let body: B
}

struct BatchEnvelope<B: Encodable>: Encodable {
    let requests: [BatchRequest<B>]
}

struct BatchResponse: Decodable {
    let responses: [BatchResponseItem]
}

struct BatchResponseItem: Decodable {
    let id: String
    let status: Int
}

struct PresenceResponse: Decodable {
    let availability: String
    let activity: String
}

struct SetPresenceBody: Encodable {
    let availability: String
    let activity: String
    let expirationDuration: String  // ISO 8601 duration, e.g., "PT4H"
}
