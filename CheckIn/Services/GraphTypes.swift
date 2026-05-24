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

/// Minimal shape for `fetchInviteEventId` — only the underlying event's
/// id matters; subject/start/end already came from the eventMessage
/// fields in the list query. Both layers are optional because Graph
/// returns empty stubs for invitations that haven't been tentatively
/// accepted yet.
struct MessageEventIdResponse: Decodable {
    let event: EventIdResponse?
}

struct EventIdResponse: Decodable {
    let id: String?
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
    /// Meeting times pulled via `microsoft.graph.eventMessage/startDateTime`
    /// (and `endDateTime`) in the list query's `$select`. Present only on
    /// invitation/cancellation/response messages; nil otherwise.
    let startDateTime: DateTimeResponse?
    let endDateTime: DateTimeResponse?
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

/// Used when we only need the message id from a list query (e.g.,
/// fetching today's read messages so we can flip them back to unread).
struct EmailIdResponse: Decodable {
    let id: String
}

/// Used by `fetchEmailBody` to pull just the body text. Combined with
/// the `Prefer: outlook.body-content-type="text"` request header so
/// Graph returns plain text instead of HTML.
struct EmailBodyResponse: Decodable {
    let body: BodyContentResponse
}

/// POST body for `/me/messages/{id}/replyAll` — Graph wraps the user's
/// short message in `comment` and stitches it onto the original
/// conversation with proper `In-Reply-To` / `References` threading.
struct ReplyCommentBody: Encodable {
    let comment: String
}

/// POST body for `/me/chats/{chatId}/messages`. Graph expects `body`
/// as a content envelope identical in shape to the lastMessagePreview
/// body we read elsewhere.
struct ChatMessageSendBody: Encodable {
    let body: ChatMessageSendContent
}

struct ChatMessageSendContent: Encodable {
    let contentType: String
    let content: String
}

/// POST body for `/chats/{id}/markChatReadForUser`. The user identity
/// requires both id and tenantId — tenantId comes from MSAL's
/// homeAccountId, id from /me.
struct MarkChatReadBody: Encodable {
    let user: TeamworkUserIdentityBody
}

/// POST body for `/chats/{id}/markChatUnreadForUser`. Per Graph docs,
/// when `lastMessageReadDateTime` is omitted the API defaults to
/// "mark the last message unread" — which is exactly what we want
/// here, so we just don't send the field. Avoids the trap of Graph
/// rejecting out-of-range timestamps (1970 etc.) for that parameter.
struct MarkChatUnreadBody: Encodable {
    let user: TeamworkUserIdentityBody
}

struct TeamworkUserIdentityBody: Encodable {
    let id: String
    let tenantId: String
}

struct ChatResponse: Decodable {
    let id: String
    let topic: String?
    let webUrl: String?
    let lastMessagePreview: ChatPreviewResponse?
    let members: [ChatMemberResponse]?
    /// Per-user state for this chat. `lastMessageReadDateTime` is the
    /// signal we use to decide whether a chat has unread activity:
    /// unread iff `lastMessagePreview.createdDateTime` is newer.
    /// `isHidden` reflects the user hiding the chat in Teams; we honor
    /// that and skip hidden chats entirely.
    let viewpoint: ChatViewpointResponse?
}

struct ChatViewpointResponse: Decodable {
    let isHidden: Bool?
    /// ISO8601. `"0001-01-01T00:00:00Z"` for chats the user has never
    /// opened — the comparison still works because that date is older
    /// than any real `createdDateTime`.
    let lastMessageReadDateTime: String?
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
    let statusMessage: StatusMessageEnvelope?
}

struct StatusMessageEnvelope: Decodable {
    let message: StatusMessageContent?
}

struct StatusMessageContent: Decodable {
    let content: String?
    let contentType: String?
}

struct SetStatusMessageBody: Encodable {
    let statusMessage: StatusMessagePayload

    init(content: String) {
        statusMessage = StatusMessagePayload(
            message: StatusMessagePayloadContent(content: content, contentType: "text")
        )
    }
}

struct StatusMessagePayload: Encodable {
    let message: StatusMessagePayloadContent
}

struct StatusMessagePayloadContent: Encodable {
    let content: String
    let contentType: String
}

struct SetPresenceBody: Encodable {
    let availability: String
    let activity: String
    let expirationDuration: String  // ISO 8601 duration, e.g., "PT4H"
}

/// Body for `/me/presence/setPresence` — the app-session endpoint that
/// registers CheckIn as an active presence source. Distinct from the
/// user-preferred body above: this one requires a `sessionId` and keeps
/// Graph from treating the user as having "no session" (which would
/// otherwise stop the preferred from being honored).
struct SetSessionPresenceBody: Encodable {
    let sessionId: String
    let availability: String
    let activity: String
    let expirationDuration: String  // ISO 8601, max "PT1H"
}

struct ClearSessionPresenceBody: Encodable {
    let sessionId: String
}

/// Subset of `/me/mailboxSettings/automaticRepliesSetting` we care about
/// for the OOO toggle. `status` drives the indicator and the toggle;
/// the messages are kept so we can preserve a user's existing
/// auto-reply text when toggling, rather than overwriting it with our
/// canned default every time.
struct AutomaticRepliesResponse: Decodable {
    let status: String  // disabled | alwaysEnabled | scheduled
    let externalAudience: String?
    let internalReplyMessage: String?
    let externalReplyMessage: String?
}

struct MailboxSettingsStatusOnly: Encodable {
    let automaticRepliesSetting: AutomaticRepliesStatusOnly
}

struct AutomaticRepliesStatusOnly: Encodable {
    let status: String
}

struct MailboxSettingsFull: Encodable {
    let automaticRepliesSetting: AutomaticRepliesFull
}

struct AutomaticRepliesFull: Encodable {
    let status: String
    let externalAudience: String
    let internalReplyMessage: String
    let externalReplyMessage: String
}
