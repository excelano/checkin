// DialogState.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Top-level app state. Sign-in gate plus an active substate for sheet
/// presentation. Voice substates and onboarding are gone; what's left is
/// just the shape the views need to navigate.
enum DialogState: Equatable {
    case signedOut
    case active(ActiveSubstate)
}

enum ActiveSubstate: Equatable {
    case idle
    case helpDisplayed
    case settingsDisplayed
}
