// NLTaggerEntityMatcher.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import NaturalLanguage

/// Day 1 entity matcher per D15. Uses `NLTagger` with `.nameType` for
/// personal names, simple word-list rules for ordinals and relative dates,
/// and a regex for raw numbers. Person matches are reconciled against the
/// senders and chat partners in the current `DialogContext.summary`, so
/// "Tony" canonicalizes to "Tony Smith" when only one Tony is in view, or
/// returns both candidates ranked equally when two Tonys are.
///
/// `contextualStrings` priming on the speech recognizer side (per D9 and
/// D10) handles the upstream half: the recognizer is more likely to spell
/// "Hernandez" correctly when a known contact is on the call sheet. This
/// matcher handles the downstream half: matching the recognized tokens to
/// concrete entities the dialog can act on.
struct NLTaggerEntityMatcher: EntityMatcher {

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
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var surfaceForms: [String] = []

        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                surfaceForms.append(String(text[tokenRange]))
            }
            return true
        }

        // The NLTagger may miss casual single first-name references in
        // lowercased speech ("any from tony"). Fall back to scanning the
        // current contact list out of the summary.
        let knownPeople = peopleInScope(context: context)
        var candidates = matchAgainstKnown(surfaceForms: surfaceForms, knownPeople: knownPeople)

        if candidates.isEmpty {
            // Last-ditch: match a known first name appearing as a bare
            // token. Avoids missing utterances NLTagger ranks below the
            // tagging threshold.
            for person in knownPeople {
                let firstName = person.split(separator: " ").first.map(String.init) ?? person
                if !firstName.isEmpty,
                   lowercased.range(of: "\\b\(firstName.lowercased())\\b",
                                    options: .regularExpression) != nil {
                    candidates.append(EntityMatch(surface: firstName,
                                                  canonical: person,
                                                  confidence: 0.7))
                }
            }
        }

        return candidates
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

    /// Reconcile NLTagger surface forms against known people. A first-name
    /// match that resolves to exactly one person is high-confidence; one
    /// that resolves to two or more drops to ambiguous and forces the
    /// dialog into D7 disambiguation.
    private func matchAgainstKnown(surfaceForms: [String],
                                   knownPeople: [String]) -> [EntityMatch] {
        guard !surfaceForms.isEmpty, !knownPeople.isEmpty else { return [] }
        var matches: [EntityMatch] = []
        for surface in surfaceForms {
            let lower = surface.lowercased()
            let resolved = knownPeople.filter { person in
                let parts = person.lowercased().split(separator: " ").map(String.init)
                return parts.contains(lower) || person.lowercased() == lower
            }
            if resolved.count == 1 {
                matches.append(EntityMatch(surface: surface,
                                           canonical: resolved[0],
                                           confidence: 0.95))
            } else if resolved.count > 1 {
                for person in resolved {
                    matches.append(EntityMatch(surface: surface,
                                               canonical: person,
                                               confidence: 0.6))
                }
            } else {
                matches.append(EntityMatch(surface: surface,
                                           canonical: surface,
                                           confidence: 0.5))
            }
        }
        return matches
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
