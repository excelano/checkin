// IntentExecutorTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
import Foundation
@testable import CheckIn

/// Pins the per-intent side effects extracted from SessionCoordinator.
/// Tests inject a recording URL opener so the deep-link route can be
/// verified without going through UIApplication.
@MainActor
struct IntentExecutorTests {

    // MARK: - Fixtures

    private final class OpenerRecorder {
        var openedURLs: [URL] = []
        var ok: Bool = true

        func opener(_ url: URL) async -> Bool {
            openedURLs.append(url)
            return ok
        }
    }

    private static func makeExecutor(matcher: ScriptedEntityMatcher = .init(),
                                     opener: OpenerRecorder = OpenerRecorder())
        -> (IntentExecutor, OpenerRecorder) {
        let executor = IntentExecutor(
            entityMatcher: matcher,
            urlOpener: { url in await opener.opener(url) }
        )
        return (executor, opener)
    }

    /// Mutation tests need to inject a scripted dispatcher. Recorder
    /// captures each (kind, ids) pair the executor would have shipped to
    /// Graph and supplies a scriptable success / failure result.
    private final class MutationRecorder {
        struct Call: Equatable {
            let kind: MutationKind
            let ids: [String]
        }
        var calls: [Call] = []
        var result: Result<Void, Error> = .success(())

        func dispatcher(_ kind: MutationKind, _ ids: [String]) async -> Result<Void, Error> {
            calls.append(Call(kind: kind, ids: ids))
            return result
        }
    }

    private static func makeMutationExecutor(matcher: ScriptedEntityMatcher = .init(),
                                             recorder: MutationRecorder = MutationRecorder())
        -> (IntentExecutor, MutationRecorder) {
        let executor = IntentExecutor(
            entityMatcher: matcher,
            urlOpener: { _ in true },
            mutationDispatcher: { kind, ids in await recorder.dispatcher(kind, ids) }
        )
        return (executor, recorder)
    }

    private static func meeting(joinUrl: String?) -> Meeting {
        Meeting(subject: "Standup", organizer: "Tony",
                location: "", start: Date(), end: Date(),
                isOnline: true, attendees: [], joinUrl: joinUrl)
    }

    private static func email(from: String, subject: String = "Hi",
                              fromAddress: String = "tony@example.com",
                              received: Date = Date()) -> Email {
        Email(id: UUID().uuidString, subject: subject, from: from,
              fromAddress: fromAddress, preview: "", received: received)
    }

    private static func chat(from: String, webUrl: String?) -> ChatMessage {
        ChatMessage(chatID: "c", topic: "t", from: from,
                    preview: "", sent: Date(), webUrl: webUrl)
    }

    private static func summary(meeting: Meeting? = nil,
                                emails: [Email] = [],
                                chats: [ChatMessage] = []) -> CheckInSummary {
        CheckInSummary(meeting: meeting, emails: emails, chats: chats,
                       emailError: nil, chatError: nil, teamsEnabled: true)
    }

    private static func context(with summary: CheckInSummary?) -> DialogContext {
        var ctx = DialogContext()
        ctx.summary = summary
        return ctx
    }

    private static func baseResponse() -> SpokenResponse {
        SpokenResponse(text: "", category: .answer)
    }

    private static func classified(_ intent: Intent) -> ClassifiedIntent {
        ClassifiedIntent(intent: intent, confidence: 1.0)
    }

    // MARK: - .exit forces idle

