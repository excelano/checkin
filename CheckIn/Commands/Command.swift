// Command.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// A user-resolved action against the inbox. Exactly the operations the
/// GUI exposes — no more. Voice and touch both produce these; the touch
/// surface emits them directly from gestures, the voice surface emits
/// them through `Interpreter`. As new touch gestures land, new cases
/// land here; voice never gets ahead of the GUI.
enum Command: Equatable {
    case refresh
    /// 1-based index into the displayed unread email list (matches what
    /// the user sees on screen). Out-of-range indices refuse with a
    /// spoken response rather than rolling forward.
    case markRead(index: Int)
}

/// What the executor returns from running a command. `spokenResponse` is
/// the canonical phrasing — single string per outcome, no persona pool.
/// Empty string means silent (e.g., a deep-link that's its own feedback
/// via the app switch).
struct CommandResult: Equatable {
    let spokenResponse: String
}

/// Runs commands. Voice and touch both route here so a single execution
/// path covers both inputs. Currently delegates to `InboxActions` for
/// mutations and to URL openers for deep links; the shape will grow as
/// more commands land.
@MainActor
final class CommandExecutor {
    private let inboxActions: InboxActions
    private let stateMachine: StateMachine

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "executor")

    init(inboxActions: InboxActions, stateMachine: StateMachine) {
        self.inboxActions = inboxActions
        self.stateMachine = stateMachine
    }

    func execute(_ command: Command) async -> CommandResult {
        #if DEBUG
        print("[command] execute \(command)")
        #endif
        switch command {
        case .refresh:
            await inboxActions.refresh()
            return CommandResult(spokenResponse: "Refreshed.")
        case .markRead(let index):
            guard let email = email(at: index) else {
                return CommandResult(spokenResponse: "I don't see email \(index).")
            }
            await inboxActions.markRead(emailId: email.id)
            return CommandResult(spokenResponse: "Marked email \(index) read.")
        }
    }

    /// Resolve a 1-based, user-spoken index into the displayed unread
    /// email list. Returns nil for out-of-range indices, which the
    /// caller turns into a spoken refusal.
    private func email(at index: Int) -> Email? {
        guard let summary = stateMachine.context.summary else { return nil }
        guard index >= 1, index <= summary.emails.count else { return nil }
        return summary.emails[index - 1]
    }
}
