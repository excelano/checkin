// Meeting.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Meeting: Identifiable {
    /// Graph event ID. Needed for the RSVP endpoints (`/me/events/{id}/accept`
    /// etc.) — synthetic UUIDs won't work.
    let id: String
    let subject: String
    let organizer: String
    /// Organizer's SMTP address from `event.organizer.emailAddress.address`.
    /// Nil when Graph doesn't return one.
    let organizerEmail: String?
    let start: Date
    let end: Date
    /// From `onlineMeeting.joinUrl` when present. iOS routes the URL to
    /// Teams when installed. Nil when the event has no online meeting.
    let joinUrl: String?
    let responseStatus: MeetingResponse
    /// True when at least one other non-cancelled, non-declined event in
    /// today's window overlaps this one's time range.
    let hasConflict: Bool

    func with(responseStatus: MeetingResponse) -> Meeting {
        Meeting(id: id,
                subject: subject,
                organizer: organizer,
                organizerEmail: organizerEmail,
                start: start,
                end: end,
                joinUrl: joinUrl,
                responseStatus: responseStatus,
                hasConflict: hasConflict)
    }
}

/// Mirrors Graph's `responseStatus.response` values verbatim.
enum MeetingResponse: String, Codable {
    case none
    case notResponded
    case organizer
    case accepted
    case tentativelyAccepted
    case declined

    /// False for events the user organizes or events with no invite
    /// relationship (`.none`) — Graph rejects accept/decline on those.
    var canRsvp: Bool {
        switch self {
        case .organizer, .none: return false
        case .notResponded, .accepted, .tentativelyAccepted, .declined: return true
        }
    }
}
