// ResponseTemplateRegistry.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Every TTS string CheckIn produces lives here, organized by response
/// category. Phrasings are reviewed against `PERSONA.md`: calm, capable,
/// brief; warm without familiarity; first person singular; light dry
/// humor only on refusals and redirects, never on operations.
///
/// Pools support D18 refusals, D19 redirects, D21 latency reassurance and
/// errors, D28 confirmations, D30 help, and D31 onboarding invitations.
/// Anti-repeat is enforced by `PersonaResponseGenerator`, which threads
/// `DialogContext.recentRefusals` / `recentRedirects` through phrasing
/// selection so the same line never repeats inside the look-back window.
enum ResponseTemplateRegistry {

    // MARK: - D18 out-of-scope refusal pool
    //
    // The user asked something outside calendar, email, and chats. Variants
    // range from concise to lightly conversational. A small fraction carry
    // a touch of dry humor; none are sarcastic. PERSONA.md governs tone.

    static let refusals: [String] = [
        "Outside my range. I know your calendar, email, and chats.",
        "Not my area. Try meetings, mail, or chats.",
        "I keep to your work day. Calendar, email, and chats.",
        "That's outside my range. Try me on calendar, email, or chats.",
        "Out of bounds. I cover meetings, mail, and chats.",
        "Not something I do. I stick to calendar, email, and chats.",
        "Wrong neighborhood. Try meetings, mail, or chats.",
        "I don't go there. Calendar, email, and chats are my range.",
        "Beyond me. Ask about calendar, email, or chats.",
        "Not on my list. I handle meetings, mail, and chats.",
        "Different scope. I know calendar, email, and chats.",
        "I keep to a small lane. Calendar, email, and chats."
    ]

    // MARK: - D19 in-scope, voice-unsupported redirect pools
    //
    // The user asked something the voice surface doesn't yet do, but the
    // subject is in scope. Each sub-kind redirects to the touch path that
    // does work, and acknowledges the question is reasonable.

    static let readContentRedirects: [String] = [
        "I don't read bodies. Tap to open it in Outlook.",
        "Reading aloud isn't in my range yet. Tap to read it on screen.",
        "I don't read what's inside. Tap to open it in Outlook.",
        "Bodies stay on the screen. Tap to read it.",
        "Not reading aloud yet. Tap to open it in Outlook.",
        "I leave the reading to your eyes. Tap to open it.",
        "I don't speak the body. Tap to open it in Outlook.",
        "That's a screen job. Tap to open it in Outlook."
    ]

    static let summarizeContentRedirects: [String] = [
        "Summarizing isn't in my range yet. Tap to open it in Outlook.",
        "I don't summarize content. Tap to read it in Outlook.",
        "Not yet on summarizing. Tap to open it in Outlook.",
        "I leave reading and summarizing to Outlook. Tap to open it.",
        "Summaries of bodies aren't mine yet. Tap to open it.",
        "I summarize your day, not your messages. Tap to open it in Outlook.",
        "I don't read inside. Tap to open it in Outlook.",
        "Outside what I do. Tap to read it in Outlook."
    ]

    static let analyzeContentRedirects: [String] = [
        "I don't judge content. Tap to open it in Outlook.",
        "I don't read what's inside. Tap to open it in Outlook.",
        "Not my call to make. Tap to open it in Outlook.",
        "That's a read-and-decide one. Tap to open it.",
        "I don't have eyes on the body. Tap to open it in Outlook.",
        "I leave that read to you. Tap to open it in Outlook.",
        "I don't analyze messages. Tap to open it.",
        "Worth a look in Outlook. Tap to open it."
    ]

    static let voiceReplyRedirects: [String] = [
        "Replying isn't in my range yet. Tap to compose in Outlook.",
        "I don't reply by voice yet. Tap to open it in Outlook.",
        "Not yet on replies. Tap to compose in Outlook.",
        "Reply work happens in Outlook. Tap to open it.",
        "I leave composing to Outlook. Tap to reply there.",
        "Not yet writing on your behalf. Tap to compose in Outlook.",
        "I don't dictate replies yet. Tap to compose in Outlook.",
        "Composing isn't mine yet. Tap to open it in Outlook."
    ]

