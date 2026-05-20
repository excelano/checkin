// DialogState.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Top-level application state. The state machine spine.
/// Mirrors the hierarchy in STATES.md.
enum DialogState: Equatable {
    case signedOut
    case onboarding(OnboardingSubstate)
    case active(ActiveSubstate)
}

/// First-run flow.
enum OnboardingSubstate: Equatable {
    case welcome
    case permissions
    case mode
    case firstQuery
}

/// Operational substates the user spends nearly all their time in.
/// Several substates carry payload via associated values: the suspended
/// intent during disambiguation, the rest state to return to from help
/// and settings sheets.
enum ActiveSubstate: Equatable {
    case idle
    case listening
    case processing(ProcessingPhase)
    case speaking(response: SpokenResponse, returnTo: RestState)
    case disambiguating(suspendedIntent: SuspendedIntent, candidates: [Candidate])
    case helpDisplayed(returnTo: RestState)
    case settingsDisplayed(returnTo: RestState)
}

/// Latency-driven substates inside `processing`.
/// `thinking` is the silent default; the longer-latency phases play
/// reassurance and status messages from the latency response pool.
enum ProcessingPhase: Equatable {
    case thinking            // < 1.5 s, silent except thinking earcon
    case speakingPlaceholder // 1.5–5 s, short reassurance
    case speakingEscalation  // > 5 s, longer status update
}

/// The two valid rest states. Tap-to-talk rests in `idle`; conversation
/// mode rests in `listening`. Help and Settings sheets, and any speaking
/// turn, must remember which to return to.
enum RestState: Equatable {
    case idle
    case listening
}

// MARK: - Payload types

/// A user intent suspended while the system disambiguates an ambiguous
/// reference. Once the user picks a candidate, the suspended intent
/// resumes with the chosen entity substituted in.
struct SuspendedIntent: Equatable {
    let utterance: String
    let intent: String
}

/// A candidate offered during disambiguation. `label` is what the user
/// hears; `entityRef` is an opaque reference to the underlying model.
struct Candidate: Identifiable, Equatable {
    let id: UUID
    let label: String
    let entityRef: String

    init(id: UUID = UUID(), label: String, entityRef: String) {
        self.id = id
        self.label = label
        self.entityRef = entityRef
    }
}

/// Transient bundle the coordinator stashes on `DialogContext` while a
/// disambiguation prompt is being spoken — the speaking-finish path reads
/// it to know whether to land in `.disambiguating` instead of rest.
struct PendingDisambiguation: Equatable {
    let suspendedIntent: SuspendedIntent
    let surface: String
    let candidates: [Candidate]
}

/// A response packaged for TTS playback and on-screen captioning.
/// `category` lets the speaking layer pick the right voice tempo, the
/// dialog layer suppress repeats, and the persona layer apply the right tone.
struct SpokenResponse: Equatable {
    let text: String
    let category: ResponseCategory
}

/// Response categories shape both presentation (caption styling, voice
/// pacing) and the anti-repeat ledger in `DialogContext`. Refusals
/// and redirects draw from rotating pools to avoid sounding canned.
enum ResponseCategory: Equatable {
    case summary
    case answer
    case refusal
    case redirect
    case disambiguation
    case error
    case help
    case latencyReassurance
}
