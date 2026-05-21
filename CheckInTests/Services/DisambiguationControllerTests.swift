// DisambiguationControllerTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
import Foundation
@testable import CheckIn

/// Pins the disambiguation flow at the controller level. Same scenarios
/// the side-channel-era flow used to depend on, now directed at the
/// extracted type instead of SessionCoordinator.
@MainActor
struct DisambiguationControllerTests {

    // MARK: - Fixtures

    private static let tonys: [Candidate] = [
        Candidate(label: "Tony Smith", entityRef: "Tony Smith"),
        Candidate(label: "Tony Jones", entityRef: "Tony Jones")
    ]

    private static let filterSuspended = SuspendedIntent(utterance: "any from tony",
                                                         origin: .filter)
    private static let replySuspended = SuspendedIntent(utterance: "reply to tony",
                                                        origin: .reply)
    private static let mutationSuspended = SuspendedIntent(
        utterance: "mark tony's email as read",
        origin: .mutation(.markRead)
    )

    private static func enterDisambiguating(_ sm: StateMachine,
                                            preferred: RestState = .idle,
                                            suspended: SuspendedIntent = filterSuspended) {
        sm.preferredRestState = preferred
        sm.transition(to: .active(.disambiguating(
            suspendedIntent: suspended,
            candidates: tonys,
            surface: "Tony")))
    }

    private static func makeController(matcher: ScriptedEntityMatcher = .init())
        -> (StateMachine, DisambiguationController, IntentExecutor) {
        let sm = StateMachine()
        let executor = IntentExecutor(entityMatcher: matcher,
                                      urlOpener: { _ in true })
        let controller = DisambiguationController(
            stateMachine: sm,
            responseGenerator: StubResponseGenerator(),
            entityMatcher: matcher,
            intentExecutor: executor,
            utteranceLog: NoOpUtteranceLog()
        )
        return (sm, controller, executor)
    }

    // MARK: - cancel