    static let listBrowseRedirects: [String] = [
        "I don't browse lists. Open Outlook for the full inbox.",
        "Not browsing yet. Open Outlook to see everything.",
        "I keep to the highlights. Open Outlook for the rest.",
        "Lists live in Outlook. Tap a row to open it.",
        "I don't read the inbox out. Open Outlook to browse.",
        "Browsing happens in Outlook. Tap a row to jump in.",
        "I summarize, I don't enumerate. Open Outlook for the full list.",
        "Long lists aren't mine. Tap a row to open Outlook."
    ]

    // MARK: - D21 latency and system errors
    //
    // The thinking earcon plays on every entry to processing. Spoken
    // reassurance kicks in if the fetch crosses 1.5 s, escalation if it
    // crosses 5 s. System errors get specific pools by category so the
    // user gets accurate information and an actionable next step.

    static let latencyReassurance: [String] = [
        "Checking your calendar.",
        "Looking now.",
        "One moment.",
        "Give me a sec.",
        "Hold on.",
        "Pulling that up.",
        "Just a moment.",
        "Working on it."
    ]

    static let latencyEscalation: [String] = [
        "Still working. Give me a moment.",
        "Hang on, almost there.",
        "Still pulling. Won't be long.",
        "Just a bit longer."
    ]

    static let errorNetwork: [String] = [
        "Can't reach Microsoft right now. Try again in a moment.",
        "No connection to Microsoft. Try again shortly.",
        "Microsoft is unreachable. Worth another try in a moment.",
        "I can't get to Microsoft right now. Try again soon.",
        "Network's not cooperating. Try again in a moment.",
        "Couldn't reach Microsoft. Try again."
    ]

    static let errorAuthExpired: [String] = [
        "Your session expired. Open settings to sign in again.",
        "Microsoft signed you out. Sign in again from settings.",
        "Sign-in's gone stale. Reauthenticate from settings.",
        "Your token's expired. Sign in again from settings.",
        "Need a fresh sign-in. Open settings to handle it.",
        "Sign-in expired. Settings has the sign-in button."
    ]

    static let errorThrottled: [String] = [
        "Microsoft's slowing me down briefly. Hold on a few seconds.",
        "Rate-limited for a moment. Try again shortly.",
        "Microsoft is throttling. Give it a few seconds.",
        "Slowed down by Microsoft for a beat. Try again soon.",
        "Brief throttle. Try again in a moment.",
        "Microsoft's pacing me. Give it a second."
    ]

    static let errorUnknown: [String] = [
        "Something went wrong. Try again?",
        "That didn't work. Try again?",
        "I hit a snag. Try again?",
        "Couldn't pull that off. Try again?",
        "Something's off. Try again?",
        "No luck this time. Try again?"
    ]

    // MARK: - Parse miss / unknown intent (recoverable)
    //
    // Distinct from D18 refusals: the system didn't classify the utterance
    // confidently. Re-prompt rather than refuse. The reprompt counter in
    // DialogContext escalates to suggest the touch path after repeat misses.

    static let parseMiss: [String] = [
        "I missed that. Try again?",
        "Sorry, didn't catch that.",
        "One more time?",
        "I missed it. Say again?",
        "Didn't get that. Try again?",
        "Couldn't make that out. Once more?"
    ]

    static let parseMissEscalated: [String] = [
        "Still not catching you. Tap the mic and try once more, or tap the question mark for examples.",
        "I'm missing it. Try one more time, or tap the question mark for what I can do."
    ]

    // MARK: - D30 help
    //
    // Short voice variant runs about 15 seconds; the long variant covers
    // every Day 1 capability. The full reference always lives on the
    // visual surface (HelpView).

    static let helpShort: String =
        "I know your calendar, email, and chats. Try 'what's on my plate,' " +
        "or 'open Tony's email.' Tap the question mark for everything I do."

    static let helpLong: String =
        "I cover three things. Calendar, email, and chats. " +
        "Ask 'what's on my plate' for a summary. " +
        "Ask 'any from Tony' to filter by sender. " +
        "Say 'open Tony's email' or 'open my next meeting' to jump to Outlook or Teams. " +
        "Say 'check again' to refresh, 'say that again' to repeat, or 'stop' to cut me off. " +
        "Tap the question mark for the full list."

