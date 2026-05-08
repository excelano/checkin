// IntentClassifier.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The intent classification seam per D15. Phase 3 swaps the stub for an
/// `NLEmbedding`-based implementation that scores semantic similarity
/// between the utterance and a fixed catalog of intent prototypes.
protocol IntentClassifier {
    func classify(utterance: String, context: DialogContext) -> ClassifiedIntent
}

/// The supported Day 1 intents per PLAN.md. Phase 2 type-checks the surface;
/// Phase 3 maps `NLEmbedding` similarity scores onto these cases.
enum Intent: String, Equatable {
    case summary
    case filter            // sender or topic filter
    case refresh
    case repeatLast
    case stop
    case help
    case open              // open by name (deep-link)
    case exit              // conversation-mode exit phrase
    case settings
    case yes               // confirmation responses
    case no
    case ordinalSelection  // "the first", "number two"
    case unknown
}

struct ClassifiedIntent: Equatable {
    let intent: Intent
    let confidence: Double
    let entities: [String: String]
}

/// Deterministic stub for tests and SwiftUI previews. Pattern-matches on
/// keyword presence; no fuzzy logic, no fallbacks. Real classification
/// arrives in Phase 3.
struct StubIntentClassifier: IntentClassifier {
    func classify(utterance: String, context: DialogContext) -> ClassifiedIntent {
        let lower = utterance.lowercased()
        let intent: Intent

        if lower.contains("summary") || lower.contains("status")
            || lower.contains("check in") || lower.contains("what's going on") {
            intent = .summary
        } else if lower.contains("from ") || lower.contains("about ") {
            intent = .filter
        } else if lower.contains("refresh") || lower.contains("again")
            || lower.contains("reload") {
            intent = .refresh
        } else if lower.contains("repeat") || lower.contains("say that again") {
            intent = .repeatLast
        } else if lower.contains("stop") || lower.contains("quiet")
            || lower.contains("be quiet") {
            intent = .stop
        } else if lower.contains("help") {
            intent = .help
        } else if lower.contains("open ") || lower.contains("show me ") {
            intent = .open
        } else if lower == "done" || lower == "thanks" || lower == "exit"
            || lower == "thank you" {
            intent = .exit
        } else if lower.contains("settings") {
            intent = .settings
        } else if lower == "yes" || lower == "yeah" || lower == "yep"
            || lower == "confirm" || lower == "do it" {
            intent = .yes
        } else if lower == "no" || lower == "nope" || lower == "cancel"
            || lower == "never mind" {
            intent = .no
        } else if lower.contains("first") || lower.contains("second")
            || lower.contains("third") || lower.contains("number ") {
            intent = .ordinalSelection
        } else {
            intent = .unknown
        }

        return ClassifiedIntent(intent: intent, confidence: 1.0, entities: [:])
    }
}
