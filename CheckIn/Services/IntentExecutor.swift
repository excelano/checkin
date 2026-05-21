// IntentExecutor.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import os

/// Owns the post-classification side effects for the intents that need to
/// fire a deep link, write to Microsoft Graph, or override the base spoken
/// response. `SessionCoordinator` calls `resolveSideEffects` after the
/// response generator builds its baseline; the executor either returns the
/// baseline unchanged, overrides it with an open/reply/join outcome, or
/// coerces the rest state for `.exit`. Mutations take a separate path
/// (`handleMutation` → `.confirming` → `executeMutation`) so every write
/// passes through the confirmation gate.
///
/// URL opening and Graph mutation are injected as closures so the
/// deep-link surface and the Graph write surface are testable without a
/// real `UIApplication` or `URLSession`.
@MainActor
final class IntentExecutor {
    private let entityMatcher: any EntityMatcher
    private let urlOpener: (URL) async -> Bool
    private let mutationDispatcher: (MutationKind, [String]) async -> Result<Void, Error>

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "executor")

    init(entityMatcher: any EntityMatcher,
         urlOpener: @escaping (URL) async -> Bool,
         mutationDispatcher: @escaping (MutationKind, [String]) async -> Result<Void, Error>
            = { _, _ in .success(()) }) {
        self.entityMatcher = entityMatcher
        self.urlOpener = urlOpener
        self.mutationDispatcher = mutationDispatcher
    }

    /// Apply per-intent side effects after the response is generated.
    /// `.open` resolves the entity and fires the deep link; `.exit` forces a
    /// return to `.idle` so a conversation-mode session ends cleanly. The
    /// pair `(response, returnTo)` lets the caller record what was actually
    /// spoken and route the state machine to the right rest state.
    func resolveSideEffects(classified: ClassifiedIntent,
                            utterance: String,
                            baseResponse: SpokenResponse,
                            context: DialogContext,
                            defaultRest: RestState) async -> (SpokenResponse, RestState) {
        switch classified.intent {
        case .open:
            let outcome = await handleOpen(utterance: utterance, context: context)
            return (outcome.spoken ?? baseResponse, defaultRest)
        case .reply:
            let outcome = await handleReply(utterance: utterance, context: context)
            return (outcome.spoken ?? baseResponse, defaultRest)
        case .join:
            let outcome = await handleJoin(context: context)
            return (outcome.spoken ?? baseResponse, defaultRest)
        case .exit:
            // Even in conversation mode, "done" ends the session — drop
            // back to idle so the recognizer doesn't auto-restart.
            return (baseResponse, .idle)
        default:
            return (baseResponse, defaultRest)
        }
    }

    /// What `handleOpen` returns: either a deep-link was fired (silent
    /// success — `spoken` stays nil so the empty base response carries
    /// through) or a spoken explanation overrides the base response.
    struct OpenOutcome {
        let spoken: SpokenResponse?
    }

    private enum OpenTarget {
        case meeting   // "open my next meeting" — only if one exists
        case calendar  // "open my calendar" — always launches the calendar app
        case chat
        case email
    }

    private func openTarget(in utterance: String) -> OpenTarget {
        let lower = utterance.lowercased()
        if lower.contains("meeting") || lower.contains("event")
            || lower.contains("appointment") {
            return .meeting
        }
        if lower.contains("calendar") {
            return .calendar
        }
        if lower.contains("chat") || lower.contains("teams") {
            return .chat
        }
        return .email
    }

    private func handleOpen(utterance: String, context: DialogContext) async -> OpenOutcome {
        switch openTarget(in: utterance) {
        case .meeting:
            return await openMeeting(context: context)
        case .calendar:
            return await openCalendar()
        case .chat:
            return await openChat(utterance: utterance, context: context)
        case .email:
            return await openEmail(utterance: utterance, context: context)
        }
    }

    private func openMeeting(context: DialogContext) async -> OpenOutcome {
        guard context.summary?.meeting != nil else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openMeetingNone,
                category: .answer))
        }
        guard let url = DeepLinkService.outlookCalendar else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        return await openURL(url)
    }

    private func openCalendar() async -> OpenOutcome {
        guard let url = DeepLinkService.outlookCalendar else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        return await openURL(url)
    }

    private func openChat(utterance: String, context: DialogContext) async -> OpenOutcome {
        let matches = entityMatcher.match(text: utterance, domain: .person, context: context)
        let chats = context.summary?.chats ?? []
        let resolved = chats.filter { chat in
            matches.contains { match in
                chat.from.localizedCaseInsensitiveCompare(match.canonical) == .orderedSame
            }
        }
        if resolved.count > 1 {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openAmbiguous,
                category: .answer))
        }
        if let single = resolved.first {
            if let urlString = single.webUrl, let url = DeepLinkService.passthrough(urlString) {
                return await openURL(url)
            }
            // Fallback: generic Teams launch when Graph didn't surface a
            // passthrough URL. The user lands on the chat list rather than
            // the specific chat.
            if let url = DeepLinkService.teams {
                return await openURL(url)
            }
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        let name = matches.first?.surface ?? "anyone"
        return OpenOutcome(spoken: SpokenResponse(
            text: ResponseTemplateRegistry.openNotFound(name),
            category: .answer))
    }

    private func openEmail(utterance: String, context: DialogContext) async -> OpenOutcome {
        let emails = context.summary?.emails ?? []
        let matches = entityMatcher.match(text: utterance, domain: .person, context: context)
        let ordinalMatches = entityMatcher.match(text: utterance, domain: .ordinal, context: context)
        let ordinal = ordinalMatches.first.flatMap { resolveOrdinalSelector($0.canonical) }

        // Bare "open my inbox" / "open my email" — no person mentioned, just
        // launch Outlook on the inbox.
        if matches.isEmpty {
            if let url = DeepLinkService.outlookInbox {
                return await openURL(url)
            }
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }

        let resolved = emails.filter { email in
            matches.contains { match in
                email.from.localizedCaseInsensitiveCompare(match.canonical) == .orderedSame
            }
        }
        if resolved.isEmpty {
            let name = matches.first?.surface ?? "that"
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openNotFound(name),
                category: .answer))
        }
        // Ordinal + sender composition. "Open the latest email from Tony"
        // and "open the first email from Tony" both reduce a multi-sender
        // result to a single message before the ambiguity check below
        // would otherwise refuse. The deep link still goes to the inbox
        // (Outlook iOS doesn't expose a per-message scheme), but the
        // resolved email confirms there's something for the user to read
        // when they land.
        if ordinal != nil {
            // Filtered email list is already sorted by Graph $orderby
            // receivedDateTime desc — index 0 is the latest. "First" in
            // this dialog means first-as-shown rather than chronologically
            // earliest, matching how the user perceives the unread list.
            // Pick the email or report nothing-from-that-position.
            if pickByOrdinal(resolved, selector: ordinal!) == nil {
                let name = matches.first?.surface ?? "that"
                return OpenOutcome(spoken: SpokenResponse(
                    text: ResponseTemplateRegistry.openNotFound(name),
                    category: .answer))
            }
            if let url = DeepLinkService.outlookInbox {
                return await openURL(url)
            }
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        let distinctSenders = Set(resolved.map { $0.from })
        if distinctSenders.count > 1 {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openAmbiguous,
                category: .answer))
        }
        if let url = DeepLinkService.outlookInbox {
            return await openURL(url)
        }
        return OpenOutcome(spoken: SpokenResponse(
            text: ResponseTemplateRegistry.openLaunchFailed,
            category: .error))
    }

    private enum OrdinalSelector {
        case latest
        case index(Int)  // 1-based position into the resolved list
    }

    private func resolveOrdinalSelector(_ canonical: String) -> OrdinalSelector? {
        if canonical == "latest" { return .latest }
        if let n = Int(canonical), n >= 1 { return .index(n) }
        return nil
    }

    private func pickByOrdinal<T>(_ list: [T], selector: OrdinalSelector) -> T? {
        switch selector {
        case .latest:
            return list.first
        case .index(let n):
            let idx = n - 1
            return list.indices.contains(idx) ? list[idx] : nil
        }
    }

    // MARK: - Reply

    /// Resolve a `.reply` turn: pull the named sender from scope, find
    /// their latest unread message (or an ordinal-selected one), and
    /// hand Outlook a compose URL with `to` and `Re:` subject pre-filled.
    /// Outlook iOS doesn't expose a per-message-id reply scheme, so this
    /// is the closest the documented compose surface gets to "reply to
    /// message N." The user lands inside an unaddressed reply they can
    /// finish in Outlook.
    ///
    /// When called from the disambig resume path `preferredSender` is the
    /// canonical the user picked; matching is skipped and that canonical
    /// is used directly. The first-turn dispatch leaves it nil and the
    /// matcher runs as before. Multi-sender disambiguation is now
    /// pre-filtered by `SessionCoordinator.resolveSender`, so this method
    /// no longer sees that case.
    private func handleReply(utterance: String,
                             context: DialogContext,
                             preferredSender: String? = nil) async -> OpenOutcome {
        let emails = context.summary?.emails ?? []

        let canonical: String
        let surface: String

        if let pref = preferredSender {
            canonical = pref
            surface = pref
        } else {
            let matches = entityMatcher.match(text: utterance,
                                              domain: .person,
                                              context: context)
            if matches.isEmpty {
                return OpenOutcome(spoken: SpokenResponse(
                    text: ResponseTemplateRegistry.replyNoSender,
                    category: .answer))
            }
            var seen = Set<String>()
            let distinct: [String] = matches.compactMap {
                seen.insert($0.canonical).inserted ? $0.canonical : nil
            }
            canonical = distinct[0]
            surface = matches.first?.surface ?? canonical
        }

        let candidates = emails.filter {
            $0.from.localizedCaseInsensitiveCompare(canonical) == .orderedSame
        }
        guard !candidates.isEmpty else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.replyUnknownSender(surface),
                category: .answer))
        }

        let ordinalMatches = entityMatcher.match(text: utterance,
                                                 domain: .ordinal,
                                                 context: context)
        let ordinal = ordinalMatches.first.flatMap { resolveOrdinalSelector($0.canonical) }
        let chosen: Email?
        if let sel = ordinal {
            chosen = pickByOrdinal(candidates, selector: sel)
        } else {
            // Latest unread is the natural default for "reply to Tony".
            chosen = candidates.first
        }
        guard let email = chosen else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.replyUnknownSender(surface),
                category: .answer))
        }

        // The deep-link's `to` field needs a real SMTP address. Graph
        // returns it as `from.emailAddress.address` and we pass it through
        // on the model; the rare missing-address case falls through to
        // a calendar-style explanation so the user isn't dropped into
        // Outlook with an empty To field.
        guard !email.fromAddress.isEmpty,
              let url = DeepLinkService.outlookReply(to: email.fromAddress,
                                                     subject: email.subject) else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }

        let opened = await openURL(url)
        if opened.spoken != nil {
            // openURL only sets a spoken response on failure; pass it through.
            return opened
        }
        return OpenOutcome(spoken: SpokenResponse(
            text: ResponseTemplateRegistry.replyOpening(to: surface),
            category: .answer))
    }

    /// Disambig resume entry point. Skips the matcher and binds the
    /// caller-supplied canonical sender into the reply URL.
    func resolveReply(utterance: String,
                      preferredSender: String,
                      context: DialogContext,
                      defaultRest: RestState) async -> (SpokenResponse, RestState) {
        let outcome = await handleReply(utterance: utterance,
                                        context: context,
                                        preferredSender: preferredSender)
        let base = SpokenResponse(text: "", category: .answer)
        return (outcome.spoken ?? base, defaultRest)
    }

    // MARK: - Mutations

    /// What `handleMutation` returns: either a pending mutation ready to
    /// route through `.speaking(_, .confirm)` → `.confirming`, or a
    /// refusal that goes straight to `.speaking(_, .rest)`. Mirrors
    /// `OpenOutcome` but split because the success path here doesn't
    /// fire an immediate side effect — the write waits on the user's yes.
    struct MutationOutcome {
        let pending: PendingMutation?
        let refusal: SpokenResponse?
    }

    /// Build a `PendingMutation` from the utterance. Resolves the sender
    /// via the entity matcher, narrows the unread set to that sender,
    /// and picks the latest email as the target. Bulk variants land in
    /// Phase 7 with a different shape (filter-then-iterate). When called
    /// from the disambig resume path `preferredSender` is the canonical
    /// the user picked; matching is skipped.
    ///
    /// Returns a refusal when:
    /// - no sender extracts from the utterance (pronoun-only phrasings),
    /// - the named sender doesn't match anyone in the unread set,
    /// - the resolved email has no usable ID (shouldn't happen but guarded).
    func handleMutation(kind: MutationKind,
                        utterance: String,
                        context: DialogContext,
                        preferredSender: String? = nil) -> MutationOutcome {
        let emails = context.summary?.emails ?? []

        let canonical: String
        let surface: String

        if let pref = preferredSender {
            canonical = pref
            surface = pref
        } else {
            let matches = entityMatcher.match(text: utterance,
                                              domain: .person,
                                              context: context)
            if matches.isEmpty {
                // Pronoun-only utterance ("mark this as read"). The voice
                // surface doesn't yet carry a strong-enough referent for
                // safe mutations; ask for a sender instead of guessing.
                return MutationOutcome(
                    pending: nil,
                    refusal: SpokenResponse(
                        text: ResponseTemplateRegistry.mutationNoSender,
                        category: .answer))
            }
            var seen = Set<String>()
            let distinct: [String] = matches.compactMap {
                seen.insert($0.canonical).inserted ? $0.canonical : nil
            }
            canonical = distinct[0]
            surface = matches.first?.surface ?? canonical
        }

        let candidates = emails.filter {
            $0.from.localizedCaseInsensitiveCompare(canonical) == .orderedSame
        }
        guard let latest = candidates.first else {
            return MutationOutcome(
                pending: nil,
                refusal: SpokenResponse(
                    text: ResponseTemplateRegistry.openNotFound(surface),
                    category: .answer))
        }

        let description = ResponseTemplateRegistry.mutationDescription(
            kind: kind, sender: canonical)
        let pending = PendingMutation(kind: kind,
                                      targets: [latest.id],
                                      description: description)
        return MutationOutcome(pending: pending, refusal: nil)
    }

    /// Execute the confirmed mutation against Graph via the injected
    /// dispatcher. Success returns a `.confirmation`-category response
    /// with the success template; failure returns a generic `.error`
    /// (the underlying error rides in the debug log, not the speech).
    func executeMutation(_ mutation: PendingMutation) async -> SpokenResponse {
        let result = await mutationDispatcher(mutation.kind, mutation.targets)
        switch result {
        case .success:
            #if DEBUG
            print("[mutation] success kind=\(mutation.kind) targets=\(mutation.targets)")
            #endif
            return SpokenResponse(
                text: ResponseTemplateRegistry.successAnnouncement(mutation.description),
                category: .confirmation)
        case .failure(let error):
            logger.error("mutation failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[mutation] failed kind=\(mutation.kind) error=\(error.localizedDescription)")
            #endif
            return SpokenResponse(
                text: ResponseTemplateRegistry.mutationFailed,
                category: .error)
        }
    }

    // MARK: - Join meeting

    private func handleJoin(context: DialogContext) async -> OpenOutcome {
        guard let meeting = context.summary?.meeting else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.meetingNoneToJoin,
                category: .answer))
        }
        if let joinUrlStr = meeting.joinUrl,
           !joinUrlStr.isEmpty,
           let url = DeepLinkService.passthrough(joinUrlStr) {
            let opened = await openURL(url)
            if opened.spoken != nil {
                // Failed; openURL set its own error template. Override the
                // generic launch-failed with the join-specific one.
                return OpenOutcome(spoken: SpokenResponse(
                    text: ResponseTemplateRegistry.meetingJoinFailed,
                    category: .error))
            }
            return opened
        }
        // No join URL on this event — open the calendar so the user can
        // see what's actually scheduled and decide what to do.
        guard let calendarURL = DeepLinkService.outlookCalendar else {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        let opened = await openURL(calendarURL)
        if opened.spoken != nil {
            return opened
        }
        return OpenOutcome(spoken: SpokenResponse(
            text: ResponseTemplateRegistry.meetingNoJoinLink,
            category: .answer))
    }

    private func openURL(_ url: URL) async -> OpenOutcome {
        let ok = await urlOpener(url)
        #if DEBUG
        print("[open] \(url.absoluteString) ok=\(ok)")
        #endif
        if !ok {
            logger.error("openURL failed for \(url.absoluteString)")
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        return OpenOutcome(spoken: nil)
    }
}