    @Test func cancelReturnsToIdleInTapToTalk() {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm, preferred: .idle)
        controller.cancel()
        #expect(sm.currentState == .active(.idle))
    }

    @Test func cancelReturnsToListeningInConversationMode() {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm, preferred: .listening)
        controller.cancel()
        #expect(sm.currentState == .active(.listening))
    }

    // MARK: - resume

    @Test func resumeRoutesThroughProcessing() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        controller.resume(with: Self.tonys[0])
        // Synchronous transition lands in .processing(.thinking) before the
        // Task-spawned completeFilterTurn runs.
        #expect(sm.currentState == .active(.processing(.thinking)))
    }

    @Test func resumeZerosFailedAttempts() {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        sm.updateContext { $0.disambiguationFailedAttempts = 1 }
        controller.resume(with: Self.tonys[0])
        #expect(sm.context.disambiguationFailedAttempts == 0)
    }

    @Test func resumeNoOpsWhenNotInDisambiguating() {
        let (sm, controller, _) = Self.makeController()
        sm.transition(to: .active(.idle))
        controller.resume(with: Self.tonys[0])
        #expect(sm.currentState == .active(.idle))
    }

    // MARK: - handleUtterance — cancel terms

    @Test func handleUtteranceCancelTermRoutesToRest() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("never mind",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        #expect(sm.currentState == .active(.idle))
    }

    // MARK: - handleUtterance — ordinal pick

    @Test func handleUtteranceOrdinalPicksCorrectCandidate() async {
        var matcher = ScriptedEntityMatcher()
        matcher.ordinalForText["the first one"] = EntityMatch(
            surface: "first", canonical: "1", confidence: 0.9)
        let (sm, controller, _) = Self.makeController(matcher: matcher)
        Self.enterDisambiguating(sm)

        await controller.handleUtterance("the first one",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // resume(with:) was invoked synchronously inside handleUtterance —
        // the state machine sits in .processing while completeFilterTurn
        // races. Either .processing or the subsequent .speaking is fine
        // proof that the resume path fired.
        switch sm.currentState {
        case .active(.processing), .active(.speaking):
            break
        default:
            Issue.record("expected processing/speaking, got \(sm.currentState)")
        }
    }

    @Test func handleUtteranceOutOfRangeOrdinalFallsThroughToMiss() async {
        var matcher = ScriptedEntityMatcher()
        matcher.ordinalForText["the fifth one"] = EntityMatch(
            surface: "fifth", canonical: "5", confidence: 0.9)
        let (sm, controller, _) = Self.makeController(matcher: matcher)
        Self.enterDisambiguating(sm)

        await controller.handleUtterance("the fifth one",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // Out-of-range ordinal isn't a pick. It also doesn't match a label.
        // Falls through to the miss-counting path → first miss → retry.
        #expect(sm.context.disambiguationFailedAttempts == 1)
        if case .active(.speaking(_, .disambiguate)) = sm.currentState {
            // expected — retry prompt with the followUp re-armed
        } else {
            Issue.record("expected .speaking with .disambiguate followUp")
        }
    }

    // MARK: - handleUtterance — name pick

    @Test func handleUtteranceLastNameSubstringResumes() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("jones",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // "jones" is a >2-char word in "Tony Jones"'s label, so candidates[1]
        // is picked and resume(with:) routes through .processing.
        switch sm.currentState {
        case .active(.processing), .active(.speaking):
            break
        default:
            Issue.record("expected processing/speaking, got \(sm.currentState)")
        }
    }

    // MARK: - handleUtterance — retry / bail

    @Test func handleUtteranceFirstMissReprompts() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        await controller.handleUtterance("uh what",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        #expect(sm.context.disambiguationFailedAttempts == 1)
        if case .active(.speaking(let response, .disambiguate(let pending))) = sm.currentState {
            #expect(response.category == .disambiguation)
            #expect(pending.candidates.count == 2)
            #expect(pending.surface == "Tony")
        } else {
            Issue.record("expected .speaking with .disambiguate followUp")
        }
    }

    // MARK: - resume (reply origin)

    @Test func resumeWithReplyOriginRoutesThroughProcessing() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm, suspended: Self.replySuspended)
        controller.resume(with: Self.tonys[0])
        #expect(sm.currentState == .active(.processing(.thinking)))
    }

    @Test func resumeWithReplyOriginEventuallyLeavesProcessing() async {
        // Spawned completeReplyTurn runs through executor.resolveReply.
        // With no matching email in context, handleReply lands on the
        // replyUnknownSender response and transitions to .speaking.
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm, suspended: Self.replySuspended)
        controller.resume(with: Self.tonys[0])
        for _ in 0..<50 {
            if case .active(.processing) = sm.currentState {
                try? await Task.sleep(nanoseconds: 10_000_000)
            } else {
                break
            }
        }
        if case .active(.speaking(let response, _)) = sm.currentState {
            #expect(response.text == ResponseTemplateRegistry.replyUnknownSender("Tony Smith"))
        } else {
            Issue.record("expected .speaking after reply resume, got \(sm.currentState)")
        }
    }

    // MARK: - resume (mutation origin)

    @Test func resumeWithMutationOriginRoutesThroughProcessing() {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm, suspended: Self.mutationSuspended)
        controller.resume(with: Self.tonys[0])
        #expect(sm.currentState == .active(.processing(.thinking)))
    }

    @Test func resumeWithMutationOriginLandsInConfirmingWhenSenderHasEmail() async {
        // Set up a summary so handleMutation finds Tony Smith's email
        // and builds a PendingMutation. The resume path should land in
        // .speaking(_, .confirm(pending)) carrying the mutation kind.
        let (sm, controller, _) = Self.makeController()
        let email = Email(id: "abc", subject: "Hi", from: "Tony Smith",
                          fromAddress: "tony@example.com",
                          preview: "", received: Date())
        let summary = CheckInSummary(meeting: nil, emails: [email], chats: [],
                                     emailError: nil, chatError: nil, teamsEnabled: true)
        sm.updateContext { $0.summary = summary }
        Self.enterDisambiguating(sm, suspended: Self.mutationSuspended)
        controller.resume(with: Self.tonys[0])
        // completeMutationTurn is synchronous in its happy-path body
        // (Task only handles utteranceLog.record), so .speaking should
        // appear without a wait — but allow a tick for the spawned Task.
        try? await Task.sleep(nanoseconds: 10_000_000)
        if case .active(.speaking(let response, let followUp)) = sm.currentState {
            #expect(response.category == .confirmation)
            if case .confirm(let pending) = followUp {
                #expect(pending.kind == .markRead)
                #expect(pending.targets == ["abc"])
            } else {
                Issue.record("expected .confirm follow-up, got \(followUp)")
            }
        } else {
            Issue.record("expected .speaking after mutation resume, got \(sm.currentState)")
        }
    }

    @Test func handleUtteranceSecondMissBailsToRest() async {
        let (sm, controller, _) = Self.makeController()
        Self.enterDisambiguating(sm)
        // Prime one prior miss so the next no-match trips the bail branch.
        sm.updateContext { $0.disambiguationFailedAttempts = 1 }
        await controller.handleUtterance("still no",
                                         suspended: Self.filterSuspended,
                                         candidates: Self.tonys,
                                         surface: "Tony")
        // After bail: counter zeroed, followUp routes to rest (preferredRestState .idle).
        #expect(sm.context.disambiguationFailedAttempts == 0)
        if case .active(.speaking(let response, .rest(let rest))) = sm.currentState {
            #expect(response.text == ResponseTemplateRegistry.disambiguationExit)
            #expect(rest == .idle)
        } else {
            Issue.record("expected .speaking with .rest followUp, got \(sm.currentState)")
        }
    }
}
