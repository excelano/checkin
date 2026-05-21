// Fixtures.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
@testable import CheckIn

/// Test fixtures. Build a deterministic `CheckInSummary` for tests to
/// chew on. Field shapes match what `GraphSummaryService` would produce.
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
}
