// IntentAnchors.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Anchor phrases the embedding-based classifier scores utterances against.
/// Each `Intent` carries a small catalog of canonical examples; the
/// classifier picks the intent whose closest anchor sits nearest the
/// utterance vector. Adding anchors broadens recall; removing them
/// tightens precision. Phrases are written in lowercase, contractions
/// allowed, no punctuation. Day 1 set per PLAN.md and D29.
enum IntentAnchors {

    /// The Day 1 catalog: every intent the classifier may emit, keyed by
    /// `Intent`, with the anchor phrases it scores against.
    static let catalog: [(Intent, [String])] = [
        (.summary, [
            "what's on my plate",
            "what do i have today",
            "what's going on",
            "give me a summary",
            "summarize my day",
            "the rundown",
            "anything new",
            "check in with me",
            "what's the status",
            "where do i stand",
            "what's up",
            "give me my brief",
            "what's my next meeting",
            "when's my next meeting",
            "what's coming up next",
            "what's next on my calendar",
            "do i have any chats",
            "any chats",
            "what chats do i have",
            "any teams messages"
        ]),

        (.filter, [
            "anything from tony",
            "any from sarah",
            "what about bob",
            "from john",
            "anything from anyone important",
            "anything from outside the company",
            "messages from liz today",
            "what's there from tony",
            "did i hear from stephanie",
            "anything about the project",
            "do i have any messages from tony",
            "do i have any emails from tony",
            "are there any messages from tony",
            "are there any emails from tony",
            "how many emails from tony",
            "how many emails do i have from tony",
            "count the emails from tony",
            "any emails from tony",
            "anything from microsoft security",
            "anything from microsoft 365 message center"
        ]),

        (.refresh, [
            "check again",
            "refresh",
            "any new",
            "look again",
            "is there anything else now",
            "update",
            "new emails",
            "fetch again",
            "anything fresh"
        ]),

        (.repeatLast, [
            "say that again",
            "repeat",
            "what was that",
            "say it again",
            "i missed that",
            "one more time",
            "could you repeat",
            "say again"
        ]),

        (.stop, [
            "stop",
            "be quiet",
            "shush",
            "enough",
            "cancel that",
            "never mind",
            "stop talking",
            "quiet"
        ]),

        (.help, [
            "help",
            "what can i say",
            "what can i do",
            "what do you know",
            "how does this work",
            "what are my options",
            "give me some examples",
            "what should i ask"
        ]),

        (.open, [
            "open tony's email",
            "open my next meeting",
            "open my chat with sarah",
            "show me tony's email",
            "open it in outlook",
            "go to my calendar",
            "pull up bob's email",
            "take me to teams",
            "open the meeting",
            "open emails from tony",
            "open my email from tony",
            "open the email from sarah"
        ]),

        (.exit, [
            "done",
            "thanks",
            "thank you",
            "bye",
            "goodbye",
            "exit",
            "that's all",
            "that's it",
            "i'm done"
        ]),

        (.settings, [
            "settings",
            "options",
            "preferences",
            "configuration",
            "open settings",
            "voice settings",
            "change settings"
        ]),

        (.yes, [
            "yes",
            "yeah",
            "yep",
            "go ahead",
            "do it",
            "confirm",
            "absolutely",
            "please do",
            "sounds good",
            "sure"
        ]),

        (.no, [
            "no",
            "nope",
            "cancel",
            "leave it",
            "skip it",
            "don't",
            "not now",
            "leave them alone"
        ]),

        (.ordinalSelection, [
            "the first",
            "first one",
            "number one",
            "number two",
            "the second",
            "second one",
            "the third",
            "third one",
            "the last one",
            "the latest"
        ]),

        // D19 in-scope-unsupported sub-categories. Each redirects to a
        // different touch path, so each gets its own anchor pool.

        (.inScopeUnsupported(.readContent), [
            "read me tony's email",
            "what does tony's email say",
            "read it",
            "read the email aloud",
            "read the body",
            "what's in the message",
            "read the chat",
            "read what tony wrote"
        ]),

        (.inScopeUnsupported(.summarizeContent), [
            "summarize tony's email",
            "give me the gist of bob's email",
            "summarize the chat",
            "tldr tony's email",
            "what's the email about",
            "shorten that email for me"
        ]),

        (.inScopeUnsupported(.analyzeContent), [
            "is this important",
            "what's it about",
            "is bob's email urgent",
            "should i read this",
            "anything urgent in there",
            "is the meeting important"
        ]),

        (.inScopeUnsupported(.voiceReply), [
            "reply to tony",
            "tell sarah i'll be there",
            "respond to bob",
            "send sarah a message",
            "write back to tony",
            "compose an email to liz"
        ]),

        (.inScopeUnsupported(.listBrowse), [
            "show me all my emails",
            "list everything",
            "what else is there",
            "browse my inbox",
            "show me everything",
            "go through them one by one",
            "let me see all of them"
        ]),

        // D18 out-of-scope probes. The classifier mostly detects
        // out-of-scope by absence of in-scope signal (low best score across
        // every category above), but a small probe pool gives the embedding
        // matcher something concrete to push against for common queries
        // outside the bounded scope.

        (.outOfScope, [
            "what's the weather",
            "play music",
            "set a timer",
            "turn off the lights",
            "what's the news",
            "tell me a joke",
            "remind me to call mom",
            "what's the time in tokyo",
            "translate this",
            "do a math problem"
        ])
    ]

    /// All anchors as a flat sequence, paired with their owning intent.
    /// The classifier embeds each anchor once at startup and caches the
    /// resulting vector for subsequent distance scoring.
    static var flattened: [(Intent, String)] {
        catalog.flatMap { (intent, phrases) in phrases.map { (intent, $0) } }
    }
}
