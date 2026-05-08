// NLEmbeddingIntentClassifier.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import NaturalLanguage
import os.log

/// Day 1 intent classifier per D14 and D15. Uses
/// `NLEmbedding.sentenceEmbedding(for:)` to score the utterance against
/// every anchor in `IntentAnchors`. The closest anchor wins; the owning
/// intent is the classification.
///
/// The classifier emits `outOfScope` (D18) and `inScopeUnsupported(...)`
/// (D19) directly because those categories have their own anchor pools.
/// When the best in-scope anchor sits beyond the confidence floor, the
/// dialog demotes to `outOfScope` rather than guessing. When even the
/// closest anchor sits beyond the unknown floor, the dialog returns
/// `unknown` and the state machine re-prompts.
///
/// Distances are cosine by default and roughly fall in `[0, 2]`. Concrete
/// floors are tuned against the test corpus in `CAPABILITIES.md`; tweak
/// once real recognizer transcripts are flowing in Phase 5.
final class NLEmbeddingIntentClassifier: IntentClassifier {

    private let embedding: NLEmbedding?
    private let confidenceFloor: Double
    private let unknownFloor: Double
    private let alternativeGap: Double
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "intent")

    init(confidenceFloor: Double = 0.85,
         unknownFloor: Double = 1.05,
         alternativeGap: Double = 0.10) {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
        self.confidenceFloor = confidenceFloor
        self.unknownFloor = unknownFloor
        self.alternativeGap = alternativeGap
        if embedding == nil {
            logger.error("Sentence embedding unavailable for English; classifier will refuse all utterances as outOfScope")
        }
    }

    func classify(utterance: String, context: DialogContext) -> ClassifiedIntent {
        let trimmed = utterance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else {
            return ClassifiedIntent(intent: .unknown, confidence: 0)
        }
        guard let embedding else {
            return ClassifiedIntent(intent: .outOfScope, confidence: 0)
        }

        // For each anchor, compute distance from the utterance. Group by
        // intent and keep the minimum distance per group: the strongest
        // anchor for that intent.
        var bestPerIntent: [Intent: Double] = [:]
        for (intent, anchor) in IntentAnchors.flattened {
            let distance = embedding.distance(between: trimmed, and: anchor)
            if let existing = bestPerIntent[intent], existing <= distance { continue }
            bestPerIntent[intent] = distance
        }

        let ranked = bestPerIntent.sorted { $0.value < $1.value }
        guard let best = ranked.first else {
            return ClassifiedIntent(intent: .unknown, confidence: 0)
        }

        #if DEBUG
        logger.debug("intent='\(String(describing: best.key))' distance=\(best.value, format: .fixed(precision: 3)) utterance='\(trimmed, privacy: .public)'")
        #endif

        let intent: Intent
        if best.value > unknownFloor {
            intent = .unknown
        } else if best.value > confidenceFloor && !isScopeAnchor(best.key) {
            intent = .outOfScope
        } else {
            intent = best.key
        }

        let alternatives = ranked.dropFirst()
            .prefix(3)
            .filter { $0.value - best.value < alternativeGap }
            .map { $0.key }

        let confidence = max(0.0, min(1.0, 1.0 - best.value))
        return ClassifiedIntent(intent: intent,
                                confidence: confidence,
                                alternatives: Array(alternatives))
    }

    /// `outOfScope` and `inScopeUnsupported(...)` are real classifications,
    /// not failure modes. Even at high distance they should be surfaced as
    /// themselves rather than demoted, so the dialog responds with the
    /// correct refusal or redirect register.
    private func isScopeAnchor(_ intent: Intent) -> Bool {
        switch intent {
        case .outOfScope, .inScopeUnsupported:
            return true
        default:
            return false
        }
    }
}
