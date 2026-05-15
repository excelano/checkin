// SessionCoordinator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Translates `StateMachine` transitions into service side effects. The
/// state machine stays free of service dependencies; the coordinator owns
/// the consequence side: start the recognizer on entry to listening, stop
/// the synthesizer on exit from speaking, fetch the summary on entry to
/// active, and so on.
///
/// Phase 5 mic-only slice: the coordinator logs every transition and
/// (in a later slice) drives `SpeechService.startListening` / `cancel`.
/// Phase 6 onward adds TTS, GraphClient, and intent routing dispatch.
@MainActor
final class SessionCoordinator {
    private let stateMachine: StateMachine
    private let speechService: any SpeechService
    private let ttsService: any TTSService
    private let intentClassifier: any IntentClassifier
    private let rankedClassifier: (any RankedIntentClassifier)?
    private let responseGenerator: any ResponseGenerator
    private let utteranceLog: any UtteranceLog

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var ttsEventTask: Task<Void, Never>?

    init(stateMachine: StateMachine,
         speechService: any SpeechService,
         ttsService: any TTSService,
         intentClassifier: any IntentClassifier,
         responseGenerator: any ResponseGenerator,
         utteranceLog: any UtteranceLog) {
        self.stateMachine = stateMachine
        self.speechService = speechService
        self.ttsService = ttsService
        self.intentClassifier = intentClassifier
        self.rankedClassifier = intentClassifier as? RankedIntentClassifier
        self.responseGenerator = responseGenerator
        self.utteranceLog = utteranceLog
    }

    /// Begin consuming the state machine's transition stream, the
    /// speech service's transcript stream, and the TTS event stream.
    /// Idempotent so SwiftUI's `.task` firing twice during view
    /// reattachment doesn't spawn duplicate consumers.
    func start() {
        guard transitionTask == nil else { return }
        let transitions = stateMachine.transitions
        let transcripts = speechService.transcripts
        let ttsEvents = ttsService.events

        transitionTask = Task { [weak self] in
            for await event in transitions {
                guard let self else { break }
                await self.handle(event)
            }
        }

        transcriptTask = Task { [weak self] in
            for await update in transcripts {
                guard let self else { break }
                await self.handle(update)
            }
        }

        ttsEventTask = Task { [weak self] in
            for await event in ttsEvents {
                guard let self else { break }
                await self.handle(tts: event)
            }
        }
    }

    func stop() {
        transitionTask?.cancel()
        transcriptTask?.cancel()
        ttsEventTask?.cancel()
        transitionTask = nil
        transcriptTask = nil
        ttsEventTask = nil
    }

    private func handle(_ event: TransitionEvent) async {
        logger.debug("saw: \(String(describing: event.from)) -> \(String(describing: event.to))")
        #if DEBUG
        // Mirror to stdout so `devicectl process launch --console` shows
        // transitions over SSH. Debug-only so Release stays clean.
        print("[coordinator] \(event.from) -> \(event.to)")
        #endif

        switch (event.from, event.to) {
        case (.active(.idle), .active(.listening)),
             (.active(.speaking), .active(.listening)):
            await beginListening()
        case (.active(.listening), .active(.processing)):
            // User signaled "I'm done speaking." Finalize the recognizer;
            // the final transcript will arrive shortly via the transcripts
            // stream and update DialogContext.lastUtterance.
            speechService.stopListening()
        case (.active(.listening), _):
            // Any other exit from listening (back to idle, app backgrounded,
            // error path) is a cancel — discard the partial transcript.
            speechService.cancel()
        default:
            break
        }

        // Speaking-state side effects are independent of the listening
        // handling above. Entering speaking starts the synthesizer; leaving
        // speaking for any reason cancels it as resource hygiene. D8 barge-in
        // (auto-cut when VAD detects user speech mid-utterance) lands later.
        switch (event.from, event.to) {
        case (_, .active(.speaking(let response, _))):
            do {
                try ttsService.speak(response.text)
            } catch {
                logger.error("tts.speak failed: \(error.localizedDescription, privacy: .public)")
                print("[coordinator] tts.speak failed: \(error.localizedDescription)")
                stateMachine.transition(to: .active(.idle))
            }
        case (.active(.speaking), _):
            if ttsService.isSpeaking {
                ttsService.stop()
            }
        default:
            break
        }
    }

    private func handle(_ update: TranscriptUpdate) async {
        logger.debug("transcript: \(update.text, privacy: .public) (final=\(update.isFinal))")
        #if DEBUG
        print("[transcript] \"\(update.text)\" final=\(update.isFinal)")
        #endif

        if update.isFinal {
            let context = stateMachine.context
            let classified = intentClassifier.classify(
                utterance: update.text,
                context: context
            )
            let ranking = rankedClassifier?.rank(utterance: update.text,
                                                 context: context) ?? []
            let response = responseGenerator.generate(
                for: classified,
                context: context
            )

            await utteranceLog.record(
                utterance: update.text,
                classified: classified,
                ranking: ranking,
                response: response
            )

            stateMachine.recordTurn(
                user: update.text,
                system: response.text,
                category: response.category
            )

            logger.info("intent: \(String(describing: classified.intent), privacy: .public) confidence=\(classified.confidence)")
            #if DEBUG
            print("[intent] \(classified.intent) confidence=\(classified.confidence)")
            print("[response] \"\(response.text)\" category=\(response.category)")
            #endif

            if case .active(.processing) = stateMachine.currentState {
                let returnTo = stateMachine.preferredRestState
                stateMachine.transition(
                    to: .active(.speaking(response: response, returnTo: returnTo))
                )
            }
        }
    }

    /// Drive the state machine out of `.speaking` when the synthesizer
    /// finishes or is cancelled. The `returnTo` carried in the speaking
    /// payload picks tap-to-talk's idle or conversation mode's listening.
    private func handle(tts event: TTSEvent) async {
        logger.debug("tts: \(String(describing: event))")
        #if DEBUG
        print("[tts] \(event)")
        #endif

        switch event {
        case .finished, .cancelled:
            if case .active(.speaking(_, let returnTo)) = stateMachine.currentState {
                let next: DialogState = (returnTo == .listening)
                    ? .active(.listening)
                    : .active(.idle)
                stateMachine.transition(to: next)
            }
        default:
            break
        }
    }

    private func beginListening() async {
        let auth = await speechService.requestAuthorization()
        guard auth == .authorized else {
            logger.error("speech authorization not granted: \(String(describing: auth), privacy: .public)")
            print("[coordinator] auth not granted: \(auth)")
            stateMachine.transition(to: .active(.idle))
            return
        }
        do {
            try speechService.startListening(contextualStrings: [])
        } catch {
            logger.error("startListening failed: \(error.localizedDescription, privacy: .public)")
            print("[coordinator] startListening failed: \(error.localizedDescription)")
            stateMachine.transition(to: .active(.idle))
        }
    }
}
