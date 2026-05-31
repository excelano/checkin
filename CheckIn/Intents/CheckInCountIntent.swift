// CheckInCountIntent.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Speak back one of CheckIn's inbox counts — unread emails, unread
/// chats, remaining meetings today, or all unread messages — from Siri,
/// Shortcuts, or Spotlight. Runs headless: refreshes CheckIn's summary,
/// then reads the count, so the spoken number matches the panel. The
/// pure counts don't need the full email set (the server total comes
/// back with a normal refresh), so this uses the default refresh.
struct CheckInCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Count"
    static var description = IntentDescription(
        "Count your unread emails, unread chats, remaining meetings, or all unread messages."
    )
    static var openAppWhenRun = false

    @Parameter(title: "What to count")
    var metric: CountMetric

    @Dependency var inbox: Inbox
    @Dependency var authService: AuthService

    init() {}

    init(metric: CountMetric) {
        self.metric = metric
    }

    static var parameterSummary: some ParameterSummary {
        Summary("How many \(\.$metric)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        _ = try await authService.acquireTokenSilentlyNoInteraction(enableTeams: Constants.teamsEnabled)
        await inbox.refresh()

        switch metric {
        case .unreadEmails:
            let n = inbox.unreadEmailCount
            return .result(value: n, dialog: "\(IntentSpeech.count(n, singular: "unread email", plural: "unread emails"))")
        case .unreadChats:
            let n = inbox.unreadChatCount
            return .result(value: n, dialog: "\(IntentSpeech.count(n, singular: "unread chat", plural: "unread chats"))")
        case .remainingMeetings:
            let n = inbox.remainingMeetingCount
            let dialog: IntentDialog = switch n {
            case 0: "You have no more meetings today."
            case 1: "You have 1 more meeting today."
            default: "You have \(n) more meetings today."
            }
            return .result(value: n, dialog: dialog)
        case .unreadMessages:
            let emails = inbox.unreadEmailCount
            let chats = inbox.unreadChatCount
            return .result(value: emails + chats, dialog: "\(IntentSpeech.unreadMessages(emails: emails, chats: chats))")
        }
    }
}
