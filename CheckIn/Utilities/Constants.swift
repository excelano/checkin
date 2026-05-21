// Constants.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum Constants {
    // Replace with your Application (client) ID from Azure Portal
    static let clientID = "0ce3820d-db53-4b2e-9621-6c4ccc086d5a"

    static let authority = "https://login.microsoftonline.com/common"
    static let redirectURI = "msauth.com.excelano.checkin://auth"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    // Note: MSAL for iOS automatically requests openid, profile, and offline_access.
    // Do not include them here or MSAL will throw an error.
    static let baseScopes = [
        "User.Read",
        "Mail.Read",
        "Calendars.Read"
    ]

    static let teamsScopes = [
        "Chat.Read"
    ]

    /// Whether the Teams pending-chat surface is part of the summary. Single
    /// source of truth for sign-in scopes and the Graph fetch in
    /// `GraphSummaryService`. Self-host override is configured elsewhere.
    static let teamsEnabled: Bool = true

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }
}

/// Single source of truth for `@AppStorage` / `UserDefaults` key names. The
/// string values are wire-stable — renaming a case is a schema migration,
/// not a rename refactor, because existing installs key off the value.
enum AppStorageKey {
    static let listeningMode = "listeningMode"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let voiceIdentifier = "voiceIdentifier"
    static let speechRate = "speechRate"
    static let verbosityFull = "verbosityFull"
    static let customClientID = "customClientID"
    static let customAuthority = "customAuthority"
    /// Minutes between automatic summary refreshes. 0 means never (only
    /// explicit `.refresh` or `.summary` will fetch). Default is 2 minutes.
    static let summaryRefreshMinutes = "summaryRefreshMinutes"

    /// Default refresh cadence applied when the user hasn't set one. Kept
    /// here so the SwiftUI `@AppStorage` binding and the SessionCoordinator's
    /// direct read agree on the fallback.
    static let summaryRefreshMinutesDefault = 2

    /// Effective refresh interval as a `TimeInterval`. Returns `nil` when
    /// the user has explicitly chosen "Never" (stored as 0). When the key
    /// has never been written, falls back to `summaryRefreshMinutesDefault`,
    /// so `UserDefaults.integer(forKey:)`'s zero-on-missing default doesn't
    /// collide with the "never" sentinel.
    static var summaryRefreshInterval: TimeInterval? {
        let stored = UserDefaults.standard.object(forKey: summaryRefreshMinutes) as? Int
        let minutes = stored ?? summaryRefreshMinutesDefault
        return minutes == 0 ? nil : TimeInterval(minutes * 60)
    }
}
