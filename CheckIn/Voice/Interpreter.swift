// Interpreter.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Parses a transcript into a `Command` the executor can run. The seam
/// lets the implementation grow from a literal phrase table to pattern
/// matching to embeddings without disturbing the executor or domain
/// layers. Returns `nil` for unrecognized input — the caller decides
/// whether to refuse, prompt, or fall back to the legacy voice path.
protocol Interpreter {
    func interpret(_ text: String) -> Command?
}

/// Initial implementation: a literal lookup against a small, hand-listed
/// set of phrasings. Trivial to extend, trivial to test. Phrases are
/// normalized (lowercased, trimmed) before matching so common
/// recognizer artifacts don't miss the table.
struct PhraseInterpreter: Interpreter {

    func interpret(_ text: String) -> Command? {
        let normalized = normalize(text)

        // Literal lookups for parameter-less phrases.
        switch normalized {
        case "refresh", "check", "check again":
            return .refresh
        default:
            break
        }

        // "mark email N as read" / "mark message N as read" / "mark email N read".
        // The optional `as` covers both natural phrasings without exploding the
        // table. Digit form only for now — word-form ("one", "two") can land
        // alongside a number-word parser in a later step if needed.
        if let match = normalized.firstMatch(of: #/^mark (?:email|message) (\d+)(?: as)? read$/#),
           let n = Int(match.1) {
            return .markRead(index: n)
        }

        return nil
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
