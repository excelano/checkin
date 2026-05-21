// Email.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Email: Identifiable {
    let id: String        // Graph API message ID
    let subject: String
    let from: String      // display name
    let fromAddress: String  // SMTP address; required for outlookReply deep-link
    let preview: String   // bodyPreview
    let received: Date
    /// Graph `flag.flagStatus == "flagged"`. Drives the row's flag
    /// indicator and the toggle label on the leading swipe action.
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

    /// Return a copy with a new flag state. Used by `InboxActions` for
    /// optimistic toggles since the struct is otherwise immutable.
    func with(isFlagged: Bool) -> Email {
        Email(id: id, subject: subject, from: from,
              fromAddress: fromAddress, preview: preview,
              received: received, isFlagged: isFlagged)
    }
}