    @Test func exitForcesIdleEvenInConversationMode() async {
        let (executor, _) = Self.makeExecutor()
        let (_, rest) = await executor.resolveSideEffects(
            classified: Self.classified(.exit),
            utterance: "done",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: nil),
            defaultRest: .listening
        )
        #expect(rest == .idle)
    }

    // MARK: - non-executor intents pass baseResponse through

    @Test func nonHandledIntentReturnsBaseResponseAndDefaultRest() async {
        let (executor, opener) = Self.makeExecutor()
        let base = SpokenResponse(text: "Three unread.", category: .summary)
        let (response, rest) = await executor.resolveSideEffects(
            classified: Self.classified(.summary),
            utterance: "anything new",
            baseResponse: base,
            context: Self.context(with: Self.summary()),
            defaultRest: .listening
        )
        #expect(response.text == "Three unread.")
        #expect(rest == .listening)
        #expect(opener.openedURLs.isEmpty)
    }

    // MARK: - .open meeting

    @Test func openMeetingFiresCalendarDeepLinkWhenMeetingPresent() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(meeting: Self.meeting(joinUrl: nil))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my next meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.count == 1)
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
        // Silent success — base (empty) response passes through.
        #expect(response.text.isEmpty)
    }

    @Test func openMeetingSpeaksNoMeetingWhenAbsent() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my next meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary(meeting: nil)),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.openMeetingNone)
    }

    // MARK: - .open calendar

    @Test func openCalendarFiresCalendarDeepLink() async {
        let (executor, opener) = Self.makeExecutor()
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my calendar",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
    }

    // MARK: - .open email

    @Test func openInboxFiresInboxDeepLinkWhenNoSenderNamed() async {
        let (executor, opener) = Self.makeExecutor()
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open my inbox",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookInbox)
    }

    @Test func openEmailFromKnownSenderFiresInbox() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open email from tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [Self.email(from: "Tony Smith")])
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open email from tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookInbox)
    }

    @Test func openEmailFromUnknownSenderSpeaksNotFound() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open email from tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        // Summary contains a different sender; tony has no email.
        let summary = Self.summary(emails: [Self.email(from: "Alice Smith")])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open email from tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.openNotFound("tony"))
    }

    // MARK: - .reply

    @Test func replyWithoutSenderSpeaksReplyNoSender() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary()),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.replyNoSender)
    }

    @Test func replyToKnownSenderFiresReplyDeepLinkAndSpeaksOpening() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["reply to tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [
            Self.email(from: "Tony Smith",
                       subject: "Lunch?",
                       fromAddress: "tony@example.com")
        ])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply to tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        let expectedURL = DeepLinkService.outlookReply(to: "tony@example.com",
                                                       subject: "Lunch?")
        #expect(opener.openedURLs.first == expectedURL)
        #expect(response.text == ResponseTemplateRegistry.replyOpening(to: "tony"))
    }

    // MARK: - .reply (disambig resume path, preferredSender)

    @Test func resolveReplyWithPreferredSenderFiresReplyDeepLink() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(emails: [
            Self.email(from: "Tony Smith",
                       subject: "Lunch?",
                       fromAddress: "tony@example.com")
        ])
        let (response, rest) = await executor.resolveReply(
            utterance: "reply to tony",
            preferredSender: "Tony Smith",
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        let expectedURL = DeepLinkService.outlookReply(to: "tony@example.com",
                                                       subject: "Lunch?")
        #expect(opener.openedURLs.first == expectedURL)
        #expect(response.text == ResponseTemplateRegistry.replyOpening(to: "Tony Smith"))
        #expect(rest == .idle)
    }

    @Test func resolveReplyWithPreferredSenderSkipsMatcher() async {
        // Matcher returns nothing for the utterance — proves resolveReply
        // does NOT re-match and uses the preferredSender directly.
        let matcher = ScriptedEntityMatcher()
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [
            Self.email(from: "Tony Smith",
                       fromAddress: "tony@example.com")
        ])
        let (response, _) = await executor.resolveReply(
            utterance: "reply to tony",
            preferredSender: "Tony Smith",
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.count == 1)
        #expect(response.text == ResponseTemplateRegistry.replyOpening(to: "Tony Smith"))
    }

    @Test func resolveReplyWithPreferredSenderAndNoMatchingEmailSpeaksUnknownSender() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(emails: [Self.email(from: "Alice Smith")])
        let (response, _) = await executor.resolveReply(
            utterance: "reply to tony",
            preferredSender: "Tony Smith",
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.replyUnknownSender("Tony Smith"))
    }

    @Test func replyToSenderWithNoEmailSpeaksUnknownSender() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["reply to tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let summary = Self.summary(emails: [Self.email(from: "Alice Smith")])
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.reply),
            utterance: "reply to tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.replyUnknownSender("tony"))
    }

    // MARK: - .join

    @Test func joinWithNoMeetingSpeaksNoneToJoin() async {
        let (executor, opener) = Self.makeExecutor()
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: Self.summary(meeting: nil)),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.isEmpty)
        #expect(response.text == ResponseTemplateRegistry.meetingNoneToJoin)
    }

    @Test func joinWithJoinUrlFiresPassthroughDeepLink() async {
        let (executor, opener) = Self.makeExecutor()
        let joinUrl = "https://teams.microsoft.com/l/meetup-join/abc"
        let summary = Self.summary(meeting: Self.meeting(joinUrl: joinUrl))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join the meeting",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.passthrough(joinUrl))
        #expect(response.text.isEmpty)
    }

    @Test func joinWithoutJoinUrlFallsBackToCalendar() async {
        let (executor, opener) = Self.makeExecutor()
        let summary = Self.summary(meeting: Self.meeting(joinUrl: nil))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.outlookCalendar)
        #expect(response.text == ResponseTemplateRegistry.meetingNoJoinLink)
    }

    @Test func joinFailureSpeaksJoinFailed() async {
        let opener = OpenerRecorder()
        opener.ok = false
        let (executor, _) = Self.makeExecutor(opener: opener)
        let joinUrl = "https://teams.microsoft.com/l/meetup-join/abc"
        let summary = Self.summary(meeting: Self.meeting(joinUrl: joinUrl))
        let (response, _) = await executor.resolveSideEffects(
            classified: Self.classified(.join),
            utterance: "join",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(response.text == ResponseTemplateRegistry.meetingJoinFailed)
    }

    // MARK: - .open chat

    @Test func openChatWithMatchingTeamsUrlFiresPassthrough() async {
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["open chat with tony"] = [
            EntityMatch(surface: "tony", canonical: "Tony Smith", confidence: 0.9)
        ]
        let (executor, opener) = Self.makeExecutor(matcher: matcher)
        let webUrl = "https://teams.microsoft.com/l/chat/abc"
        let summary = Self.summary(chats: [Self.chat(from: "Tony Smith", webUrl: webUrl)])
        _ = await executor.resolveSideEffects(
            classified: Self.classified(.open),
            utterance: "open chat with tony",
            baseResponse: Self.baseResponse(),
            context: Self.context(with: summary),
            defaultRest: .idle
        )
        #expect(opener.openedURLs.first == DeepLinkService.passthrough(webUrl))
    }

    // MARK: - Mutations

    @Test func handleMutationWithPreferredSenderBuildsPending() async {
        let (executor, recorder) = Self.makeMutationExecutor()
        let target = Self.email(from: "Tony Smith")
        let summary = Self.summary(emails: [target])
        let outcome = executor.handleMutation(
            kind: .markRead,
            utterance: "mark tony's email as read",
            context: Self.context(with: summary),
            preferredSender: "Tony Smith"
        )
        #expect(outcome.pending != nil)
        #expect(outcome.refusal == nil)
        #expect(outcome.pending?.kind == .markRead)
        #expect(outcome.pending?.targets == [target.id])
        #expect(outcome.pending?.description.contains("Tony Smith") == true)
        #expect(recorder.calls.isEmpty) // no Graph call yet
    }

    @Test func handleMutationRefusesWithNoSender() async {
        let (executor, _) = Self.makeMutationExecutor()
        let summary = Self.summary(emails: [Self.email(from: "Tony Smith")])
        let outcome = executor.handleMutation(
            kind: .delete,
            utterance: "delete this",
            context: Self.context(with: summary)
        )
        #expect(outcome.pending == nil)
        #expect(outcome.refusal?.text == ResponseTemplateRegistry.mutationNoSender)
    }

    @Test func handleMutationRefusesWhenNamedSenderHasNoEmail() async {
        // handleMutation names the surface (what the user said) back to
        // the user, not the canonical. The matcher resolved "bob" to
        // "Bob Jones" but no Bob Jones is in the unread set, so the
        // refusal echoes the surface form for honesty about what was
        // heard versus what was understood.
        var matcher = ScriptedEntityMatcher()
        matcher.personForText["flag bob's email"] = [
            EntityMatch(surface: "bob", canonical: "Bob Jones", confidence: 0.9)
        ]
        let (executor, _) = Self.makeMutationExecutor(matcher: matcher)
        let summary = Self.summary(emails: [Self.email(from: "Tony Smith")])
        let outcome = executor.handleMutation(
            kind: .flag,
            utterance: "flag bob's email",
            context: Self.context(with: summary)
        )
        #expect(outcome.pending == nil)
        #expect(outcome.refusal?.text.contains("bob") == true)
    }

    @Test func handleMutationPicksLatestWhenSenderHasMany() async {
        // Multiple emails from same sender → mutation targets the first
        // (Graph $orderby receivedDateTime desc puts latest at index 0).
        let (executor, _) = Self.makeMutationExecutor()
        let latest = Self.email(from: "Tony Smith")
        let older = Self.email(from: "Tony Smith")
        let summary = Self.summary(emails: [latest, older])
        let outcome = executor.handleMutation(
            kind: .delete,
            utterance: "delete tony's email",
            context: Self.context(with: summary),
            preferredSender: "Tony Smith"
        )
        #expect(outcome.pending?.targets == [latest.id])
        #expect(outcome.pending?.targets.count == 1)
    }

    @Test func executeMutationSuccessReturnsConfirmationCategory() async {
        let recorder = MutationRecorder()
        recorder.result = .success(())
        let (executor, _) = Self.makeMutationExecutor(recorder: recorder)
        let pending = PendingMutation(kind: .markRead,
                                      targets: ["msg-1"],
                                      description: "mark the latest email from Tony as read")
        let response = await executor.executeMutation(pending)
        #expect(response.category == .confirmation)
        #expect(response.text == ResponseTemplateRegistry.successAnnouncement(pending.description))
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first == MutationRecorder.Call(kind: .markRead, ids: ["msg-1"]))
    }

    @Test func executeMutationFailureReturnsErrorCategory() async {
        struct StubError: Error {}
        let recorder = MutationRecorder()
        recorder.result = .failure(StubError())
        let (executor, _) = Self.makeMutationExecutor(recorder: recorder)
        let pending = PendingMutation(kind: .delete,
                                      targets: ["msg-2"],
                                      description: "delete the latest email from Tony")
        let response = await executor.executeMutation(pending)
        #expect(response.category == .error)
        #expect(response.text == ResponseTemplateRegistry.mutationFailed)
        #expect(recorder.calls.count == 1)
    }

    @Test func executeMutationDispatchesAllTargets() async {
        // Bulk variants ship many IDs in a single dispatcher call. Phase
        // 6 doesn't create those yet, but the executor must pass through
        // whatever `targets` carries.
        let recorder = MutationRecorder()
        let (executor, _) = Self.makeMutationExecutor(recorder: recorder)
        let pending = PendingMutation(kind: .bulkMarkRead,
                                      targets: ["a", "b", "c"],
                                      description: "mark three emails as read")
        _ = await executor.executeMutation(pending)
        #expect(recorder.calls.first?.ids == ["a", "b", "c"])
    }
}
