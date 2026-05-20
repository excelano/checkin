// PersonaResponseGenerator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Day 1 response generator per D15. Picks a phrasing from
/// `ResponseTemplateRegistry` based on the classified intent and the
/// current dialog context. Honors anti-repeat: never re-uses a refusal
/// or redirect phrasing that sits in the recent-phrasings window in
/// `DialogContext`. PERSONA.md governs the underlying strings.
struct PersonaResponseGenerator: ResponseGenerator {

    func generate(for intent: ClassifiedIntent,
                  utterance: String,
                  resolvedSender: String?,
                  context: DialogContext) -> SpokenResponse {
        switch intent.intent {
        case .summary:
            return summaryResponse(utterance: utterance, context: context)

        case .filter:
            return filterResponse(utterance: utterance,
                                  resolvedSender: resolvedSender,
                                  context: context)

        case .refresh:
            // The actual fetch is on the Graph layer; the spoken response
            // arrives on completion via `summary` or `errorNetwork`. The
            // immediate spoken acknowledgment is empty so the thinking
            // earcon carries the moment.
            return SpokenResponse(text: "", category: .answer)

        case .repeatLast:
            let last = context.lastSystemResponse ?? ""
            if last.isEmpty {
                return SpokenResponse(text: ResponseTemplateRegistry.nothingToRepeat,
                                      category: .answer)
            }
            return SpokenResponse(text: last, category: .answer)

        case .stop:
            return SpokenResponse(text: ResponseTemplateRegistry.stopAcknowledged,
                                  category: .answer)

        case .help:
            // The short variant plays first; "tell me more" extends to
            // long. The visual sheet always shows the full reference
            // regardless of voice variant.
            return SpokenResponse(text: ResponseTemplateRegistry.helpShort,
                                  category: .help)

        case .open:
            // The state machine triggers the deep-link via DeepLinkService;
            // the spoken response is empty so the route happens cleanly.
            return SpokenResponse(text: "", category: .answer)

        case .reply, .join:
            // Side-effect-driven: the coordinator's resolveSideEffects
            // either supplies the spoken explanation (no sender resolved,
            // no join URL, launch failure) or fires the deep-link silently.
            return SpokenResponse(text: "", category: .answer)

        case .timeQuery:
            return timeQueryResponse(context: context)

        case .exit:
            return SpokenResponse(text: ResponseTemplateRegistry.exitAcknowledged,
                                  category: .answer)

        case .settings:
            return SpokenResponse(text: ResponseTemplateRegistry.settingsOpened,
                                  category: .answer)

        case .yes, .no, .ordinalSelection:
            // Yes/no/ordinal flow inside disambiguating or confirming
            // states; the state machine resolves them and produces the
            // resulting summary / success / cancel spoken response. The
            // raw classification itself doesn't generate spoken output.
            return SpokenResponse(text: "", category: .answer)

        case .inScopeUnsupported(let kind):
            return redirectResponse(for: kind, context: context)

        case .outOfScope:
            return refusalResponse(context: context)

        case .unknown:
            return parseMissResponse(context: context)
        }
    }

    // MARK: - Summary

    private func summaryResponse(utterance: String, context: DialogContext) -> SpokenResponse {
        guard let summary = context.summary else {
            return SpokenResponse(text: ResponseTemplateRegistry.notFetched,
                                  category: .answer)
        }
        let text: String
        switch ResponseTemplateRegistry.detectDomain(utterance) {
        case .email:   text = ResponseTemplateRegistry.summaryEmailOnly(from: summary)
        case .chat:    text = ResponseTemplateRegistry.summaryChatOnly(from: summary)
        case .meeting: text = ResponseTemplateRegistry.summaryMeetingOnly(from: summary, utterance: utterance)
        case .all:     text = ResponseTemplateRegistry.summarySentence(from: summary)
        }
        return SpokenResponse(text: text, category: .summary)
    }