    // MARK: - D31 onboarding invitations
    //
    // Step 4 of first-run: the system speaks a varied invitation, the
    // user runs their first query, and the help affordance lands in
    // muscle memory. Pool stays small but distinct enough that re-onboarding
    // (after a state reset) doesn't feel identical.

    static let onboardingInvitations: [String] = [
        "Try saying: what's on my plate.",
        "Give it a try: what do I have today?",
        "Ask me: any from anyone important?",
        "Say: what's the rundown.",
        "Try: anything new since this morning?"
    ]

    // MARK: - D28 confirmations and announcements
    //
    // Confirmation prompts are templated by ActionKind and parameters.
    // The "yes" path announces brief success; the "no" path acknowledges
    // and returns. Phrasings stay plain — confirmations are the wrong
    // place for humor.

    static func confirmationPrompt(for action: PendingAction) -> String {
        switch action.kind {
        case .markEmailRead:
            return "Mark \(action.target)'s email as read?"
        case .flagEmail:
            return "Flag \(action.target)'s email?"
        case .softDeleteEmail:
            return "Move \(action.target)'s email to Deleted Items?"
        case .markAllEmailsRead:
            return "Mark all emails from \(action.target) as read?"
        case .flagAllEmails:
            return "Flag all emails from \(action.target)?"
        case .softDeleteAllEmails:
            return "Move all emails from \(action.target) to Deleted Items?"
        }
    }

    static func successAnnouncement(for action: PendingAction) -> String {
        switch action.kind {
        case .markEmailRead, .markAllEmailsRead:
            return "Marked."
        case .flagEmail, .flagAllEmails:
            return "Flagged."
        case .softDeleteEmail, .softDeleteAllEmails:
            return "Moved to Deleted Items."
        }
    }

    static let confirmationCancel: String = "OK, leaving them."

    // MARK: - D7 disambiguation
    //
    // Names the original utterance back to the user so they understand
    // what's being asked, then enumerates candidates briefly.

