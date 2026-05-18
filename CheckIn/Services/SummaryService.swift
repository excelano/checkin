// SummaryService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Pulls the three Day 1 surfaces (next meeting, unread email, pending
/// Teams chats) into a single `CheckInSummary` for the response generator
/// to consume.
///
/// Per-stream errors collapse into the `emailError` / `chatError` slots on
/// `CheckInSummary` so partial success surfaces correctly (Teams down,
/// email up still produces a useful summary). The meeting slot has no
/// error field by design — a meeting fetch failure is indistinguishable
/// from "nothing in the next 24 hours."
protocol SummaryService {
    func fetchSummary() async -> CheckInSummary
}

/// Microsoft Graph implementation. The three calls run in parallel via
/// `async let`; a single missing user-ID call (a prerequisite for the
/// Teams pending-chat heuristic) runs serially on first use.
@MainActor
final class GraphSummaryService: SummaryService {
    private let graphClient: GraphClient
    private let teamsEnabled: Bool
    private var didFetchUserID = false

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "summary")

    init(graphClient: GraphClient, teamsEnabled: Bool) {
        self.graphClient = graphClient
        self.teamsEnabled = teamsEnabled
    }

    func fetchSummary() async -> CheckInSummary {
        var userIDReady = !teamsEnabled || didFetchUserID
        if teamsEnabled && !didFetchUserID {
            do {
                try await graphClient.fetchUserID()
                didFetchUserID = true
                userIDReady = true
            } catch {
                logger.error("fetchUserID failed: \(error.localizedDescription, privacy: .public)")
                userIDReady = false
            }
        }

        let userIDForChats = userIDReady
        async let meetingTask: Meeting? = fetchMeetingOrNil()
        async let emailsTask: (emails: [Email], error: String?) = fetchEmails()
        async let chatsTask: (chats: [ChatMessage], error: String?) = fetchChats(userIDReady: userIDForChats)

        let meeting = await meetingTask
        let emailsTuple = await emailsTask
        let chatsTuple = await chatsTask

        return CheckInSummary(
            meeting: meeting,
            emails: emailsTuple.emails,
            chats: chatsTuple.chats,
            emailError: emailsTuple.error,
            chatError: chatsTuple.error,
            teamsEnabled: teamsEnabled
        )
    }

    private func fetchMeetingOrNil() async -> Meeting? {
        do {
            return try await graphClient.nextMeeting()
        } catch {
            logger.error("nextMeeting failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchEmails() async -> (emails: [Email], error: String?) {
        do {
            return (try await graphClient.unreadEmails(), nil)
        } catch {
            logger.error("unreadEmails failed: \(error.localizedDescription, privacy: .public)")
            return ([], error.localizedDescription)
        }
    }

    private func fetchChats(userIDReady: Bool) async -> (chats: [ChatMessage], error: String?) {
        guard teamsEnabled else { return ([], nil) }
        // If fetchUserID failed the pending-chat heuristic can't run; the
        // Teams scope likely isn't granted on the silent token.
        guard userIDReady else {
            return ([], "Teams access not available.")
        }
        do {
            return (try await graphClient.pendingChats(), nil)
        } catch {
            logger.error("pendingChats failed: \(error.localizedDescription, privacy: .public)")
            return ([], error.localizedDescription)
        }
    }
}

/// Preview/test stub: returns a fixed empty summary.
final class StubSummaryService: SummaryService {
    private let summary: CheckInSummary
    init(_ summary: CheckInSummary = CheckInSummary(
        meeting: nil,
        emails: [],
        chats: [],
        emailError: nil,
        chatError: nil,
        teamsEnabled: false
    )) {
        self.summary = summary
    }
    func fetchSummary() async -> CheckInSummary { summary }
}
