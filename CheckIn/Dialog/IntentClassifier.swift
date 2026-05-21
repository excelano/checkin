// IntentClassifier.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The intent classification seam. `NLEmbeddingIntentClassifier`
/// is the real implementation: it scores semantic similarity between the
/// utterance and a fixed catalog of intent prototypes.
protocol IntentClassifier {
    func classify(utterance: String, context: DialogContext) -> ClassifiedIntent
}

/// The launch intent surface, plus the two scope categories
/// (out-of-scope, in-scope-unsupported with sub-kinds) the
/// classifier emits when the utterance falls outside what voice can do.
enum Intent: Hashable {
    case summary
    case filter            // sender or topic filter
    case refresh
    case repeatLast
    case stop
    case help
    case open              // open by name (deep-link)
    case reply             // reply to a known sender (deep-link to Outlook compose)
    case join              // join the next meeting via onlineMeeting.joinUrl
    case timeQuery         // "when's my next meeting", "how long until"
    case exit              // conversation-mode exit phrase
    case settings
    case yes               // confirmation responses
    case no
    case ordinalSelection  // "the first", "number two"

    // Mutations — every one goes through the `.confirming` gate before
    // any write reaches Graph.
    case markRead
    case flag
    case delete

    /// In-scope subject (calendar, email, chats) but the requested action
    /// isn't a launch voice capability. Sub-kind selects the redirect pool.
    case inScopeUnsupported(UnsupportedKind)

    /// Outside the bounded scope entirely. Out-of-scope refusal pool applies.
    case outOfScope

    /// Confidence below the floor and no scope signal. Treated as a
    /// recoverable parse miss; the dialog re-prompts rather than refuses.
    case unknown
}

/// In-scope-unsupported sub-categories. Each maps to its own redirect pool because the
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

    /// Ranked alternatives below the top, surfaced for disambiguation
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

/// One row of a full classifier ranking — every intent the classifier
/// considered, paired with its best (lowest) anchor distance for that
/// intent. Used by the utterance log to capture the full verdict for
/// tuning, not just the chosen winner.
struct IntentRanking: Equatable {
    let intent: Intent
    let distance: Double
}

/// Diagnostic capability some classifiers offer alongside the primary
/// classify() API. Embedding-based classifiers expose the full ranked
/// candidate list so the tuning log can record near-misses; stub
/// classifiers don't bother.
protocol RankedIntentClassifier: IntentClassifier {
    func rank(utterance: String, context: DialogContext) -> [IntentRanking]
}

#if DEBUG
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
#endif
