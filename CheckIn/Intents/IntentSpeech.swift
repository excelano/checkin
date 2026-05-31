// IntentSpeech.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation

/// Spoken-dialog phrasing shared across CheckIn's App Intents so the
/// "next meeting" and "unread messages" sentences read identically
/// whether they're asked for on their own (`NextMeetingIntent`,
/// `CheckInCountIntent`) or stitched together (`WorkdaySummaryIntent`).
///
/// These return plain `String`s rather than `IntentDialog`, so the
/// work-day summary can concatenate two sentences before wrapping the
/// result in a single dialog; each caller wraps via string interpolation.
enum IntentSpeech {
    /// "You have no Xs." / "You have 1 X." / "You have N Xs."
    static func count(_ n: Int, singular: String, plural: String) -> String {
        switch n {
        case 0: return "You have no \(plural)."
        case 1: return "You have 1 \(singular)."
        default: return "You have \(n) \(plural)."
        }
    }

    /// The next-meeting sentence, matching `NextMeetingIntent`'s wording.
    static func nextMeeting(_ meeting: Meeting?) -> String {
        guard let meeting else {
            return "You have no more meetings today."
        }
        let time = meeting.start.formatted(date: .omitted, time: .shortened)
        return "Your next meeting is \(meeting.subject) at \(time)."
    }

    /// The current-presence sentence, Out-of-Office-dominant to match how
    /// the glance and widget render state (OOO overrides the pill).
    /// `.unknown` means "no preference set" rather than a real status, so
    /// it reads as automatic rather than speaking the "—" display name.
    static func currentPresence(_ presence: Presence, isOutOfOffice: Bool) -> String {
        if isOutOfOffice {
            return presence == .unknown
                ? "Out of office is on."
                : "Out of office is on, and you're showing as \(presence.displayName)."
        }
        return presence == .unknown
            ? "Your status isn't set — Microsoft 365 is showing it automatically."
            : "You're showing as \(presence.displayName)."
    }

    /// The combined unread-messages sentence (emails plus chats), matching
    /// `CheckInCountIntent`'s `.unreadMessages` wording.
    static func unreadMessages(emails: Int, chats: Int) -> String {
        switch (emails, chats) {
        case (0, 0):
            return "You're all caught up — no unread messages."
        case (let e, 0):
            return count(e, singular: "unread email", plural: "unread emails")
        case (0, let c):
            return count(c, singular: "unread chat", plural: "unread chats")
        default:
            let e = emails == 1 ? "1 email" : "\(emails) emails"
            let c = chats == 1 ? "1 chat" : "\(chats) chats"
            return "You have \(emails + chats) unread messages: \(e) and \(c)."
        }
    }
}
