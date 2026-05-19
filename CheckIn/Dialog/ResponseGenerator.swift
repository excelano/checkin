// ResponseGenerator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The response generation seam per D15. Phase 3 swaps the stub for the
/// real persona-shaped template registry that draws from rotating refusal
/// (D18) and redirect (D19) pools, with the latency reassurance pool (D21)
/// attached to `processing` substate transitions.
protocol ResponseGenerator {
    func generate(for intent: ClassifiedIntent,
                  utterance: String,
                  resolvedSender: String?,
                  context: DialogContext) -> SpokenResponse
}

/// Deterministic stub for tests and previews. Fixed strings, no rotation.
/// PERSONA.md-shaped output lands in Phase 3.
struct StubResponseGenerator: ResponseGenerator {
    func generate(for intent: ClassifiedIntent,
                  utterance: String,
                  resolvedSender: String?,
                  context: DialogContext) -> SpokenResponse {
        switch intent.intent {
        case .summary:
            return SpokenResponse(text: "Here is your stub summary.", category: .summary)
        case .filter:
            return SpokenResponse(text: "Filtering, stub.", category: .answer)
        case .refresh:
            return SpokenResponse(text: "Refreshing.", category: .answer)
        case .repeatLast:
            return SpokenResponse(text: context.lastSystemResponse ?? "", category: .answer)
        case .stop:
            return SpokenResponse(text: "", category: .answer)
        case .help:
            return SpokenResponse(text: "Stub help.", category: .help)
        case .open:
            return SpokenResponse(text: "Opening, stub.", category: .answer)
        case .exit:
            return SpokenResponse(text: "", category: .answer)
        case .settings:
            return SpokenResponse(text: "", category: .answer)
        case .yes:
            return SpokenResponse(text: "Confirmed, stub.", category: .confirmation)
        case .no:
            return SpokenResponse(text: "Cancelled, stub.", category: .answer)
        case .ordinalSelection:
            return SpokenResponse(text: "Selected, stub.", category: .answer)
        case .inScopeUnsupported:
            return SpokenResponse(text: "Tap to open in Outlook.", category: .redirect)
        case .outOfScope:
            return SpokenResponse(text: "Outside my range.", category: .refusal)
        case .unknown:
            return SpokenResponse(text: "I missed that. Try again?", category: .error)
        }
    }
}
