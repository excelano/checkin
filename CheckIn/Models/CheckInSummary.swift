// CheckInSummary.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct CheckInSummary {
    var emails: [Email]
    var chats: [ChatMessage]
    /// Total unread across the mailbox. `emails` is capped at 20 newest;
    /// the section footer uses `totalUnreadEmails - emails.count` to show
    /// "X more unread" when there are more than we render.
    var totalUnreadEmails: Int
}
