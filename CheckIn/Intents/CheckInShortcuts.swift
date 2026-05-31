// CheckInShortcuts.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

/// Surfaces CheckIn's intents to Siri and Spotlight with spoken phrases.
/// Every phrase must contain the `\(.applicationName)` token — the
/// framework requires it so Siri can disambiguate which app to invoke —
/// and by convention it goes last, as "in the \(.applicationName) app".
/// Phrases keep both "status" and "presence" wordings because users say
/// both; the extra variants cost nothing and improve Siri's match rate.
struct CheckInShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetPresenceIntent(),
            phrases: [
                "Set my presence to \(\.$status) in the \(.applicationName) app",
                "Change my presence to \(\.$status) in the \(.applicationName) app",
                "Mark me as \(\.$status) in the \(.applicationName) app",
                "Set my status to \(\.$status) in the \(.applicationName) app",
                "Set my status in the \(.applicationName) app",
                "Change my status in the \(.applicationName) app",
            ],
            shortTitle: "Set Presence",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: CurrentPresenceIntent(),
            phrases: [
                "What's my presence in the \(.applicationName) app",
                "What's my status in the \(.applicationName) app",
                "What's my current status in the \(.applicationName) app",
                "What am I set to in the \(.applicationName) app",
            ],
            shortTitle: "My Presence",
            systemImageName: "person.crop.circle.fill"
        )
        AppShortcut(
            intent: NextMeetingIntent(),
            phrases: [
                "What's my next meeting in the \(.applicationName) app",
                "When's my next meeting in the \(.applicationName) app",
                "What's coming up next in the \(.applicationName) app",
                "What's my next call in the \(.applicationName) app",
            ],
            shortTitle: "Next Meeting",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(value: true),
            phrases: [
                "Turn on my Out of Office in the \(.applicationName) app",
                "Set my Out of Office on in the \(.applicationName) app",
                "Enable my Out of Office in the \(.applicationName) app",
                "Set me to out of office in the \(.applicationName) app",
            ],
            shortTitle: "Turn On Out of Office",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: SetOutOfOfficeIntent(value: false),
            phrases: [
                "Turn off my Out of Office in the \(.applicationName) app",
                "Set my Out of Office off in the \(.applicationName) app",
                "Disable my Out of Office in the \(.applicationName) app",
                "Clear my Out of Office in the \(.applicationName) app",
            ],
            shortTitle: "Turn Off Out of Office",
            systemImageName: "envelope.open"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadEmails),
            phrases: [
                "How many unread emails do I have in the \(.applicationName) app",
                "How many unread emails in the \(.applicationName) app",
                "Do I have any unread emails in the \(.applicationName) app",
                "Any unread emails in the \(.applicationName) app",
            ],
            shortTitle: "Unread Emails",
            systemImageName: "envelope.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadChats),
            phrases: [
                "How many unread chats do I have in the \(.applicationName) app",
                "How many unread chats in the \(.applicationName) app",
                "Do I have any unread chats in the \(.applicationName) app",
            ],
            shortTitle: "Unread Chats",
            systemImageName: "message.badge"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .remainingMeetings),
            phrases: [
                "How many more meetings today in the \(.applicationName) app",
                "How many meetings do I have left in the \(.applicationName) app",
                "How many meetings are left today in the \(.applicationName) app",
                "Do I have more meetings today in the \(.applicationName) app",
            ],
            shortTitle: "Remaining Meetings",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: CheckInCountIntent(metric: .unreadMessages),
            phrases: [
                "How many unread messages do I have in the \(.applicationName) app",
                "How many unread messages in the \(.applicationName) app",
                "Do I have any unread messages in the \(.applicationName) app",
                "Am I caught up in the \(.applicationName) app",
            ],
            shortTitle: "Unread Messages",
            systemImageName: "tray.full"
        )
        AppShortcut(
            intent: WorkdaySummaryIntent(),
            phrases: [
                "What's my work day like in the \(.applicationName) app",
                "Tell me about my work day in the \(.applicationName) app",
                "What's on my plate in the \(.applicationName) app",
                "What's my overview in the \(.applicationName) app",
                "Give me an overview in the \(.applicationName) app",
                "How's my day looking in the \(.applicationName) app",
                "Catch me up in the \(.applicationName) app",
            ],
            shortTitle: "Work Day",
            systemImageName: "list.bullet.clipboard"
        )
    }
}
