// ResponseGenerator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The response generation seam. `PersonaResponseGenerator` is the
/// real implementation, drawing from rotating refusal and redirect
/// pools with the latency reassurance pool attached to
/// `processing` substate transitions.
protocol ResponseGenerator {
    func generate(for intent: ClassifiedIntent,
                  utterance: String,
                  resolvedSender: String?,
                  context: DialogContext) -> SpokenResponse
}

#if DEBUG
/// Deterministic stub for tests and previews. Fixed strings, no rotation.
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
        case .reply:
            return SpokenResponse(text: "Replying, stub.", category: .answer)
        case .join:
            return SpokenResponse(text: "Joining, stub.", category: .answer)
        case .timeQuery:
            return SpokenResponse(text: "Time query, stub.", category: .answer)
        case .exit:
            return SpokenResponse(text: "", category: .answer)
        case .settings:
            return SpokenResponse(text: "", category: .answer)
        case .yes:
            return SpokenResponse(text: "Confirmed, stub.", category: .answer)
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
#endif
