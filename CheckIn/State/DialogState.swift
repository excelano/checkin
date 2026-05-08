// DialogState.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Top-level application state. The state machine spine per D1 and D33.
/// Mirrors the hierarchy in STATES.md.
enum DialogState: Equatable {
    case signedOut
    case onboarding(OnboardingSubstate)
    case active(ActiveSubstate)
}

/// First-run flow per D31.
enum OnboardingSubstate: Equatable {
    case welcome
    case permissions
    case mode
    case firstQuery
}

/// Operational substates the user spends nearly all their time in.
/// Several substates carry payload via associated values: the suspended
/// intent during disambiguation, the pending action during confirmation,
/// the rest state to return to from help and settings sheets.
enum ActiveSubstate: Equatable {
    case idle
    case listening
    case processing(ProcessingPhase)
    case speaking(response: SpokenResponse, returnTo: RestState)
    case disambiguating(suspendedIntent: SuspendedIntent, candidates: [Candidate])
    case confirming(pendingAction: PendingAction)
    case helpDisplayed(returnTo: RestState)
    case settingsDisplayed(returnTo: RestState)
}

/// Latency-driven substates inside `processing` per D21.
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
//
// These are intentionally light for Phase 2. Phase 3 enriches them as the
// real intent classifier, entity matcher, and response template registry
// land behind the protocols in `Dialog/`.

/// A user intent suspended while the system disambiguates an ambiguous
/// reference per D7. Once the user picks a candidate, the suspended intent
/// resumes with the chosen entity substituted in.
struct SuspendedIntent: Equatable {
    let utterance: String
    let intent: String
}

/// A candidate offered during disambiguation. `label` is what the user
/// hears; `entityRef` is an opaque reference Phase 3 binds to a model.
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

/// A destructive or modifying action awaiting yes-or-no confirmation per D28.
struct PendingAction: Equatable {
    let description: String
    let kind: ActionKind
    let target: String
}

/// The destructive or modifying actions CheckIn supports. Day 1 has none;
/// Day 2 adds `markEmailRead` and `flagEmail`; Day 3 adds the soft-delete
/// and bulk operations.
enum ActionKind: Equatable {
    case markEmailRead
    case flagEmail
    case softDeleteEmail
    case markAllEmailsRead
    case flagAllEmails
    case softDeleteAllEmails
}

/// A response packaged for TTS playback and on-screen captioning.
/// `category` lets the speaking layer pick the right voice tempo, the
/// dialog layer suppress repeats, and the persona layer apply the right tone.
struct SpokenResponse: Equatable {
    let text: String
    let category: ResponseCategory
}

/// Response categories shape both presentation (caption styling, voice
/// pacing) and the anti-repeat ledger in `DialogContext`. Refusals (D18)
/// and redirects (D19) draw from rotating pools to avoid sounding canned.
enum ResponseCategory: Equatable {
    case summary
    case answer
    case refusal
    case redirect
    case disambiguation
    case confirmation
    case error
    case help
    case latencyReassurance
}
