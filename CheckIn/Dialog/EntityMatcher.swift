// EntityMatcher.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The entity matching seam per D15. Phase 3 swaps the stub for an
/// `NLTagger`-based implementation primed with `contextualStrings` from the
/// current summary's senders, subjects, and chat topics.
protocol EntityMatcher {
    func match(text: String, domain: EntityDomain, context: DialogContext) -> [EntityMatch]
}

enum EntityDomain: Equatable {
    case person
    case subject
    case date
    case ordinal
    case number
}

struct EntityMatch: Equatable {
    let surface: String
    let canonical: String
    let confidence: Double
}

/// Deterministic stub. Returns no matches; tests that need fixed matches
/// inject their own implementation.
struct StubEntityMatcher: EntityMatcher {
    func match(text: String, domain: EntityDomain, context: DialogContext) -> [EntityMatch] {
        []
    }
}
