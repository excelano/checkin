// SessionCoordinator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UIKit
import os

/// Translates `StateMachine` transitions into service side effects and
/// wires the voice loop: speech recognizer transcripts → interpreter →
/// command executor → spoken result via the speaking state.
///
/// The legacy intent-classification / persona / disambiguation / mutation
/// machinery was retired. The coordinator no longer routes voice prompts
/// or builds spoken-response pools — there's exactly one voice path,
/// `transcript → Command → CommandResult → speak`, and unrecognized
/// transcripts get a canonical refusal.
@MainActor
final class SessionCoordinator {
    private let stateMachine: StateMachine
    private let speechService: any SpeechService
    private let ttsService: any TTSService
    private let audioController: AudioSessionController
    private let summaryService: any SummaryService
    private let commandExecutor: CommandExecutor
    private let interpreter: any Interpreter
    private let transitionRouter = TransitionRouter()

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var ttsEventTask: Task<Void, Never>?

    /// In-flight summary fetch, held so a concurrent dispatch awaits the
    /// same fetch rather than racing or duplicating it.
    private var pendingFetch: Task<Void, Never>?

    init(stateMachine: StateMachine,
         speechService: any SpeechService,
         ttsService: any TTSService,
         audioController: AudioSessionController,
         summaryService: any SummaryService,
         commandExecutor: CommandExecutor,
         interpreter: any Interpreter) {
        self.stateMachine = stateMachine
        self.speechService = speechService
        self.ttsService = ttsService
        self.audioController = audioController
        self.summaryService = summaryService
        self.commandExecutor = commandExecutor
        self.interpreter = interpreter
    }

    /// Begin consuming the state machine's transition stream, the speech
    /// service's transcript stream, and the TTS event stream. Idempotent.
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

    // MARK: - Transition handling

    private func handle(_ event: TransitionEvent) async {
        logger.debug("saw: \(String(describing: event.from)) -> \(String(describing: event.to))")
        #if DEBUG
        print("[coordinator] \(event.from) -> \(event.to)")
        #endif

        // Account boundary: a transition into .signedOut drops per-account
        // caches and cancels any in-flight fetch.
        if case .signedOut = event.to {
            summaryService.reset()
            pendingFetch?.cancel()
            pendingFetch = nil
        }

        // Sign-in (cold-boot from .signedOut into .active): kick off an
        // initial summary load so the first turn has data without racing.
        if case .signedOut = event.from, case .active = event.to {
            startSummaryFetch(reason: "boot")
        }

        let effects = transitionRouter.sideEffects(
            from: event.from,
            to: event.to,
            preferredRestState: stateMachine.preferredRestState
        )
        for effect in effects {
            await apply(effect)
        }
    }

