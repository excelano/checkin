// Meeting.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Meeting: Identifiable {
    let id = UUID()
    let subject: String
    let organizer: String
    let start: Date
    /// From `onlineMeeting.joinUrl` when present. iOS routes the URL to
    /// Teams when installed. Nil when the event has no online meeting.
    let joinUrl: String?
}
