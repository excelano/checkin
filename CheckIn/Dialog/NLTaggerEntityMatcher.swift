// NLTaggerEntityMatcher.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Entity matcher per D15. Personal-name resolution is longest-canonical
/// -substring matching against the lowercased utterance, scoped to the
/// senders and chat partners in the current `DialogContext.summary`. The
/// earlier NLTagger-driven path over-fired on vendor tokens that lead
/// several known sender names ("Microsoft" leading "Microsoft Outlook",
/// "Microsoft Teams", "Microsoft 365 Message Center", ...): it surfaced
/// every Microsoft-prefix candidate and pushed the dialog into a noisy
/// D7 disambiguation. The current implementation prefers a full-canonical
/// span ("tony smith"), falls back to a first-name span ("tony") only
/// when the bare token resolves a small set of real-person candidates,
/// and otherwise returns nothing so `SessionCoordinator.extractFromName`
/// can route the surface to `filterUnknownSender`.
///
/// `contextualStrings` priming on the speech recognizer side (per D9 and
/// D10) handles the upstream half: the recognizer is more likely to spell
/// "Hernandez" correctly when a known contact is on the call sheet. This
/// matcher handles the downstream half: matching the recognized tokens
/// to concrete entities the dialog can act on.
struct NLTaggerEntityMatcher: EntityMatcher {

    /// Suppress first-name fallback when this many or more known people
    /// share a leading token. That pattern is structurally a vendor
    /// sending under multiple display names (Microsoft Outlook,
    /// Microsoft Teams, ...), not a real-person disambiguation that D7
    /// can handle — leave matches empty so the surface routes through
    /// `filterUnknownSender`.
    private static let firstNameFallbackCeiling = 4

    /// Numeric ordinals readable by the dialog. The classifier folds
    /// "the first" / "first one" / "number one" alike to position 1.
    private static let ordinalWords: [String: Int] = [
        "first": 1, "1st": 1, "one": 1,
        "second": 2, "2nd": 2, "two": 2,
        "third": 3, "3rd": 3, "three": 3,
        "fourth": 4, "4th": 4, "four": 4,
        "fifth": 5, "5th": 5, "five": 5,
        "sixth": 6, "6th": 6, "six": 6,
        "seventh": 7, "7th": 7, "seven": 7,
        "eighth": 8, "8th": 8, "eight": 8,
        "ninth": 9, "9th": 9, "nine": 9,
        "tenth": 10, "10th": 10, "ten": 10
    ]

    /// Relative date phrases the dialog accepts at Day 1. Day 2 quick-time
    /// queries (D29) extend this with explicit times.
    private static let dateWords: Set<String> = [
        "today", "tomorrow", "tonight",
        "this morning", "this afternoon", "this evening",
        "this week", "next week"
    ]

    func match(text: String, domain: EntityDomain, context: DialogContext) -> [EntityMatch] {
        let lower = text.lowercased()
        switch domain {
        case .person:
            return matchPeople(in: text, lowercased: lower, context: context)
        case .ordinal:
            return matchOrdinals(in: lower)
        case .date:
            return matchDates(in: lower)
        case .number:
            return matchNumbers(in: lower)
        case .subject:
            // Day 1 has no structured subject extraction. Phase 4 may add
            // a fuzzy match against current email subjects when filter by
            // topic lands in the response surface.
            return []
        }
    }

    // MARK: - Person matching

    private func matchPeople(in text: String,
                             lowercased: String,
                             context: DialogContext) -> [EntityMatch] {
        let knownPeople = peopleInScope(context: context)
        return matchAgainstKnown(text: text,
                                 lowercasedText: lowercased,
                                 knownPeople: knownPeople)
    }

    /// Distinct senders and chat partners from the current summary. These
    /// are the only people the dialog can act on this turn.
    private func peopleInScope(context: DialogContext) -> [String] {
        guard let summary = context.summary else { return [] }
        var seen = Set<String>()
        var people: [String] = []
        for email in summary.emails where !email.from.isEmpty && seen.insert(email.from).inserted {
            people.append(email.from)
        }
        for chat in summary.chats where !chat.from.isEmpty && seen.insert(chat.from).inserted {
            people.append(chat.from)
        }
        return people
    }