    private func apply(_ effect: TransitionRouter.SideEffect) async {
        switch effect {
        case .configureAudio(let phase):
            do {
                try audioController.configure(for: phase)
            } catch {
                logger.error("audio configure(\(String(describing: phase), privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("[coordinator] audio configure failed for \(phase): \(error.localizedDescription)")
                #endif
            }
        case .speak(let text):
            do {
                try ttsService.speak(text)
            } catch {
                logger.error("tts.speak failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("[coordinator] tts.speak failed: \(error.localizedDescription)")
                #endif
                stateMachine.transition(to: .active(.idle))
            }
        case .stopTTSIfSpeaking:
            if ttsService.isSpeaking {
                ttsService.stop()
            }
        case .beginListening:
            await beginListening()
        case .stopListening:
            speechService.stopListening()
        case .cancelListening:
            speechService.cancel()
        case .cancelListeningIfActive:
            if speechService.isListening {
                speechService.cancel()
            }
        case .playEarcon(let earcon):
            audioController.play(earcon)
        }
    }

    // MARK: - Transcript handling

    private func handle(_ update: TranscriptUpdate) async {
        logger.debug("transcript: \(update.text) (final=\(update.isFinal))")
        #if DEBUG
        print("[transcript] \"\(update.text)\" final=\(update.isFinal)")
        #endif

        guard update.isFinal else { return }

        // Auto-finalize: in tap-to-talk the UI tap already moved the
        // machine to .processing before the recognizer stopped, so by
        // the time the final transcript arrives we're already there. In
        // conversation mode the recognizer's natural isFinal fires while
        // the machine is still .listening — drive it forward here.
        if case .active(.listening) = stateMachine.currentState {
            stateMachine.transition(to: .active(.processing))
        }

        let command = interpreter.interpret(update.text)
        if let command {
            await handleCommand(command)
        } else {
            #if DEBUG
            print("[command] unrecognized \"\(update.text)\"")
            #endif
            speakAndReturnToRest("I didn't catch that.")
        }
    }

    private func handleCommand(_ command: Command) async {
        let result = await commandExecutor.execute(command)
        #if DEBUG
        print("[command] result \"\(result.spokenResponse)\"")
        #endif
        speakAndReturnToRest(result.spokenResponse)
    }

    /// Drive the speaking-then-rest tail of a turn. Empty text returns
    /// directly to rest; non-empty text routes through `.speaking` so the
    /// router's TTS plumbing handles playback and the TTS-finished event
    /// completes the transition.
    private func speakAndReturnToRest(_ text: String) {
        guard case .active(.processing) = stateMachine.currentState else { return }
        if text.isEmpty {
            switch stateMachine.preferredRestState {
            case .idle: stateMachine.transition(to: .active(.idle))
            case .listening: stateMachine.transition(to: .active(.listening))
            }
        } else {
            stateMachine.transition(to: .active(.speaking(
                text: text,
                returnTo: stateMachine.preferredRestState)))
        }
    }

    // MARK: - TTS event handling

    /// Drive the state machine out of `.speaking` when the synthesizer
    /// finishes or is cancelled.
    private func handle(tts event: TTSEvent) async {
        logger.debug("tts: \(String(describing: event))")
        #if DEBUG
        print("[tts] \(event)")
        #endif

        switch event {
        case .finished, .cancelled:
            if let next = transitionRouter.nextStateAfterSpeaking(stateMachine.currentState) {
                stateMachine.transition(to: next)
            }
        default:
            break
        }
    }

    // MARK: - Listening

    private func beginListening() async {
        let auth = await speechService.requestAuthorization()
        guard auth == .authorized else {
            logger.error("speech authorization not granted: \(String(describing: auth), privacy: .public)")
            #if DEBUG
            print("[coordinator] auth not granted: \(auth)")
            #endif
            stateMachine.transition(to: .active(.idle))
            return
        }
        do {
            try audioController.configure(for: .listening)
        } catch {
            logger.error("audio configure for listening failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[coordinator] audio configure for listening failed: \(error.localizedDescription)")
            #endif
            stateMachine.transition(to: .active(.idle))
            return
        }
        do {
            try speechService.startListening()
        } catch {
            logger.error("startListening failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[coordinator] startListening failed: \(error.localizedDescription)")
            #endif
            stateMachine.transition(to: .active(.idle))
        }
    }

    // MARK: - Summary fetch lifecycle

    /// Kick off a summary fetch if one isn't already in flight. Repeat
    /// calls coalesce.
    private func startSummaryFetch(reason: String) {
        if pendingFetch != nil { return }
        pendingFetch = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("[summary] fetching reason=\(reason)")
            #endif
            let summary = await self.summaryService.fetchSummary()
            if Task.isCancelled { return }
            self.stateMachine.updateContext {
                $0.summary = summary
                $0.summaryFetchedAt = Date()
            }
            #if DEBUG
            let m = summary.meeting != nil ? "meeting" : "no-meeting"
            print("[summary] fetched: emails=\(summary.emails.count) chats=\(summary.chats.count) \(m) emailErr=\(summary.emailError ?? "nil") chatErr=\(summary.chatError ?? "nil")")
            #endif
            self.pendingFetch = nil
        }
    }
}
