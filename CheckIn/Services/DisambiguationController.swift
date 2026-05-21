// DisambiguationController.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Owns the disambiguation flow extracted from `SessionCoordinator`.
///
/// When a `.filter` turn resolves to multiple candidate senders,
/// `SessionCoordinator` constructs the `.speaking(_, .disambiguate(pending))`
/// transition that speaks the prompt. From that point on this controller
/// drives the flow: voice-pick (ordinal or name), touch-pick, retry on a
/// missed match, bail after two misses, and explicit cancel. The
/// controller has no direct view dependency — it transitions the shared
/// `StateMachine`, and `SessionCoordinator` keeps the public surface the
/// view layer calls through (`resumeDisambiguation` / `cancelDisambiguation`).
@MainActor
final class DisambiguationController {
    private let stateMachine: StateMachine
    private let responseGenerator: any ResponseGenerator
    private let entityMatcher: any EntityMatcher
    private let intentExecutor: IntentExecutor
    private let utteranceLog: any UtteranceLog

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "disambig")

    init(stateMachine: StateMachine,
         responseGenerator: any ResponseGenerator,
         entityMatcher: any EntityMatcher,
         intentExecutor: IntentExecutor,
         utteranceLog: any UtteranceLog) {
        self.stateMachine = stateMachine
        self.responseGenerator = responseGenerator
        self.entityMatcher = entityMatcher
        self.intentExecutor = intentExecutor
        self.utteranceLog = utteranceLog
    }

    /// User picked a candidate (touch tap or voice match). Branch on the
    /// suspended intent's origin: filter narrows the summary response;
    /// reply binds the chosen sender's address into an Outlook compose
    /// URL; mutation resolves the sender's latest email and stages a
    /// `.confirming` prompt.
    func resume(with candidate: Candidate) {
        guard case .active(.disambiguating(let suspended, _, _))
                = stateMachine.currentState else { return }

        stateMachine.updateContext {
            $0.disambiguationFailedAttempts = 0
        }
        stateMachine.transition(to: .active(.processing(.thinking)))

        Task { [weak self] in
            guard let self else { return }
            switch suspended.origin {
            case .filter:
                await self.completeFilterTurn(utterance: suspended.utterance,
                                              sender: candidate.entityRef)
            case .reply:
                await self.completeReplyTurn(utterance: suspended.utterance,
                                             sender: candidate.entityRef)
            case .mutation(let kind):
                self.completeMutationTurn(utterance: suspended.utterance,
                                          sender: candidate.entityRef,
                                          kind: kind)
            }
        }
    }

    /// User cancelled disambiguation (touch Cancel button or mic-tap).
    /// Silent return to rest — the absence of speech is the
    /// acknowledgment, mirroring `.stop`.
    func cancel() {
        let rest = dialogState(forRest: stateMachine.preferredRestState)
        stateMachine.transition(to: rest)
        #if DEBUG
        print("[disambig] cancelled")
        #endif
    }

    /// Voice path for a transcript arriving while `.disambiguating`. Tries
    /// cancel terms, then ordinal, then label-substring match. On no match
    /// counts the miss and either re-prompts or bails out.
    func handleUtterance(_ text: String,
                         suspended: SuspendedIntent,
                         candidates: [Candidate],
                         surface: String) async {
        let lower = text.lowercased()

        // Cancel surfaces — silent return to rest. Wider than just .stop
        // anchors so users have natural exit phrasings.
        let cancelTerms = ["never mind", "cancel", "stop", "forget it", "skip it"]
        if cancelTerms.contains(where: { lower.contains($0) }) {
            cancel()
            return
        }

        // Ordinal first ("the first one", "number two").
        let ordinals = entityMatcher.match(text: text,
                                           domain: .ordinal,
                                           context: stateMachine.context)
        if let ord = ordinals.first,
           let index = Int(ord.canonical),
           index >= 1, index <= candidates.count {
            resume(with: candidates[index - 1])
            return
        }

        // Canonical / partial canonical match. Matches if the utterance
        // contains the full label OR any word from the label longer than
        // two characters — catches "Tony Jones" → "jones" and "Smith"
        // alike, but doesn't trip on stopwords.
        if let chosen = candidates.first(where: { cand in
            let labelLower = cand.label.lowercased()
            if lower.contains(labelLower) { return true }
            return labelLower.split(separator: " ").contains {
                $0.count > 2 && lower.contains($0)
            }
        }) {
            resume(with: chosen)
            return
        }

        // No match — count the miss and either retry or bail.
        stateMachine.updateContext { $0.disambiguationFailedAttempts += 1 }
        let misses = stateMachine.context.disambiguationFailedAttempts

        if misses >= 2 {
            let response = SpokenResponse(
                text: ResponseTemplateRegistry.disambiguationExit,
                category: .answer)
            stateMachine.updateContext {
                $0.disambiguationFailedAttempts = 0
            }
            await utteranceLog.record(
                utterance: text,
                classified: ClassifiedIntent(intent: .unknown, confidence: 0.0),
                ranking: [],
                response: response)
            stateMachine.recordTurn(user: text,
                                    system: response.text,
                                    category: response.category)
            #if DEBUG
            print("[disambig] bail after \(misses) misses")
            #endif
            stateMachine.transition(to: .active(.speaking(
                response: response,
                followUp: .rest(stateMachine.preferredRestState))))
            return
        }

        // Retry — speak the retry prompt with a fresh PendingDisambiguation
        // payload so speaking-finish lands back in .disambiguating.
        let pending = PendingDisambiguation(suspendedIntent: suspended,
                                            surface: surface,
                                            candidates: candidates)
        let prompt = ResponseTemplateRegistry.disambiguationRetry(
            heardSurface: surface, candidates: candidates)
        let response = SpokenResponse(text: prompt, category: .disambiguation)
        await utteranceLog.record(
            utterance: text,
            classified: ClassifiedIntent(intent: .unknown, confidence: 0.0),
            ranking: [],
            response: response)
        stateMachine.recordTurn(user: text,
                                system: response.text,
                                category: response.category)
        #if DEBUG
        print("[disambig] retry (miss \(misses))")
        #endif
        stateMachine.transition(to: .active(.speaking(
            response: response,
            followUp: .disambiguate(pending))))
    }

    private func completeFilterTurn(utterance: String, sender: String) async {
        let classified = ClassifiedIntent(intent: .filter, confidence: 1.0)
        let baseResponse = responseGenerator.generate(
            for: classified,
            utterance: utterance,
            resolvedSender: sender,
            context: stateMachine.context
        )
        let returnTo = stateMachine.preferredRestState

        await utteranceLog.record(
            utterance: utterance,
            classified: classified,
            ranking: [],
            response: baseResponse
        )
        stateMachine.recordTurn(
            user: utterance,
            system: baseResponse.text,
            category: baseResponse.category
        )

        #if DEBUG
        print("[disambig] resumed filter sender=\(sender)")
        print("[response] \"\(baseResponse.text)\" category=\(baseResponse.category)")
        #endif

        if case .active(.processing) = stateMachine.currentState {
            if baseResponse.text.isEmpty {
                stateMachine.transition(to: dialogState(forRest: returnTo))
            } else {
                stateMachine.transition(to: .active(.speaking(
                    response: baseResponse,
                    followUp: .rest(returnTo))))
            }
        }
    }

    private func completeReplyTurn(utterance: String, sender: String) async {
        let classified = ClassifiedIntent(intent: .reply, confidence: 1.0)
        let (response, returnTo) = await intentExecutor.resolveReply(
            utterance: utterance,
            preferredSender: sender,
            context: stateMachine.context,
            defaultRest: stateMachine.preferredRestState
        )

        await utteranceLog.record(
            utterance: utterance,
            classified: classified,
            ranking: [],
            response: response
        )
        stateMachine.recordTurn(
            user: utterance,
            system: response.text,
            category: response.category
        )

        #if DEBUG
        print("[disambig] resumed reply sender=\(sender)")
        print("[response] \"\(response.text)\" category=\(response.category)")
        #endif

        if case .active(.processing) = stateMachine.currentState {
            if response.text.isEmpty {
                stateMachine.transition(to: dialogState(forRest: returnTo))
            } else {
                stateMachine.transition(to: .active(.speaking(
                    response: response,
                    followUp: .rest(returnTo))))
            }
        }
    }

    /// Resume path for mutation disambig. Builds a `PendingMutation`
    /// against the user's picked sender and stages the confirmation
    /// prompt. No Graph write fires here — that happens later when the
    /// user accepts via the `.confirming` panel.
    private func completeMutationTurn(utterance: String,
                                      sender: String,
                                      kind: MutationKind) {
        let intentForLog: Intent
        switch kind {
        case .markRead, .bulkMarkRead: intentForLog = .markRead
        case .flag, .bulkFlag:         intentForLog = .flag
        case .delete, .bulkDelete:     intentForLog = .delete
        }
        let classified = ClassifiedIntent(intent: intentForLog, confidence: 1.0)
        let outcome = intentExecutor.handleMutation(
            kind: kind,
            utterance: utterance,
            context: stateMachine.context,
            preferredSender: sender
        )

        let response: SpokenResponse
        let followUp: SpeakingFollowUp
        if let pending = outcome.pending {
            let promptText = ResponseTemplateRegistry.confirmationPrompt(
                pending.description)
            response = SpokenResponse(text: promptText, category: .confirmation)
            followUp = .confirm(pending)
        } else {
            response = outcome.refusal
                ?? SpokenResponse(text: "", category: .answer)
            followUp = .rest(stateMachine.preferredRestState)
        }

        Task { [weak self] in
            guard let self else { return }
            await self.utteranceLog.record(
                utterance: utterance,
                classified: classified,
                ranking: [],
                response: response)
        }
        stateMachine.recordTurn(
            user: utterance,
            system: response.text,
            category: response.category)

        #if DEBUG
        if let p = outcome.pending {
            print("[disambig] resumed mutation kind=\(kind) targets=\(p.targets) sender=\(sender)")
        } else {
            print("[disambig] resumed mutation refused kind=\(kind) sender=\(sender)")
        }
        #endif

        if case .active(.processing) = stateMachine.currentState {
            if response.text.isEmpty {
                stateMachine.transition(to: dialogState(forRest: stateMachine.preferredRestState))
            } else {
                stateMachine.transition(to: .active(.speaking(
                    response: response,
                    followUp: followUp)))
            }
        }
    }

    private func dialogState(forRest rest: RestState) -> DialogState {
        switch rest {
        case .idle: return .active(.idle)
        case .listening: return .active(.listening)
        }
    }
}
