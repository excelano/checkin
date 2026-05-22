// Email.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Email: Identifiable {
    let id: String
    let subject: String
    let from: String
    /// SMTP address; required for the outlookReply deep-link.
    let fromAddress: String
    /// Graph's `bodyPreview` — plain text, already HTML-stripped and
    /// truncated to ~255 chars on the server.
    let preview: String
    let received: Date
    /// Mirrors Graph `flag.flagStatus == "flagged"`.
    let isFlagged: Bool

    init(id: String,
         subject: String,
         from: String,
         fromAddress: String,
         preview: String,
         received: Date,
         isFlagged: Bool = false) {
        self.id = id
        self.subject = subject
        self.from = from
        self.fromAddress = fromAddress
        self.preview = preview
        self.received = received
        self.isFlagged = isFlagged
    }

    func with(isFlagged: Bool) -> Email {
        Email(id: id, subject: subject, from: from,
              fromAddress: fromAddress, preview: preview,
              received: received, isFlagged: isFlagged)
    }
}