    static func disambiguationPrompt(heardSurface: String,
                                     candidates: [Candidate]) -> String {
        let names = candidates.map { $0.label }
        let joined: String
        switch names.count {
        case 0: joined = ""
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) or \(names[1])"
        default:
            let last = names.last ?? ""
            let lead = names.dropLast().joined(separator: ", ")
            joined = "\(lead), or \(last)"
        }
        return "I heard '\(heardSurface).' Did you mean \(joined)?"
    }

    // MARK: - Routine acknowledgments

    static let stopAcknowledged: String = ""           // No spoken ack on stop; the silence is the answer.
    static let exitAcknowledged: String = "See you."
    static let nothingToRepeat: String = "Nothing to repeat yet."
    static let settingsOpened: String = ""             // Settings sheet replaces speech.
    static let helpOpened: String = ""                 // Same: help sheet replaces speech.

    // MARK: - Open routing (5.3a)

    static func openNotFound(_ entity: String) -> String {
        "I don't have anything from \(entity). Try refreshing."
    }

    static let openAmbiguous: String = "I have a few. Could you be more specific?"
    static let openMeetingNone: String = "Nothing on your calendar to open."
    static let openLaunchFailed: String = "Couldn't open it. Make sure the app is installed."

    // MARK: - Summary phrasing

    /// The user's question targets a single domain when they name it
    /// explicitly. `.all` means either no domain word matched or two or
    /// more domains matched and we fall back to the full three-part
    /// summary instead of guessing which the user wanted.
    enum SummaryDomain { case email, chat, meeting, all }

    /// Keyword scan over the utterance. "message"/"messages" routes to
    /// email — that's the dominant register in M365 voice queries, and
    /// the user can disambiguate with "chats" or "teams" when they mean
    /// the other thing.
    static func detectDomain(_ utterance: String) -> SummaryDomain {
        let lower = utterance.lowercased()

        let emailHits = ["email", "mail", "unread", "inbox",
                         "message", "messages"].contains { lower.contains($0) }
        let chatHits = ["chat", "chats", "teams"].contains { lower.contains($0) }
        let meetingHits = ["meeting", "calendar", "appointment",
                           "schedule", "agenda"].contains { lower.contains($0) }

        let count = [emailHits, chatHits, meetingHits].filter { $0 }.count
        if count > 1 { return .all }
        if emailHits { return .email }
        if chatHits { return .chat }
        if meetingHits { return .meeting }
        return .all
    }

    /// Builds a Day 1 summary sentence from the current `CheckInSummary`.
    /// PERSONA.md verbosity defaults to terse: two or three short sentences.
    /// Verbosity expansion (D5) lives outside this function and feeds into
    /// the call site instead of branching here.
    static func summarySentence(from summary: CheckInSummary) -> String {
        var parts: [String] = []

        if let meeting = summary.meeting {
            parts.append(meetingPhrase(meeting))
        } else {
            parts.append("Nothing on your calendar coming up.")
        }

        switch summary.emails.count {
        case 0:
            parts.append("No unread.")
        case 1:
            parts.append("One unread, from \(summary.emails[0].from).")
        case 2:
            parts.append("Two unread, from \(summary.emails[0].from) and \(summary.emails[1].from).")
        case let n:
            let first = summary.emails[0].from
            parts.append("\(spellCount(n)) unread, the latest from \(first).")
        }

        if summary.teamsEnabled {
            switch summary.chats.count {
            case 0: break
            case 1: parts.append("One chat, from \(summary.chats[0].from).")
            default: parts.append("\(spellCount(summary.chats.count)) chats.")
            }
        }

        return parts.joined(separator: " ")
    }

    static func summaryEmailOnly(from summary: CheckInSummary) -> String {
        switch summary.emails.count {
        case 0:
            return "No unread."
        case 1:
            return "One unread, from \(summary.emails[0].from)."
        case let n:
            let first = summary.emails[0].from
            return "\(spellCount(n)) unread, the latest from \(first)."
        }
    }

    static func summaryChatOnly(from summary: CheckInSummary) -> String {
        guard summary.teamsEnabled else {
            return "Teams isn't enabled."
        }
        switch summary.chats.count {
        case 0:
            return "No pending chats."
        case 1:
            return "One chat, from \(summary.chats[0].from)."
        case let n:
            return "\(spellCount(n)) chats."
        }
    }

    static func summaryMeetingOnly(from summary: CheckInSummary) -> String {
        if let meeting = summary.meeting {
            return meetingPhrase(meeting)
        }
        return "Nothing on your calendar coming up."
    }

    /// Narrow the email list to one sender and read the count back with
    /// the latest subject. `sender` is the canonical form resolved by
    /// `EntityMatcher` — case-insensitive against `email.from`.
    static func summaryFilteredBySender(from summary: CheckInSummary,
                                        matching sender: String) -> String {
        let matches = summary.emails.filter {
            $0.from.localizedCaseInsensitiveCompare(sender) == .orderedSame
        }
        switch matches.count {
        case 0:
            return "Nothing from \(sender)."
        case 1:
            return "One from \(sender), about \(matches[0].subject)."
        case let n:
            return "\(spellCount(n)) from \(sender), the latest about \(matches[0].subject)."
        }
    }

    private static func meetingPhrase(_ meeting: Meeting) -> String {
        let now = Date()
        let interval = meeting.start.timeIntervalSince(now)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: meeting.start)
        if interval < 0 {
            return "Your meeting started already."
        } else if interval < 5 * 60 {
            return "Your next meeting starts in a few minutes."
        } else if interval < 60 * 60 {
            let minutes = Int(interval / 60)
            return "Next meeting in \(minutes) minutes."
        } else {
            return "Next meeting at \(timeString)."
        }
    }

    private static let smallNumbers: [Int: String] = [
        2: "Two", 3: "Three", 4: "Four", 5: "Five", 6: "Six", 7: "Seven",
        8: "Eight", 9: "Nine", 10: "Ten"
    ]

    private static func spellCount(_ n: Int) -> String {
        smallNumbers[n] ?? "\(n)"
    }
}
