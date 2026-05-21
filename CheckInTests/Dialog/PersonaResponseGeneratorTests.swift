// PersonaResponseGeneratorTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the anti-repeat behavior of `PersonaResponseGenerator` and the
/// dispatch from `Intent` to category/phrasing. Anti-repeat is the
/// behavior that PERSONA.md guarantees ("never re-uses a refusal or
/// redirect phrasing in the recent window") and the test that's hardest
/// to verify by eye in shipped behavior.
struct PersonaResponseGeneratorTests {
    private let generator = PersonaResponseGenerator()

    private func classified(_ intent: Intent) -> ClassifiedIntent {
        ClassifiedIntent(intent: intent, confidence: 0.9)
    }

    // MARK: - Category dispatch

    @Test func outOfScopeProducesRefusal() {
        let r = generator.generate(for: classified(.outOfScope),
                                   utterance: "what's the weather",
                                   resolvedSender: nil,
                                   context: DialogContext())
        #expect(r.category == .refusal)
        #expect(!r.text.isEmpty)
    }

    @Test func inScopeUnsupportedProducesRedirect() {
        let r = generator.generate(for: classified(.inScopeUnsupported(.readContent)),
                                   utterance: "read me the email",
                                   resolvedSender: nil,
                                   context: DialogContext())
        #expect(r.category == .redirect)
        #expect(!r.text.isEmpty)
    }

    @Test func unknownProducesError() {
        let r = generator.generate(for: classified(.unknown),
                                   utterance: "asdfgh",
                                   resolvedSender: nil,
                                   context: DialogContext())
        #expect(r.category == .error)
    }

    @Test func summaryWithoutFetchedSummaryNudgesToFetch() {
        let r = generator.generate(for: classified(.summary),
                                   utterance: "what's on my plate",
                                   resolvedSender: nil,
                                   context: DialogContext())
        #expect(r.text.lowercased().contains("haven't fetched"))
    }

    @Test func summaryWithFetchedSummaryReadsTheRoom() {
        var ctx = DialogContext()
        ctx.summary = Fixtures.summary(emails: [("Tony Smith", "Project update")])
        let r = generator.generate(for: classified(.summary),
                                   utterance: "what's on my plate",
                                   resolvedSender: nil,
                                   context: ctx)
        #expect(r.category == .summary)
        #expect(r.text.contains("Tony Smith"))
    }

    @Test func repeatLastWithEmptyHistoryFallsThrough() {
        let r = generator.generate(for: classified(.repeatLast),
                                   utterance: "say that again",
                                   resolvedSender: nil,
                                   context: DialogContext())
        #expect(r.text == ResponseTemplateRegistry.nothingToRepeat)
    }

    @Test func repeatLastWithHistoryEchoes() {
        var ctx = DialogContext()
        ctx.lastSystemResponse = "Previously spoken thing."
        let r = generator.generate(for: classified(.repeatLast),
                                   utterance: "say that again",
                                   resolvedSender: nil,
                                   context: ctx)
        #expect(r.text == "Previously spoken thing.")
    }

    // MARK: - Anti-repeat

    /// With the entire refusal pool minus one entry on the avoid list,
    /// the picker must return the single remaining entry.
    @Test func refusalAntiRepeatHonorsRecent() {
        let pool = ResponseTemplateRegistry.refusals
        let avoid = Array(pool.dropLast())
        var ctx = DialogContext()
        ctx.recentRefusals = avoid

        let r = generator.generate(for: classified(.outOfScope),
                                   utterance: "play music",
                                   resolvedSender: nil,
                                   context: ctx)
        #expect(r.text == pool.last)
    }

    /// Same shape for redirects on a specific sub-kind pool.
    @Test func redirectAntiRepeatHonorsRecent() {
        let pool = ResponseTemplateRegistry.readContentRedirects
        let avoid = Array(pool.dropLast())
        var ctx = DialogContext()
        ctx.recentRedirects = avoid

        let r = generator.generate(for: classified(.inScopeUnsupported(.readContent)),
                                   utterance: "read me it",
                                   resolvedSender: nil,
                                   context: ctx)
        #expect(r.text == pool.last)
    }

    /// When the pool is fully covered by recents, the picker still
    /// returns *something* — falling back to anything that isn't the
    /// most-recent line so two turns in a row are never identical.
    @Test func refusalFallbackWhenPoolFullyCovered() {
        var ctx = DialogContext()
        ctx.recentRefusals = ResponseTemplateRegistry.refusals
        let r = generator.generate(for: classified(.outOfScope),
                                   utterance: "play music",
                                   resolvedSender: nil,
                                   context: ctx)
        #expect(!r.text.isEmpty)
        // Must not be the most recent — that's the anti-repeat floor.
        #expect(r.text != ResponseTemplateRegistry.refusals.last)
    }
}
