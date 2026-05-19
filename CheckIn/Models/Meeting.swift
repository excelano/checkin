// Meeting.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct Meeting: Identifiable {
    let id = UUID()
    let subject: String
    let organizer: String
    let location: String
    let start: Date
    let end: Date
    let isOnline: Bool
    let attendees: [String]
}
