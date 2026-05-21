// Fixtures.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
@testable import CheckIn

/// Test fixtures. Build a `CheckInSummary` with known senders so the
/// entity matcher and the response generator both have something
/// deterministic to chew on.
enum Fixtures {

    static func summary(emails: [(from: String, subject: String)] = [],
                        chats: [(from: String, topic: String)] = [],
                        meeting: Meeting? = nil,
                        teamsEnabled: Bool = true) -> CheckInSummary {
        let emailObjects = emails.enumerated().map { (i, e) in
            Email(id: "msg-\(i)",
                  subject: e.subject,
                  from: e.from,
                  fromAddress: "\(e.from.lowercased().replacingOccurrences(of: " ", with: "."))@example.com",
                  preview: "",
                  received: Date(timeIntervalSinceReferenceDate: Double(i) * 60))
        }
        let chatObjects = chats.map { c in
            ChatMessage(chatID: "chat-\(c.from)",
                        topic: c.topic,
                        from: c.from,
                        preview: "",
                        sent: Date(),
                        webUrl: nil)
        }
        return CheckInSummary(meeting: meeting,
                              emails: emailObjects,
                              chats: chatObjects,
                              emailError: nil,
                              chatError: nil,
                              teamsEnabled: teamsEnabled)
    }

    static func context(summary: CheckInSummary? = nil) -> DialogContext {
        var ctx = DialogContext()
        ctx.summary = summary
        return ctx
    }

    /// A Microsoft-prefix-heavy sender set that exercises the
    /// firstNameFallbackCeiling suppression path in NLTaggerEntityMatcher.
    static let microsoftPrefixSummary: CheckInSummary = summary(
        emails: [
            ("Microsoft Outlook", "Calendar reminder"),
            ("Microsoft Teams", "You have unread messages"),
            ("Microsoft 365 Message Center", "Service health"),
            ("Microsoft Security", "Sign-in alert"),
            ("Tony Smith", "Project update")
        ]
    )

    /// Two distinct people sharing a first name — the disambiguation case.
    static let twoTonysSummary: CheckInSummary = summary(
        emails: [
            ("Tony Smith", "Project update"),
            ("Tony Jones", "Review request")
        ]
    )
}
