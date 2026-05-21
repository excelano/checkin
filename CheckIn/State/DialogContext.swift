// DialogContext.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Per-session dialog state held alongside the state machine. Memory only;
/// nothing persists to disk.
struct DialogContext {
    /// The most recent named entity in scope, used to resolve pronouns and
    /// elliptical follow-ups ("read it", "from him").
    var focusedEntity: String?

    /// The latest summary fetched from Microsoft Graph. Cached so that
    /// follow-up queries ("how many emails?") don't trigger a refetch.
    var summary: CheckInSummary?

    var lastUtterance: String?
    var lastSystemResponse: String?

    /// Bounded ring of recent turns. The window is small by design: voice
    /// dialog history beyond a handful of turns rarely informs the next
    /// response and burns memory.
    var turnHistory: [Turn] = []

    /// Consecutive voice-resolution misses while in `.disambiguating`. Two
    /// misses in a row bail out so the user doesn't get trapped in retries.
    var disambiguationFailedAttempts: Int = 0

    /// Reprompt counter for repeat-after-no-input flows. Reset on a
    /// successful turn or on transition out of `listening`.
    var repromptCount: Int = 0

    /// Recent refusal phrasings, oldest first. Used by `ResponseGenerator`
    /// to avoid repeating the same line within a short window.
    var recentRefusals: [String] = []

    /// Recent redirect phrasings for the same anti-repeat purpose.
    var recentRedirects: [String] = []

    /// How many turns of history to keep. Anything beyond this is dropped.
    static let turnHistoryLimit = 8

    /// How many recent refusals/redirects to remember for anti-repeat.
    static let recentPhrasingLimit = 4

    mutating func recordTurn(user: String, system: String) {
        let turn = Turn(userUtterance: user, systemResponse: system, timestamp: Date())
        turnHistory.append(turn)
        if turnHistory.count > Self.turnHistoryLimit {
            turnHistory.removeFirst(turnHistory.count - Self.turnHistoryLimit)
        }
        lastUtterance = user
        // Silent-by-design intents (.stop, .refresh, .open on a successful
        // deep-link route) carry an empty `system`. They shouldn't shadow
        // the prior spoken response — `.repeatLast` should still surface
        // the last sentence the user actually heard.
        if !system.isEmpty {
            lastSystemResponse = system
        }
    }

    mutating func rememberPhrasing(_ phrasing: String, in category: ResponseCategory) {
        switch category {
        case .refusal:
            Self.append(phrasing, to: &recentRefusals)
        case .redirect:
            Self.append(phrasing, to: &recentRedirects)
        default:
            break
        }
    }

    private static func append(_ phrasing: String, to ring: inout [String]) {
        ring.append(phrasing)
        if ring.count > Self.recentPhrasingLimit {
            ring.removeFirst(ring.count - Self.recentPhrasingLimit)
        }
    }
}

struct Turn: Equatable {
    let userUtterance: String
    let systemResponse: String
    let timestamp: Date
}
