// CheckInSnapshot.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// IMPORTANT: this struct is duplicated at CheckInWidget/CheckInSnapshot.swift.
// Synchronized-group target memberships in Xcode don't easily let one
// Swift file belong to both targets, so the two copies must stay
// byte-for-byte identical. Update both, or move to a Swift Package
// when this is too much to maintain.

import Foundation

/// Snapshot of CheckIn state written to the App Group on every refresh,
/// for the widget to read. Trimmed to just what the widget can render —
/// the widget can't authenticate or call Graph, so anything not in this
/// struct is invisible to it.
struct CheckInSnapshot: Codable {
    /// When the main app last refreshed and wrote this snapshot.
    let updatedAt: Date
    /// Subject of the next meeting today, or nil if none remain.
    let nextMeetingSubject: String?
    /// Start time of the next meeting, or nil if none remain.
    let nextMeetingStart: Date?
    /// Organizer name for the next meeting (drives the "with X" line).
    let nextMeetingOrganizer: String?
    /// Teams join URL for the next meeting (drives the Join pill).
    /// Nil for events without an online meeting attached.
    let nextMeetingJoinUrl: String?
    /// Number of unread emails in the inbox (total, not just the visible ones).
    let unreadEmailCount: Int
    /// Number of pending Teams chats waiting on a reply.
    let chatCount: Int

    /// Identifier shared between the main app and the widget extension
    /// for the App Group container both can read/write.
    static let appGroupIdentifier = "group.com.excelano.checkin"
    /// Key inside the App Group's UserDefaults where the encoded
    /// snapshot is stored.
    static let userDefaultsKey = "snapshot"
}
