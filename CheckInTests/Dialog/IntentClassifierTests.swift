// IntentClassifierTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the launch intent surface against the real
/// `NLEmbeddingIntentClassifier`. The classifier loads the sentence
/// embedding for English at init; if the embedding model isn't available
/// in the test process the tests fail loudly rather than silently
/// passing — that's intentional.
///
/// Golden set is small on purpose. We want regression detection for the
/// shape of the classifier's decisions, not an exhaustive evaluation
/// suite. Confidence floors here mirror the live coordinator's path
/// (default `confidenceFloor = 0.85`, `unknownFloor = 1.05`).
struct IntentClassifierTests {

    /// Build a fresh classifier per test so anchor-cache state can't
    /// leak between cases.
    private func classifier() -> NLEmbeddingIntentClassifier {
        NLEmbeddingIntentClassifier()
    }

    private let context = DialogContext()

    // MARK: - Core operational intents

    @Test("summary anchor — 'what's on my plate'")
    func summaryDirect() {
        let result = classifier().classify(utterance: "what's on my plate", context: context)
        #expect(result.intent == .summary)
    }

    @Test("summary anchor — 'give me a summary'")
    func summaryVerb() {
        let result = classifier().classify(utterance: "give me a summary", context: context)
        #expect(result.intent == .summary)
    }

    @Test("filter — 'anything from tony'")
    func filterFromTony() {
        let result = classifier().classify(utterance: "anything from tony", context: context)
        #expect(result.intent == .filter)
    }

    @Test("filter — count phrasing 'how many emails from tony'")
    func filterCount() {
        let result = classifier().classify(utterance: "how many emails from tony", context: context)
        #expect(result.intent == .filter)
    }

    @Test("refresh — 'check again'")
    func refresh() {
        let result = classifier().classify(utterance: "check again", context: context)
        #expect(result.intent == .refresh)
    }

    @Test("repeatLast — 'say that again'")
    func repeatLast() {
        let result = classifier().classify(utterance: "say that again", context: context)
        #expect(result.intent == .repeatLast)
    }

    @Test("stop — 'stop'")
    func stop() {
        let result = classifier().classify(utterance: "stop", context: context)
        #expect(result.intent == .stop)
    }

    @Test("help — 'what can i say'")
    func help() {
        let result = classifier().classify(utterance: "what can i say", context: context)
        #expect(result.intent == .help)
    }

    @Test("open — 'open tony's email'")
    func openTonysEmail() {
        let result = classifier().classify(utterance: "open tony's email", context: context)
        #expect(result.intent == .open)
    }

    @Test("reply — 'reply to tony'")
    func reply() {
        let result = classifier().classify(utterance: "reply to tony", context: context)
        #expect(result.intent == .reply)
    }

    @Test("join — 'join my meeting'")
    func join() {
        let result = classifier().classify(utterance: "join my meeting", context: context)
        #expect(result.intent == .join)
    }

    @Test("timeQuery — 'when's my next meeting'")
    func timeQuery() {
        let result = classifier().classify(utterance: "when's my next meeting", context: context)
        #expect(result.intent == .timeQuery)
    }

    @Test("exit — 'thanks'")
    func exit() {
        let result = classifier().classify(utterance: "thanks", context: context)
        #expect(result.intent == .exit)
    }

    @Test("settings — 'open settings'")
    func settings() {
        let result = classifier().classify(utterance: "open settings", context: context)
        #expect(result.intent == .settings)
    }

    @Test("yes — 'yes'")
    func yes() {
        let result = classifier().classify(utterance: "yes", context: context)
        #expect(result.intent == .yes)
    }

    @Test("no — 'cancel'")
    func no() {
        let result = classifier().classify(utterance: "cancel", context: context)
        #expect(result.intent == .no)
    }

    @Test("ordinalSelection — 'the first'")
    func ordinalSelection() {
        let result = classifier().classify(utterance: "the first", context: context)
        #expect(result.intent == .ordinalSelection)
    }

    // MARK: - Scope categories

    @Test("in-scope-unsupported readContent — 'read me tony's email'")
    func readContentRedirect() {
        let result = classifier().classify(utterance: "read me tony's email", context: context)
        #expect(result.intent == .inScopeUnsupported(.readContent))
    }

    @Test("in-scope-unsupported summarizeContent — 'summarize tony's email'")
    func summarizeContentRedirect() {
        let result = classifier().classify(utterance: "summarize tony's email", context: context)
        #expect(result.intent == .inScopeUnsupported(.summarizeContent))
    }

    @Test("out-of-scope probe — 'what's the weather'")
    func outOfScopeWeather() {
        let result = classifier().classify(utterance: "what's the weather", context: context)
        #expect(result.intent == .outOfScope)
    }

    // MARK: - Confidence and degenerate input

    @Test("clear anchor match produces non-zero confidence")
    func confidenceNonZero() {
        let result = classifier().classify(utterance: "what's on my plate", context: context)
        #expect(result.confidence > 0.0)
    }

    @Test("empty utterance returns unknown with zero confidence")
    func emptyUtteranceUnknown() {
        let result = classifier().classify(utterance: "", context: context)
        #expect(result.intent == .unknown)
        #expect(result.confidence == 0.0)
    }

    @Test("whitespace-only utterance returns unknown")
    func whitespaceUnknown() {
        let result = classifier().classify(utterance: "   \n  ", context: context)
        #expect(result.intent == .unknown)
    }
}
