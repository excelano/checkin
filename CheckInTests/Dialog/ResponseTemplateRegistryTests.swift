// ResponseTemplateRegistryTests.swift
// CheckInTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Testing
@testable import CheckIn

/// Pins the registry's pure-function surface. The pools themselves are
/// just static arrays of strings — the value-add tests are the
/// per-domain template builders and the anti-repeat picker behavior in
/// `PersonaResponseGenerator`, which is what callers actually see.
struct ResponseTemplateRegistryTests {

    // MARK: - Pool sanity

    @Test func refusalPoolNonEmpty() {
        #expect(!ResponseTemplateRegistry.refusals.isEmpty)
    }

    @Test func everyRedirectPoolIsPopulated() {
        #expect(!ResponseTemplateRegistry.readContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.summarizeContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.analyzeContentRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.voiceReplyRedirects.isEmpty)
        #expect(!ResponseTemplateRegistry.listBrowseRedirects.isEmpty)
    }

    // MARK: - Disambiguation prompts

    @Test func disambiguationPromptListsAllCandidates() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "tony.smith"),
            Candidate(label: "Tony Jones", entityRef: "tony.jones")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony"))
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Tony Jones"))
    }

    @Test func disambiguationPromptUsesOrSeparatorForTwo() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony Smith or Tony Jones"))
    }

    @Test func disambiguationPromptUsesOxfordForThreePlus() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b"),
            Candidate(label: "Tony Park", entityRef: "c")
        ]
        let text = ResponseTemplateRegistry.disambiguationPrompt(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(text.contains("Tony Smith, Tony Jones, or Tony Park"))
    }

    @Test func disambiguationRetryOmitsAmbiguityPreamble() {
        let candidates = [
            Candidate(label: "Tony Smith", entityRef: "a"),
            Candidate(label: "Tony Jones", entityRef: "b")
        ]
        let retry = ResponseTemplateRegistry.disambiguationRetry(
            heardSurface: "Tony", candidates: candidates
        )
        #expect(retry.contains("I missed that"))
        #expect(retry.contains("Tony Smith"))
        #expect(retry.contains("Tony Jones"))
    }

    // MARK: - Filter / open templates

    @Test func filterUnknownSenderNamesTheTokenBack() {
        let text = ResponseTemplateRegistry.filterUnknownSender("Microsoft")
        #expect(text.contains("Microsoft"))
        #expect(text.contains("inbox"))
    }

    @Test func openNotFoundMentionsRefresh() {
        let text = ResponseTemplateRegistry.openNotFound("Tony")
        #expect(text.contains("Tony"))
        #expect(text.contains("refresh") || text.contains("Refresh"))
    }

    // MARK: - Reply templates

    @Test func replyOpeningCallsOutOutlook() {
        let text = ResponseTemplateRegistry.replyOpening(to: "Tony Smith")
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Outlook"))
    }

    @Test func replyUnknownSenderNamesTheToken() {
        let text = ResponseTemplateRegistry.replyUnknownSender("Microsoft")
        #expect(text.contains("Microsoft"))
    }

    // MARK: - Domain detection

    @Test func detectDomainEmailWord() {
        #expect(ResponseTemplateRegistry.detectDomain("any new emails") == .email)
    }

    @Test func detectDomainChatWord() {
        #expect(ResponseTemplateRegistry.detectDomain("any teams chats") == .chat)
    }

    @Test func detectDomainMeetingWord() {
        #expect(ResponseTemplateRegistry.detectDomain("anything on my calendar") == .meeting)
    }

    @Test func detectDomainAmbiguousFallsToAll() {
        // 'meeting' and 'email' both hit → ambiguous → .all
        #expect(ResponseTemplateRegistry.detectDomain("emails and meetings") == .all)
    }

    @Test func detectDomainNoSignalFallsToAll() {
        #expect(ResponseTemplateRegistry.detectDomain("anything new") == .all)
    }

    // The "messages" token alone routes to Outlook (the dominant register
    // in M365 voice queries). Teams-flavored phrasings that contain
    // "messages" route to Teams; Outlook-flavored phrasings stay Outlook.

    @Test func detectDomainBareMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many messages do I have") == .email)
    }

    @Test func detectDomainEmailMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many email messages") == .email)
    }

    @Test func detectDomainUnreadMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("how many unread messages") == .email)
    }

    @Test func detectDomainNewMessagesPegToEmail() {
        #expect(ResponseTemplateRegistry.detectDomain("any new messages") == .email)
    }

    @Test func detectDomainChatMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many chat messages") == .chat)
    }

    @Test func detectDomainTeamsMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many teams messages") == .chat)
    }

    @Test func detectDomainPendingMessagesPegToChat() {
        #expect(ResponseTemplateRegistry.detectDomain("how many pending messages") == .chat)
    }

    // MARK: - Summary phrasing

    @Test func summarySentenceHandlesZeroUnread() {
        let summary = Fixtures.summary()
        let text = ResponseTemplateRegistry.summarySentence(from: summary)
        #expect(text.contains("No unread"))
    }

    @Test func summarySentenceSpellsTwoUnread() {
        let summary = Fixtures.summary(emails: [
            ("Tony Smith", "A"),
            ("Sarah Park", "B")
        ])
        let text = ResponseTemplateRegistry.summarySentence(from: summary)
        #expect(text.contains("Two unread"))
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Sarah Park"))
    }

    @Test func summaryFilteredBySenderEmptyMatch() {
        let summary = Fixtures.summary(emails: [("Tony Smith", "A")])
        let text = ResponseTemplateRegistry.summaryFilteredBySender(
            from: summary, matching: "Bob", utterance: "anything from bob"
        )
        #expect(text.contains("Bob"))
        #expect(text.lowercased().contains("nothing"))
    }

    @Test func summaryFilteredBySenderSingleMatch() {
        let summary = Fixtures.summary(emails: [
            ("Tony Smith", "Project update")
        ])
        let text = ResponseTemplateRegistry.summaryFilteredBySender(
            from: summary, matching: "Tony Smith", utterance: "any from tony"
        )
        #expect(text.contains("Tony Smith"))
        #expect(text.contains("Project update"))
    }
}
