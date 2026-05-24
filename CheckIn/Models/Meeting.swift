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
    /// Universal meeting identifier — hex string of the same binary value
    /// that lives on the corresponding eventMessage's `PidLidGlobalObjectId`
    /// MAPI property. Lets us join an invite email to its event without
    /// fuzzy subject/time matching. Nil only when Graph omits the field.
    let iCalUId: String?

    func with(responseStatus: MeetingResponse) -> Meeting {
        Meeting(id: id,
                subject: subject,
                organizer: organizer,
                organizerEmail: organizerEmail,
                start: start,
                end: end,
                joinUrl: joinUrl,
                responseStatus: responseStatus,
                hasConflict: hasConflict,
                iCalUId: iCalUId)
    }

    func with(hasConflict: Bool) -> Meeting {
        Meeting(id: id,
                subject: subject,
                organizer: organizer,
                organizerEmail: organizerEmail,
                start: start,
                end: end,
                joinUrl: joinUrl,
                responseStatus: responseStatus,
                hasConflict: hasConflict,
                iCalUId: iCalUId)
    }
}

extension Meeting {
    /// True when `email` refers to this meeting. Canonical predicate
    /// used everywhere that has to bridge email ↔ meeting (the row's
    /// invitation lookup, the invite-cache builder, the post-RSVP
    /// auto-mark-read). Combining the matching here keeps the three
    /// surfaces from drifting — earlier versions had three near-copies
    /// that disagreed on whether to use start-time or organizer-fallback
    /// matching.
    ///
    /// Two-tier match:
    /// 1. Normalized subject equality, also accepting the "Updated:"
    ///    and "Cancelled:" prefixes Outlook applies to meeting-update
    ///    and meeting-cancellation emails.
    /// 2. Two-factor fallback for tenant-specific subject prefixes
    ///    (e.g. "Meeting request:", "Invitation:") — requires the
    ///    email is a meetingMessage from the meeting's organizer, then
    ///    accepts a `contains` match on the normalized subjects.
    ///
    /// When the email carries a start time (invitations do, via
    /// `eventMessage.startDateTime`), the times must agree within a
    /// minute. This disambiguates same-titled recurring meetings — a
    /// "Status update" invitation for next Monday won't be matched
    /// against an instance of the same series on today's calendar.
    func matches(_ email: Email) -> Bool {
        let target = subject.normalizedSubjectKey
        let key = email.subject.normalizedSubjectKey
        guard !target.isEmpty, !key.isEmpty else { return false }

        let subjectMatch: Bool
        if key == target
            || key == "updated: \(target)"
            || key == "cancelled: \(target)" {
            subjectMatch = true
        } else if let organizer = organizerEmail?
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !organizer.isEmpty,
                  email.fromAddress.lowercased() == organizer,
                  email.meetingMessageType != nil,
                  key.contains(target) {
            subjectMatch = true
        } else {
            subjectMatch = false
        }
        guard subjectMatch else { return false }

        if let emailStart = email.meetingStart {
            return abs(start.timeIntervalSince(emailStart)) < 60
        }
        return true
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

    /// Short pill label for the actioned states. Nil for states that
    /// shouldn't surface as a "you replied" hint.
    var displayLabel: String? {
        switch self {
        case .accepted: return "Accepted"
        case .tentativelyAccepted: return "Tentative"
        case .declined: return "Declined"
        case .organizer, .none, .notResponded: return nil
        }
    }
}
