// Constants.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum Constants {
    static let clientID = "0ce3820d-db53-4b2e-9621-6c4ccc086d5a"

    static let authority = "https://login.microsoftonline.com/common"
    static let redirectURI = "msauth.com.excelano.checkin://auth"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    // MSAL for iOS automatically requests openid, profile, and offline_access.
    // Mail.ReadWrite drives the email mutation surface (mark read, flag).
    // Calendars.ReadWrite drives the next-meeting fetch and the RSVP
    // (accept/tentative/decline) calls. Chat.ReadWrite drives the Teams
    // pending-chat surface.
    static let baseScopes = [
        "User.Read",
        "Mail.ReadWrite",
        "Calendars.ReadWrite"
    ]

    static let teamsScopes = [
        "Chat.ReadWrite",
        "Presence.ReadWrite"
    ]

    static let teamsEnabled: Bool = true

    /// Identifier the OS uses for our background refresh task. Must match
    /// the `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
    static let backgroundRefreshIdentifier = "com.excelano.checkin.refresh"

    /// Lower bound iOS uses when scheduling our next background run.
    /// Actual run time is at the system's discretion and can be much
    /// later (or never, on a quiet day or after a force-quit).
    static let backgroundRefreshInterval: TimeInterval = 30 * 60

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }

    /// User-supplied client ID if set, otherwise the published default.
    static var effectiveClientID: String {
        let custom = (UserDefaults.standard.string(forKey: AppStorageKey.customClientID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? clientID : custom
    }

    /// `https://login.microsoftonline.com/<tenant>` where `<tenant>` is the
    /// user-supplied Directory (tenant) ID, or `common` when none is set.
    static var effectiveAuthority: String {
        let tenant = (UserDefaults.standard.string(forKey: AppStorageKey.customTenantID) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tenant.isEmpty { return authority }
        return "https://login.microsoftonline.com/\(tenant)"
    }
}

enum AppStorageKey {
    static let customClientID = "customClientID"
    static let customTenantID = "customTenantID"
    static let showingAllEmails = "showingAllEmails"
}
