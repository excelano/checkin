// NLTaggerEntityMatcherTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the current matching behavior before Phase 7's microsoft-routing
/// fix changes how the surface text reads. The Microsoft-prefix case is
/// the load-bearing one — the suppression at firstNameFallbackCeiling is
/// what keeps the dialog from offering a 4-way vendor disambig.
struct NLTaggerEntityMatcherTests {
    private let matcher = NLTaggerEntityMatcher()

    // MARK: - Person, full canonical

    @Test func fullCanonicalMatchesLongestSpan() {
        let ctx = Fixtures.context(summary: Fixtures.summary(
            emails: [("Tony Smith", "Hello")]
        ))
        let matches = matcher.match(text: "from tony smith",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.count == 1)
        #expect(matches.first?.canonical == "Tony Smith")
        #expect(matches.first?.surface == "tony smith")
    }

    @Test func firstNameMatchesWhenSingleCandidate() {
        let ctx = Fixtures.context(summary: Fixtures.summary(
            emails: [("Tony Smith", "Hello")]
        ))
        let matches = matcher.match(text: "anything from tony",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.count == 1)
        #expect(matches.first?.canonical == "Tony Smith")
        #expect(matches.first?.confidence == 0.85)
    }

    @Test func firstNameProducesBothCandidatesWhenAmbiguous() {
        let ctx = Fixtures.context(summary: Fixtures.twoTonysSummary)
        let matches = matcher.match(text: "any from tony",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.count == 2)
        let canonicals = Set(matches.map { $0.canonical })
        #expect(canonicals == Set(["Tony Smith", "Tony Jones"]))
        // Both share the lower confidence floor for first-name ambiguity.
        #expect(matches.allSatisfy { $0.confidence == 0.6 })
    }

    // MARK: - Microsoft-prefix suppression (the pinned bug)

    /// Four or more known senders share a leading token → first-name
    /// fallback is suppressed and the matcher returns no match. The
    /// surface then routes through `filterUnknownSender("microsoft")`,
    /// which is the bit Phase 7 reconsiders. Pinning this here means a
    /// regression in the suppression logic gets caught immediately.
    @Test func microsoftPrefixReturnsNoMatchUnderCeiling() {
        let ctx = Fixtures.context(summary: Fixtures.microsoftPrefixSummary)
        let matches = matcher.match(text: "anything from microsoft",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.isEmpty)
    }

    /// The other senders in the same set still resolve normally — the
    /// suppression is scoped to the colliding first-name token.
    @Test func tonyStillResolvesAlongsideSuppressedMicrosoft() {
        let ctx = Fixtures.context(summary: Fixtures.microsoftPrefixSummary)
        let matches = matcher.match(text: "anything from tony",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.count == 1)
        #expect(matches.first?.canonical == "Tony Smith")
    }

    @Test func emptyKnownPeopleReturnsEmpty() {
        let ctx = Fixtures.context(summary: Fixtures.summary())
        let matches = matcher.match(text: "from anyone",
                                    domain: .person,
                                    context: ctx)
        #expect(matches.isEmpty)
    }

    @Test func noSummaryReturnsEmpty() {
        let matches = matcher.match(text: "from tony",
                                    domain: .person,
                                    context: DialogContext())
        #expect(matches.isEmpty)
    }

    // MARK: - Ordinal

    @Test func ordinalFirstResolvesToOne() {
        let matches = matcher.match(text: "the first",
                                    domain: .ordinal,
                                    context: DialogContext())
        #expect(matches.first?.canonical == "1")
    }

    @Test func ordinalSecondResolvesToTwo() {
        let matches = matcher.match(text: "number two",
                                    domain: .ordinal,
                                    context: DialogContext())
        #expect(matches.first?.canonical == "2")
    }

    @Test func latestResolvesToLatestCanonical() {
        let matches = matcher.match(text: "the latest one",
                                    domain: .ordinal,
                                    context: DialogContext())
        #expect(matches.first?.canonical == "latest")
    }

    // MARK: - Date

    @Test func dateTodayMatches() {
        let matches = matcher.match(text: "anything from today",
                                    domain: .date,
                                    context: DialogContext())
        #expect(matches.first?.canonical == "today")
    }

    @Test func dateThisWeekMatches() {
        let matches = matcher.match(text: "messages this week",
                                    domain: .date,
                                    context: DialogContext())
        #expect(matches.first?.canonical == "this week")
    }

    // MARK: - Subject domain is intentionally inert

    @Test func subjectDomainReturnsEmpty() {
        let ctx = Fixtures.context(summary: Fixtures.microsoftPrefixSummary)
        let matches = matcher.match(text: "anything about the project",
                                    domain: .subject,
                                    context: ctx)
        #expect(matches.isEmpty)
    }
}
