// CurrentPresenceIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit

/// Read back the user's current Microsoft 365 presence (and whether
/// Out-of-Office is on) from Siri, Shortcuts, or Spotlight. Runs headless:
/// refreshes CheckIn's summary, then reads `currentPresence` /
/// `isOutOfOffice`, so the spoken state matches the panel. Returns the
/// presence name as a value too, for Shortcuts to chain on.
struct CurrentPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Current Presence"
    static var description = IntentDescription("Check your current Microsoft 365 status.")
    static var openAppWhenRun = false

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.refresh()

        let presence = inbox.currentPresence
        let value = presence == .unknown ? "Not set" : presence.displayName
        let dialog: IntentDialog = "\(IntentSpeech.currentPresence(presence, isOutOfOffice: inbox.isOutOfOffice))"
        return .result(value: value, dialog: dialog)
    }
}
