// DialogState.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Top-level application state. The state machine spine.
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

/// Operational substates. Voice prompt machinery (`.disambiguating`,
/// `.confirming`) is gone — clarification and confirmation are GUI
/// concerns driven by `@State`, not protocol states. `processing` is a
/// single phase (no latency-tier substates) since the persona response
/// pool that consumed them was retired.
enum ActiveSubstate: Equatable {
    case idle
    case listening
    case processing
    case speaking(text: String, returnTo: RestState)
    case helpDisplayed(returnTo: RestState)
    case settingsDisplayed(returnTo: RestState)
}

/// The two valid rest states. Tap-to-talk rests in `idle`; conversation
/// mode rests in `listening`. Help and Settings sheets, and any speaking
/// turn, remember which to return to.
enum RestState: Equatable {
    case idle
    case listening
}
