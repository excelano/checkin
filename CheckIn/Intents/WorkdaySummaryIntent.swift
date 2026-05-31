// WorkdaySummaryIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Speak a quick work-day overview from Siri, Shortcuts, or Spotlight:
/// the next meeting today immediately followed by the unread-message
/// count. Combines what `NextMeetingIntent` and `CheckInCountIntent`
/// (`.unreadMessages`) say on their own, sharing their exact wording via
/// `IntentSpeech` so the three intents never drift apart. Runs headless.
///
/// One refresh feeds both reads — the meeting and the counts come back in
/// the same fetch, so this is no more work than either intent alone.
struct WorkdaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Work Day Summary"
    static var description = IntentDescription(
        "Hear your next meeting and unread messages together."
    )
    static var openAppWhenRun = false

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.refresh()

        let meeting = IntentSpeech.nextMeeting(inbox.nextMeeting)
        let messages = IntentSpeech.unreadMessages(
            emails: inbox.unreadEmailCount,
            chats: inbox.unreadChatCount
        )
        let dialog: IntentDialog = "\(meeting) \(messages)"
        return .result(dialog: dialog)
    }
}
