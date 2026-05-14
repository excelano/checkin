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

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?

    init(stateMachine: StateMachine, speechService: any SpeechService) {
        self.stateMachine = stateMachine
        self.speechService = speechService
    }

    /// Begin consuming the state machine's transition stream and the
    /// speech service's transcript stream. Idempotent so SwiftUI's `.task`
    /// firing twice during view reattachment doesn't spawn duplicate consumers.
    func start() {
        guard transitionTask == nil else { return }
        let transitions = stateMachine.transitions
        let transcripts = speechService.transcripts

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
    }

    func stop() {
        transitionTask?.cancel()
        transcriptTask?.cancel()
        transitionTask = nil
        transcriptTask = nil
    }

    private func handle(_ event: TransitionEvent) async {
        logger.debug("saw: \(String(describing: event.from)) -> \(String(describing: event.to))")
        // Phase 5 scaffold: mirror to stdout so `devicectl process launch
        // --console` shows transitions over SSH. Remove once we have a
        // device-side `os_log` streaming path that survives SSH.
        print("[coordinator] \(event.from) -> \(event.to)")

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
    }

    private func handle(_ update: TranscriptUpdate) async {
        logger.debug("transcript: \(update.text, privacy: .public) (final=\(update.isFinal))")
        print("[transcript] \"\(update.text)\" final=\(update.isFinal)")

        if update.isFinal {
            stateMachine.updateContext { ctx in
                ctx.lastUtterance = update.text
            }
            // Phase 5 mic-only: route nowhere yet. Drop back to idle so the
            // UI doesn't strand the user on the processing spinner. Phase 6
            // wires intent classification + response generation on entry to
            // processing, which will own the next transition.
            if case .active(.processing) = stateMachine.currentState {
                stateMachine.transition(to: .active(.idle))
            }
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
