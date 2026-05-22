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

    // MSAL for iOS automatically requests openid, profile, and offline_access.
    // Mail.ReadWrite drives the email mutation surface (mark read, flag,
    // delete). Calendars.Read drives the next-meeting fetch. Chat.ReadWrite
    // drives the Teams pending-chat surface.
    static let baseScopes = [
        "User.Read",
        "Mail.ReadWrite",
        "Calendars.Read"
    ]

    static let teamsScopes = [
        "Chat.ReadWrite"
    ]

    static let teamsEnabled: Bool = true

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }
}

/// Single source of truth for `@AppStorage` / `UserDefaults` key names.
/// String values are wire-stable — renaming a case is a schema migration
/// because existing installs key off the value.
enum AppStorageKey {
    static let voiceEnabled = "voiceEnabled"
    static let customClientID = "customClientID"
    static let customAuthority = "customAuthority"
    static let summaryRefreshMinutes = "summaryRefreshMinutes"

    /// Default refresh cadence applied when the user hasn't set one.
    static let summaryRefreshMinutesDefault = 2

    /// Effective refresh interval as a `TimeInterval`. `nil` when the user
    /// has chosen "Never" (stored as 0). Falls back to the default when
    /// the key hasn't been written so the zero-on-missing default doesn't
    /// collide with the explicit "never" sentinel.
    static var summaryRefreshInterval: TimeInterval? {
        let stored = UserDefaults.standard.object(forKey: summaryRefreshMinutes) as? Int
        let minutes = stored ?? summaryRefreshMinutesDefault
        return minutes == 0 ? nil : TimeInterval(minutes * 60)
    }
}