    /// `.filter` is implicitly email-domain for Day 1. Resolved sender
    /// wins (sender narrowing). Otherwise apply domain detection — the
    /// classifier sometimes routes plain "how many emails" to `.filter`
    /// rather than `.summary`, so the narrowing has to live on both
    /// paths to be reliable.
    private func filterResponse(utterance: String,
                                resolvedSender: String?,
                                context: DialogContext) -> SpokenResponse {
        guard let summary = context.summary else {
            return SpokenResponse(text: ResponseTemplateRegistry.notFetched,
                                  category: .answer)
        }
        if let sender = resolvedSender {
            let text = ResponseTemplateRegistry.summaryFilteredBySender(from: summary,
                                                                        matching: sender,
                                                                        utterance: utterance)
            return SpokenResponse(text: text, category: .summary)
        }
        let text: String
        switch ResponseTemplateRegistry.detectDomain(utterance) {
        case .email:   text = ResponseTemplateRegistry.summaryEmailOnly(from: summary)
        case .chat:    text = ResponseTemplateRegistry.summaryChatOnly(from: summary)
        case .meeting: text = ResponseTemplateRegistry.summaryMeetingOnly(from: summary, utterance: utterance)
        case .all:     text = ResponseTemplateRegistry.summarySentence(from: summary)
        }
        return SpokenResponse(text: text, category: .summary)
    }

    // MARK: - Time query (Phase C, D29)

    private func timeQueryResponse(context: DialogContext) -> SpokenResponse {
        guard let summary = context.summary else {
            return SpokenResponse(text: ResponseTemplateRegistry.notFetched,
                                  category: .answer)
        }
        guard let meeting = summary.meeting else {
            return SpokenResponse(text: ResponseTemplateRegistry.timeQueryNoMeeting,
                                  category: .answer)
        }
        let text = ResponseTemplateRegistry.timeQueryAnswer(for: meeting)
        return SpokenResponse(text: text, category: .answer)
    }

    // MARK: - D18 refusal (out-of-scope)

    private func refusalResponse(context: DialogContext) -> SpokenResponse {
        let phrase = pick(from: ResponseTemplateRegistry.refusals,
                          avoiding: context.recentRefusals)
        return SpokenResponse(text: phrase, category: .refusal)
    }

    // MARK: - D19 redirect (in-scope-unsupported)

    private func redirectResponse(for kind: UnsupportedKind,
                                  context: DialogContext) -> SpokenResponse {
        let pool: [String]
        switch kind {
        case .readContent: pool = ResponseTemplateRegistry.readContentRedirects
        case .summarizeContent: pool = ResponseTemplateRegistry.summarizeContentRedirects
        case .analyzeContent: pool = ResponseTemplateRegistry.analyzeContentRedirects
        case .voiceReply: pool = ResponseTemplateRegistry.voiceReplyRedirects
        case .listBrowse: pool = ResponseTemplateRegistry.listBrowseRedirects
        }
        let phrase = pick(from: pool, avoiding: context.recentRedirects)
        return SpokenResponse(text: phrase, category: .redirect)
    }

    // MARK: - Parse miss

    private func parseMissResponse(context: DialogContext) -> SpokenResponse {
        if context.repromptCount >= 2 {
            let phrase = ResponseTemplateRegistry.parseMissEscalated.randomElement()
                ?? ResponseTemplateRegistry.parseMissEscalated[0]
            return SpokenResponse(text: phrase, category: .error)
        }
        let phrase = ResponseTemplateRegistry.parseMiss.randomElement()
            ?? ResponseTemplateRegistry.parseMiss[0]
        return SpokenResponse(text: phrase, category: .error)
    }

    // MARK: - Picker

    /// Pick a phrasing not in the avoid list. If every phrasing is on the
    /// list, drop the oldest constraint and pick the first that wasn't a
    /// recent repeat. Random within the eligible set so two users don't
    /// always hear the same default.
    private func pick(from pool: [String], avoiding recent: [String]) -> String {
        let avoidSet = Set(recent)
        let eligible = pool.filter { !avoidSet.contains($0) }
        if let choice = eligible.randomElement() { return choice }
        // Pool fully covered by recents (rare; happens only when the user
        // hits the same category many turns in a row). Fall back to the
        // oldest line in the pool that isn't the most recent.
        let mostRecent = recent.last
        return pool.first { $0 != mostRecent } ?? pool[0]
    }
}