    /// Longest-canonical-substring matching against the lowercased
    /// utterance. The bare-token first-name fallback fires only when the
    /// utterance doesn't already contain a full canonical and the first
    /// name resolves a small number of candidates; vendor tokens that
    /// lead 4+ known senders are dropped so the surface routes through
    /// `filterUnknownSender` instead of triggering a noisy disambig.
    ///
    /// `text` is the original-case utterance; the surface stored on
    /// each match is extracted from it at the indices found in
    /// `lowercasedText` so spoken templates ("There are multiple senders
    /// that match Tony.") read naturally.
    private func matchAgainstKnown(text: String,
                                   lowercasedText: String,
                                   knownPeople: [String]) -> [EntityMatch] {
        guard !knownPeople.isEmpty else { return [] }
        var matches: [EntityMatch] = []
        var consumed: [Range<String.Index>] = []

        let sortedKnown = knownPeople.sorted { $0.count > $1.count }
        for person in sortedKnown {
            let needle = person.lowercased()
            guard let range = wholeWordRange(of: needle, in: lowercasedText),
                  !consumed.contains(where: { $0.overlaps(range) }) else { continue }
            consumed.append(range)
            let surface = casedSubstring(of: text, atLowercasedRange: range, in: lowercasedText) ?? person
            matches.append(EntityMatch(surface: surface,
                                       canonical: person,
                                       confidence: 0.95))
        }
        if !matches.isEmpty { return matches }

        var byFirstName: [String: [String]] = [:]
        for person in knownPeople {
            let firstName = person.split(separator: " ").first.map(String.init) ?? person
            let key = firstName.lowercased()
            guard !key.isEmpty else { continue }
            byFirstName[key, default: []].append(person)
        }
        for (firstName, candidates) in byFirstName {
            guard let range = wholeWordRange(of: firstName, in: lowercasedText) else { continue }
            if candidates.count >= Self.firstNameFallbackCeiling { continue }
            let surface = casedSubstring(of: text, atLowercasedRange: range, in: lowercasedText)
                ?? firstName.capitalized
            if candidates.count == 1 {
                matches.append(EntityMatch(surface: surface,
                                           canonical: candidates[0],
                                           confidence: 0.85))
            } else {
                for person in candidates {
                    matches.append(EntityMatch(surface: surface,
                                               canonical: person,
                                               confidence: 0.6))
                }
            }
        }
        return matches
    }

    private func wholeWordRange(of needle: String,
                                in haystack: String) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
        return haystack.range(of: pattern, options: .regularExpression)
    }

    /// Map a range found in the lowercased string back onto the original
    /// utterance. Index alignment holds for ASCII English names; on the
    /// rare Unicode mismatch we fall back to the lowercased substring
    /// rather than risk an out-of-bounds slice.
    private func casedSubstring(of text: String,
                                atLowercasedRange range: Range<String.Index>,
                                in lowercased: String) -> String? {
        let lowerStart = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
        let lowerEnd = lowercased.distance(from: lowercased.startIndex, to: range.upperBound)
        guard lowerStart <= text.count, lowerEnd <= text.count else { return nil }
        let start = text.index(text.startIndex, offsetBy: lowerStart)
        let end = text.index(text.startIndex, offsetBy: lowerEnd)
        return String(text[start..<end])
    }

    // MARK: - Ordinals, dates, numbers

    private func matchOrdinals(in lowercased: String) -> [EntityMatch] {
        if lowercased.contains("the latest") || lowercased.contains("most recent")
            || lowercased.contains("last one") {
            return [EntityMatch(surface: "the latest", canonical: "latest", confidence: 1.0)]
        }
        for (word, index) in Self.ordinalWords {
            let pattern = "\\b\(word)\\b"
            if lowercased.range(of: pattern, options: .regularExpression) != nil {
                return [EntityMatch(surface: word,
                                    canonical: "\(index)",
                                    confidence: 1.0)]
            }
        }
        return []
    }

    private func matchDates(in lowercased: String) -> [EntityMatch] {
        for phrase in Self.dateWords {
            if lowercased.contains(phrase) {
                return [EntityMatch(surface: phrase,
                                    canonical: phrase,
                                    confidence: 1.0)]
            }
        }
        return []
    }

    private func matchNumbers(in lowercased: String) -> [EntityMatch] {
        let pattern = "\\b\\d+\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = lowercased as NSString
        let matches = regex.matches(in: lowercased,
                                    range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { m in
            let surface = nsText.substring(with: m.range)
            return EntityMatch(surface: surface, canonical: surface, confidence: 1.0)
        }
    }
}
