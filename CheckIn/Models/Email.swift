// Email.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Email: Identifiable {
    let id: String
    let subject: String
    let from: String
    /// SMTP address of the sender. Surfaced for per-sender bulk actions
    /// (Mark/Delete all from this sender) and for the recipient line in
    /// the reply composer.
    let fromAddress: String
    /// Graph's `bodyPreview` — plain text, already HTML-stripped and
    /// truncated to ~255 chars on the server.
    let preview: String
    let received: Date
    /// Mirrors Graph `flag.flagStatus == "flagged"`.
    let isFlagged: Bool
    /// Graph's `inferenceClassification`: "focused" or "other". Drives the
    /// "Mark N in Other" bulk action.
    let inferenceClassification: String?
    /// EventMessage subtype's `meetingMessageType`. Nil for non-meeting
    /// messages. Values include `meetingRequest`, `meetingCancelled`,
    /// `meetingAccepted`, `meetingTentativelyAccepted`, `meetingDeclined`.
    let meetingMessageType: String?
    /// Start of the referenced meeting, read from `eventMessage.startDateTime`
    /// in the list query. Used to match invite emails to their underlying
    /// calendar event (Graph's `$expand=event` returns empty stubs for
    /// future invitations, so we sidestep it and match on subject + start).
    /// Nil on non-meeting messages and on the rare invite where Graph
    /// omits the field.
    let meetingStart: Date?
    /// End of the referenced meeting. Same provenance as `meetingStart`.
    let meetingEnd: Date?
    /// True when the message has an RFC 2369 `List-Unsubscribe` header —
    /// the standard signal that a message came from a mailing list.
    /// Derived in GraphClient from `internetMessageHeaders`.
    let isMailingList: Bool

    init(id: String,
         subject: String,
         from: String,
         fromAddress: String,
         preview: String,
         received: Date,
         isFlagged: Bool = false,
         inferenceClassification: String? = nil,
         meetingMessageType: String? = nil,
         meetingStart: Date? = nil,
         meetingEnd: Date? = nil,
         isMailingList: Bool = false) {
        self.id = id
        self.subject = subject
        self.from = from
        self.fromAddress = fromAddress
        self.preview = preview
        self.received = received
        self.isFlagged = isFlagged
        self.inferenceClassification = inferenceClassification
        self.meetingMessageType = meetingMessageType
        self.meetingStart = meetingStart
        self.meetingEnd = meetingEnd
        self.isMailingList = isMailingList
    }

    func with(isFlagged: Bool) -> Email {
        Email(id: id, subject: subject, from: from,
              fromAddress: fromAddress, preview: preview,
              received: received, isFlagged: isFlagged,
              inferenceClassification: inferenceClassification,
              meetingMessageType: meetingMessageType,
              meetingStart: meetingStart,
              meetingEnd: meetingEnd,
              isMailingList: isMailingList)
    }
}

extension Email {
    /// Graph `meetingMessageType` values that represent the noise that
    /// piles up after the actionable invite — cancellations and RSVP
    /// responses from other attendees. `meetingRequest` is intentionally
    /// excluded; that's the original invite, still actionable.
    static let meetingNoticeMessageTypes: Set<String> = [
        "meetingCancelled",
        "meetingAccepted",
        "meetingTentativelyAccepted",
        "meetingDeclined"
    ]

    /// True when this email is a meeting cancellation or RSVP response.
    /// Drives the "Mark N meeting notices read" bulk action.
    var isMeetingNotice: Bool {
        guard let type = meetingMessageType else { return false }
        return Self.meetingNoticeMessageTypes.contains(type)
    }

    /// True when this email is an original meeting invitation
    /// (excludes updates and cancellations — those are
    /// `isMeetingNotice`). Gate for invite-row RSVP UI and for the
    /// invite-to-calendar matcher.
    var isInvite: Bool {
        meetingMessageType == "meetingRequest"
    }
}
