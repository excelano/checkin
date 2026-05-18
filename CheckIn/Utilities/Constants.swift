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
        "Mail.ReadWrite",
        "Mail.Send",
        "Calendars.Read"
    ]

    static let teamsScopes = [
        "Chat.ReadWrite"
    ]

    /// Whether the Teams pending-chat surface is part of the summary. Single
    /// source of truth for sign-in scopes and the Graph fetch in
    /// `GraphSummaryService`. D25 self-host override is a separate slice.
    static let teamsEnabled: Bool = true

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }
}
