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

/// The Day 1 intent surface per PLAN.md, plus the two scope categories
/// (D18 out-of-scope, D19 in-scope-unsupported with sub-kinds) the
/// classifier emits when the utterance falls outside what voice can do.
///
/// Phase 3 maps `NLEmbedding` similarity scores onto these cases.
enum Intent: Hashable {
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

    /// In-scope subject (calendar, email, chats) but the requested action
    /// isn't a Day 1 voice capability. Sub-kind selects the redirect pool.
    case inScopeUnsupported(UnsupportedKind)

    /// Outside the bounded scope entirely. D18 refusal pool applies.
    case outOfScope

    /// Confidence below the floor and no scope signal. Treated as a
    /// recoverable parse miss; the dialog re-prompts rather than refuses.
    case unknown
}

/// The D19 sub-categories. Each maps to its own redirect pool because the
/// touch-path guidance differs ("tap to open in Outlook" vs "compose in
/// Outlook" vs "browse in Outlook").
enum UnsupportedKind: Hashable {
    case readContent       // "what does it say", "read me Tony's email"
    case summarizeContent  // "summarize Tony's email", "what's in it"
    case analyzeContent    // "is this important", "what's it about"
    case voiceReply        // "reply to Tony", "send Tony a message"
    case listBrowse        // "what else is there", "show me all of them"
}

struct ClassifiedIntent: Equatable {
    let intent: Intent
    let confidence: Double
    let entities: [String: String]

    /// Ranked alternatives below the top, surfaced for D7 disambiguation
    /// when the score gap between top-1 and top-2 is small.
    let alternatives: [Intent]

    init(intent: Intent,
         confidence: Double,
         entities: [String: String] = [:],
         alternatives: [Intent] = []) {
        self.intent = intent
        self.confidence = confidence
        self.entities = entities
        self.alternatives = alternatives
    }
}

/// Deterministic stub for tests and SwiftUI previews. Pattern-matches on
/// keyword presence; no fuzzy logic, no fallbacks. The real classifier
/// is `NLEmbeddingIntentClassifier`.
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

        return ClassifiedIntent(intent: intent, confidence: 1.0)
    }
}
