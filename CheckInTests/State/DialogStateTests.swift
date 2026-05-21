// DialogStateTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the shape of the speaking-state `followUp` payload introduced when
/// the `pendingDisambiguation` side-channel was retired. The followUp is
/// how `.speaking` tells the speaking-finish handler whether to land in
/// rest or in `.disambiguating`.
struct DialogStateTests {

    @Test func speakingRestFollowUpCarriesRestState() {
        let response = SpokenResponse(text: "Three unread.", category: .summary)
        let state: ActiveSubstate = .speaking(response: response,
                                              followUp: .rest(.listening))
        if case .speaking(_, .rest(let rest)) = state {
            #expect(rest == .listening)
        } else {
            Issue.record("expected .speaking(_, .rest)")
        }
    }

    @Test func speakingDisambiguateFollowUpCarriesPending() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let pending = PendingDisambiguation(
            suspendedIntent: SuspendedIntent(utterance: "any from tony", intent: "filter"),
            surface: "Tony",
            candidates: candidates
        )
        let response = SpokenResponse(text: "Two Tonys.", category: .disambiguation)
        let state: ActiveSubstate = .speaking(response: response,
                                              followUp: .disambiguate(pending))
        if case .speaking(_, .disambiguate(let carried)) = state {
            #expect(carried.surface == "Tony")
            #expect(carried.candidates.count == 2)
            #expect(carried.suspendedIntent.utterance == "any from tony")
        } else {
            Issue.record("expected .speaking(_, .disambiguate)")
        }
    }

    @Test func disambiguatingCarriesSuspendedCandidatesAndSurface() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let state: ActiveSubstate = .disambiguating(
            suspendedIntent: SuspendedIntent(utterance: "any from tony", intent: "filter"),
            candidates: candidates,
            surface: "Tony"
        )
        if case .disambiguating(let suspended, let cands, let surface) = state {
            #expect(suspended.utterance == "any from tony")
            #expect(cands.count == 2)
            #expect(surface == "Tony")
        } else {
            Issue.record("expected .disambiguating")
        }
    }

    @Test func followUpEquatableDiscriminatesRestVsDisambiguate() {
        let pending = PendingDisambiguation(
            suspendedIntent: SuspendedIntent(utterance: "u", intent: "filter"),
            surface: "s",
            candidates: []
        )
        let restListening: SpeakingFollowUp = .rest(.listening)
        let restIdle: SpeakingFollowUp = .rest(.idle)
        let disambig: SpeakingFollowUp = .disambiguate(pending)

        #expect(restListening != restIdle)
        #expect(restListening != disambig)
        #expect(restListening == .rest(.listening))
        #expect(disambig == .disambiguate(pending))
    }
}
