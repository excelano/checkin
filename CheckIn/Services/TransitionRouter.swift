// TransitionRouter.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Pure mapping from a state-machine transition to the list of side effects
/// the coordinator should fire. No state of its own — the same
/// `(from, to, preferredRestState)` triple always produces the same
/// effect list. Voice substates (`.disambiguating`, `.confirming`) are
/// gone, so the routing reduces to: speaking lifecycle, listening
/// lifecycle, audio session category, and earcons.
struct TransitionRouter {

    /// Side effects produced by a transition, in the order the coordinator
    /// should apply them. Order matters: TTS stops before the audio session
    /// swaps; the recognizer cancels before any rest entry; earcons fire
    /// last under the now-correct phase.
    enum SideEffect: Equatable {
        case configureAudio(AudioSessionController.Phase)
        case speak(String)
        case stopTTSIfSpeaking
        case beginListening
        case stopListening
        case cancelListening
        case cancelListeningIfActive
        case playEarcon(Earcon)
    }

    func sideEffects(from: DialogState,
                     to: DialogState,
                     preferredRestState: RestState) -> [SideEffect] {
        var effects: [SideEffect] = []

        // Bucket 1: speaking-state side effects. Synth stops cleanly ahead
        // of any session category swap.
        switch (from, to) {
        case (_, .active(.speaking(let text, _))):
            effects.append(.configureAudio(.speaking))
            effects.append(.speak(text))
        case (.active(.speaking), _):
            effects.append(.stopTTSIfSpeaking)
        default:
            break
        }

        // Bucket 2: recognizer lifecycle.
        switch (from, to) {
        case (.active(.idle), .active(.listening)),
             (.active(.speaking), .active(.listening)):
            effects.append(.beginListening)
        case (.active(.listening), .active(.processing)):
            // User signaled done — finalize so the final transcript fires.
            effects.append(.stopListening)
        case (.active(.listening), _):
            // Any other exit from listening is a cancel — discard the partial.
            effects.append(.cancelListening)
        default:
            break
        }

        // Bucket 3: audio session deactivation on entry to rest states.
        switch to {
        case .active(.idle), .active(.helpDisplayed), .active(.settingsDisplayed):
            effects.append(.configureAudio(.inactive))
        default:
            break
        }

        // Bucket 4: earcons on entry to a new state category.
        if isListening(to) && !isListening(from) {
            effects.append(.playEarcon(.listening))
        }
        if isProcessing(to) && !isProcessing(from) {
            effects.append(.playEarcon(.thinking))
        }

        return effects
    }

    /// Map a finished/cancelled `.speaking` state to the next destination.
    /// Returns nil when the current state isn't `.speaking` (the TTS event
    /// arrived after some other transition already moved the machine).
    func nextStateAfterSpeaking(_ state: DialogState) -> DialogState? {
        guard case .active(.speaking(_, let returnTo)) = state else { return nil }
        switch returnTo {
        case .idle: return .active(.idle)
        case .listening: return .active(.listening)
        }
    }

    private func isListening(_ state: DialogState) -> Bool {
        if case .active(.listening) = state { return true }
        return false
    }

    private func isProcessing(_ state: DialogState) -> Bool {
        if case .active(.processing) = state { return true }
        return false
    }
}
