// DialogContextTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the mutator surface on `DialogContext`. The recordTurn /
/// rememberPhrasing pair plus the ring trimming are the bits the
/// coordinator and the response generator both rely on.
struct DialogContextTests {

    // MARK: - recordTurn

    @Test func recordTurnUpdatesLastUtteranceAndResponse() {
        var ctx = DialogContext()
        ctx.recordTurn(user: "what's on my plate", system: "Three unread.")
        #expect(ctx.lastUtterance == "what's on my plate")
        #expect(ctx.lastSystemResponse == "Three unread.")
        #expect(ctx.turnHistory.count == 1)
    }

    /// Silent intents (.stop, .refresh ack, deep-link routes) record an
    /// empty system response. The previously-spoken line must stay
    /// reachable so `.repeatLast` can still surface it.
    @Test func recordTurnEmptySystemDoesNotShadowPriorResponse() {
        var ctx = DialogContext()
        ctx.recordTurn(user: "what's on my plate", system: "Three unread.")
        ctx.recordTurn(user: "stop", system: "")
        #expect(ctx.lastUtterance == "stop")
        #expect(ctx.lastSystemResponse == "Three unread.")
    }

    @Test func turnHistoryTrimsToLimit() {
        var ctx = DialogContext()
        let limit = DialogContext.turnHistoryLimit
        for i in 0..<(limit + 3) {
            ctx.recordTurn(user: "u\(i)", system: "s\(i)")
        }
        #expect(ctx.turnHistory.count == limit)
        // Oldest dropped, newest kept.
        #expect(ctx.turnHistory.first?.userUtterance == "u3")
        #expect(ctx.turnHistory.last?.userUtterance == "u\(limit + 2)")
    }

    // MARK: - rememberPhrasing (anti-repeat ledger)

    @Test func rememberPhrasingRecordsRefusal() {
        var ctx = DialogContext()
        ctx.rememberPhrasing("Not my area.", in: .refusal)
        #expect(ctx.recentRefusals == ["Not my area."])
    }

    @Test func rememberPhrasingRecordsRedirect() {
        var ctx = DialogContext()
        ctx.rememberPhrasing("Tap to open it.", in: .redirect)
        #expect(ctx.recentRedirects == ["Tap to open it."])
    }

    @Test func rememberPhrasingIgnoresOtherCategories() {
        var ctx = DialogContext()
        ctx.rememberPhrasing("Three unread.", in: .summary)
        ctx.rememberPhrasing("Got it.", in: .answer)
        ctx.rememberPhrasing("Net down.", in: .error)
        #expect(ctx.recentRefusals.isEmpty)
        #expect(ctx.recentRedirects.isEmpty)
    }

    @Test func refusalLedgerTrimsToLimit() {
        var ctx = DialogContext()
        let limit = DialogContext.recentPhrasingLimit
        for i in 0..<(limit + 2) {
            ctx.rememberPhrasing("r\(i)", in: .refusal)
        }
        #expect(ctx.recentRefusals.count == limit)
        #expect(ctx.recentRefusals.first == "r2")
        #expect(ctx.recentRefusals.last == "r\(limit + 1)")
    }

    @Test func redirectLedgerTrimsToLimit() {
        var ctx = DialogContext()
        let limit = DialogContext.recentPhrasingLimit
        for i in 0..<(limit + 2) {
            ctx.rememberPhrasing("rd\(i)", in: .redirect)
        }
        #expect(ctx.recentRedirects.count == limit)
        #expect(ctx.recentRedirects.first == "rd2")
    }

    @Test func disambiguationFailedAttemptsDefaultsToZero() {
        let ctx = DialogContext()
        #expect(ctx.disambiguationFailedAttempts == 0)
    }

    @Test func repromptCountDefaultsToZero() {
        let ctx = DialogContext()
        #expect(ctx.repromptCount == 0)
    }
}
