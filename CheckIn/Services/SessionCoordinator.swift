// SessionCoordinator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UIKit
import os

/// Translates `StateMachine` transitions into service side effects. The
/// state machine stays free of service dependencies; the coordinator owns
/// the consequence side: start the recognizer on entry to listening, stop
/// the synthesizer on exit from speaking, fetch the summary on entry to
/// active, and so on.
///
/// Phase 5 mic-only slice: the coordinator logs every transition and
/// (in a later slice) drives `SpeechService.startListening` / `cancel`.
/// Phase 6 onward adds TTS, GraphClient, and intent routing dispatch.
@MainActor
final class SessionCoordinator {
    private let stateMachine: StateMachine
    private let speechService: any SpeechService
    private let ttsService: any TTSService
    private let audioController: AudioSessionController
    private let summaryService: any SummaryService
    private let intentClassifier: any IntentClassifier
    private let rankedClassifier: (any RankedIntentClassifier)?
    private let responseGenerator: any ResponseGenerator
    private let entityMatcher: any EntityMatcher
    private let utteranceLog: any UtteranceLog

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var ttsEventTask: Task<Void, Never>?

    init(stateMachine: StateMachine,
         speechService: any SpeechService,
         ttsService: any TTSService,
         audioController: AudioSessionController,
         summaryService: any SummaryService,
         intentClassifier: any IntentClassifier,
         responseGenerator: any ResponseGenerator,
         entityMatcher: any EntityMatcher,
         utteranceLog: any UtteranceLog) {
        self.stateMachine = stateMachine
        self.speechService = speechService
        self.ttsService = ttsService
        self.audioController = audioController
        self.summaryService = summaryService
        self.intentClassifier = intentClassifier
        self.rankedClassifier = intentClassifier as? RankedIntentClassifier
        self.responseGenerator = responseGenerator
        self.entityMatcher = entityMatcher
        self.utteranceLog = utteranceLog
    }

    /// Begin consuming the state machine's transition stream, the
    /// speech service's transcript stream, and the TTS event stream.
    /// Idempotent so SwiftUI's `.task` firing twice during view
    /// reattachment doesn't spawn duplicate consumers.
    func start() {
        guard transitionTask == nil else { return }
        let transitions = stateMachine.transitions
        let transcripts = speechService.transcripts
        let ttsEvents = ttsService.events

        // The SwiftUI panel only sees the state machine; route its
        // selection / cancel events through these closures so the
        // coordinator owns the resume side without a view back-pointer.
        stateMachine.onCandidateSelected = { [weak self] candidate in
            self?.resumeDisambiguation(with: candidate)
        }
        stateMachine.onDisambiguationCancelled = { [weak self] in
            self?.cancelDisambiguation()
        }

        transitionTask = Task { [weak self] in
            for await event in transitions {
                guard let self else { break }
                await self.handle(event)
            }
        }

        transcriptTask = Task { [weak self] in
            for await update in transcripts {
                guard let self else { break }
                await self.handle(update)
            }
        }

        ttsEventTask = Task { [weak self] in
            for await event in ttsEvents {
                guard let self else { break }
                await self.handle(tts: event)
            }
        }
    }

    func stop() {
        stateMachine.onCandidateSelected = nil
        stateMachine.onDisambiguationCancelled = nil
        transitionTask?.cancel()
        transcriptTask?.cancel()
        ttsEventTask?.cancel()
        transitionTask = nil
        transcriptTask = nil
        ttsEventTask = nil
    }

    private func handle(_ event: TransitionEvent) async {
        logger.debug("saw: \(String(describing: event.from)) -> \(String(describing: event.to))")
        #if DEBUG
        // Mirror to stdout so `devicectl process launch --console` shows
        // transitions over SSH. Debug-only so Release stays clean.
        print("[coordinator] \(event.from) -> \(event.to)")
        #endif

        // Speaking-state side effects run before listening's so the synth
        // is stopped cleanly ahead of any session category swap. The synth
        // is per-utterance now, so a swap mid-utterance only impacts that
        // single utterance, but stopping first is still the right order.
        // D8 barge-in (auto-cut when VAD detects user speech mid-utterance)
        // is deferred past v1.
        switch (event.from, event.to) {
        case (_, .active(.speaking(let response, _))):
            audioController.configure(for: .speaking)
            do {
                try ttsService.speak(response.text)
            } catch {
                logger.error("tts.speak failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("[coordinator] tts.speak failed: \(error.localizedDescription)")
                #endif
                stateMachine.transition(to: .active(.idle))
            }
        case (.active(.speaking), _):
            if ttsService.isSpeaking {
                ttsService.stop()
            }
        default:
            break
        }

        switch (event.from, event.to) {
        case (.active(.idle), .active(.listening)),
             (.active(.speaking), .active(.listening)),
             (.active(.disambiguating), .active(.listening)),
             (.active(.confirming), .active(.listening)):
            await beginListening()
        case (.active(.speaking), .active(.disambiguating)):
            // Auto-listen for the disambig answer in conversation mode.
            // Tap-to-talk leaves the recognizer off; the user taps the mic
            // to voice-pick or taps a candidate. The disambig branch in
            // handle(_ update:) is already wired to route the next final
            // transcript to handleDisambiguationUtterance.
            if stateMachine.preferredRestState == .listening {
                await beginListening()
            }
        case (.active(.disambiguating), _):
            // Conversation mode left the recognizer running in
            // .disambiguating. Exits to .listening fall through the case
            // above and reuse the implicit teardown inside startListening.
            // Every other exit (resumeDisambiguation → .processing,
            // cancelDisambiguation → .idle for tap-to-talk) needs an
            // explicit cancel here. No-op when the recognizer isn't live.
            if speechService.isListening {
                speechService.cancel()
            }
        case (.active(.listening), .active(.processing)):
            // User signaled "I'm done speaking." Finalize the recognizer;
            // the final transcript will arrive shortly via the transcripts
            // stream and update DialogContext.lastUtterance.
            speechService.stopListening()
        case (.active(.listening), _):
            // Any other exit from listening (back to idle, app backgrounded,
            // error path) is a cancel — discard the partial transcript.
            speechService.cancel()
        default:
            break
        }

        // Audio session deactivates on entry to rest-without-mic states.
        // Speaking, listening, disambiguating, confirming, and processing
        // all hold an active session; idle/help/settings release it.
        switch event.to {
        case .active(.idle), .active(.helpDisplayed), .active(.settingsDisplayed):
            audioController.configure(for: .inactive)
        default:
            break
        }

        // End-of-turn disambig sweep. Any rest-state entry clears
        // pendingDisambiguation and disambiguationFailedAttempts so transient
        // state can't leak into the next turn. Catches non-coordinator exits
        // (deep-link tap from SummaryView while the panel is up, TTS-throw
        // recovery into .idle from either the initial prompt or a retry
        // prompt). Bail and resume retain their pre-transition clears because
        // both route through .speaking, and handle(tts:) treats a still-set
        // pendingDisambiguation as the signal to re-enter .disambiguating.
        switch event.to {
        case .active(.idle), .active(.listening):
            if stateMachine.context.pendingDisambiguation != nil
                || stateMachine.context.disambiguationFailedAttempts != 0 {
                stateMachine.updateContext {
                    $0.pendingDisambiguation = nil
                    $0.disambiguationFailedAttempts = 0
                }
            }
        default:
            break
        }

        // Earcons per D13: fire on entry to a state category, not on
        // intra-category transitions (processing(.thinking) shifting to
        // processing(.speakingPlaceholder) is one processing visit, not
        // two). Routed through the audio controller so each plays under
        // the phase's category — silent during speaking, bypassed during
        // listening/confirming/disambiguating. Fire-and-forget.
        if isListening(event.to) && !isListening(event.from) {
            audioController.play(.listening)
        }
        if isProcessing(event.to) && !isProcessing(event.from) {
            audioController.play(.thinking)
        }
        if isConfirming(event.to) && !isConfirming(event.from) {
            audioController.play(.confirmation)
        }
    }

    private func needsSummary(_ intent: Intent) -> Bool {
        switch intent {
        case .summary, .filter, .refresh: return true
        case .reply, .join, .timeQuery: return true
        default: return false
        }
    }

    private func isListening(_ state: DialogState) -> Bool {
        if case .active(.listening) = state { return true }
        return false
    }

    private func isProcessing(_ state: DialogState) -> Bool {
        if case .active(.processing) = state { return true }
        return false
    }

    private func isConfirming(_ state: DialogState) -> Bool {
        if case .active(.confirming) = state { return true }
        return false
    }

    private func handle(_ update: TranscriptUpdate) async {
        logger.debug("transcript: \(update.text, privacy: .public) (final=\(update.isFinal))")
        #if DEBUG
        print("[transcript] \"\(update.text)\" final=\(update.isFinal)")
        #endif

        guard update.isFinal else { return }

        // A transcript arriving while disambiguating means the user is
        // voice-picking a candidate, not starting a fresh intent turn.
        if case .active(.disambiguating(let suspended, let candidates))
            = stateMachine.currentState {
            await handleDisambiguationUtterance(update.text,
                                                suspended: suspended,
                                                candidates: candidates)
            return
        }

        // Auto-finalize: in tap-to-talk the UI tap moved the machine to
        // .processing before the recognizer stopped, so by the time the
        // final transcript arrives we're already there. In conversation
        // mode the recognizer's natural isFinal fires while the machine
        // is still .listening — drive it forward here so the rest of the
        // turn's logic runs identically to tap-to-talk.
        if case .active(.listening) = stateMachine.currentState {
            stateMachine.transition(to: .active(.processing(.thinking)))
        }

        let context = stateMachine.context
        let classified = intentClassifier.classify(
            utterance: update.text,
            context: context
        )
        let ranking = rankedClassifier?.rank(utterance: update.text,
                                             context: context) ?? []

        // Fetch fresh data for intents that need it before generating
        // the spoken response. `.summary` and `.filter` both reference
        // the data directly; `.refresh` populates the context so the
        // user's next ask picks it up (per 5.2 decision: empty spoken
        // ack on refresh, summary on next turn).
        if needsSummary(classified.intent) {
            #if DEBUG
            print("[summary] fetching for intent=\(classified.intent)")
            #endif
            let summary = await summaryService.fetchSummary()
            stateMachine.updateContext { $0.summary = summary }
            #if DEBUG
            let m = summary.meeting != nil ? "meeting" : "no-meeting"
            print("[summary] fetched: emails=\(summary.emails.count) chats=\(summary.chats.count) \(m) emailErr=\(summary.emailError ?? "nil") chatErr=\(summary.chatError ?? "nil")")
            #endif
        }

        let resolution = resolveSender(intent: classified.intent,
                                       text: update.text)

        let response: SpokenResponse
        let returnTo: RestState

        switch resolution {
        case .needsDisambiguation(let surface, let candidates):
            let suspended = SuspendedIntent(utterance: update.text,
                                            intent: "filter")
            let pending = PendingDisambiguation(suspendedIntent: suspended,
                                                surface: surface,
                                                candidates: candidates)
            stateMachine.updateContext { $0.pendingDisambiguation = pending }
            let text = ResponseTemplateRegistry.disambiguationPrompt(
                heardSurface: surface, candidates: candidates)
            response = SpokenResponse(text: text, category: .disambiguation)
            returnTo = stateMachine.preferredRestState
            #if DEBUG
            print("[disambig] prompt surface=\(surface) candidates=\(candidates.map { $0.label })")
            #endif

        case .unknown(let name):
            let text = ResponseTemplateRegistry.filterUnknownSender(name)
            response = SpokenResponse(text: text, category: .answer)
            returnTo = stateMachine.preferredRestState
            #if DEBUG
            print("[filter] unknown sender name=\(name)")
            #endif

        case .resolved(let sender):
            let baseResponse = responseGenerator.generate(
                for: classified,
                utterance: update.text,
                resolvedSender: sender,
                context: stateMachine.context
            )
            let result = await resolveSideEffects(
                classified: classified,
                utterance: update.text,
                baseResponse: baseResponse,
                context: stateMachine.context
            )
            response = result.0
            returnTo = result.1
        }

        await utteranceLog.record(
            utterance: update.text,
            classified: classified,
            ranking: ranking,
            response: response
        )

        stateMachine.recordTurn(
            user: update.text,
            system: response.text,
            category: response.category
        )

        logger.info("intent: \(String(describing: classified.intent), privacy: .public) confidence=\(classified.confidence)")
        #if DEBUG
        print("[intent] \(classified.intent) confidence=\(classified.confidence)")
        print("[response] \"\(response.text)\" category=\(response.category)")
        #endif

        if case .active(.processing) = stateMachine.currentState {
            if response.text.isEmpty {
                // Silent-by-design intents (.stop, .open on a successful
                // deep-link route) return straight to the rest state.
                // AVSpeechSynthesizer fires no delegate callbacks for an
                // empty utterance, so routing through .speaking would
                // strand the state machine there.
                stateMachine.transition(to: dialogState(forRest: returnTo))
            } else {
                stateMachine.transition(
                    to: .active(.speaking(response: response, returnTo: returnTo))
                )
            }
        }
    }

    // MARK: - Sender resolution (5.3b)

    /// Three-way fork over the `.filter` resolution: one canonical (fall
    /// through to the existing narrowing path), multiple (suspend the turn
    /// and disambiguate), zero with a "from <X>" surface (the user named
    /// someone we couldn't tag — answer to that, don't silently fall back).
    private enum SenderResolution {
        case resolved(String?)
        case unknown(name: String)
        case needsDisambiguation(surface: String, candidates: [Candidate])
    }

    private func resolveSender(intent: Intent, text: String) -> SenderResolution {
        guard case .filter = intent else { return .resolved(nil) }
        let matches = entityMatcher.match(text: text,
                                          domain: .person,
                                          context: stateMachine.context)
        // Reduce to distinct canonicals — NLTagger may return the same
        // person via surface + first-name fallback; dedupe before counting.
        var seen = Set<String>()
        let distinct: [String] = matches.compactMap {
            seen.insert($0.canonical).inserted ? $0.canonical : nil
        }

        if distinct.count > 1 {
            let surface = matches.first?.surface ?? text
            let candidates = distinct.map { Candidate(label: $0, entityRef: $0) }
            return .needsDisambiguation(surface: surface, candidates: candidates)
        }
        if let only = distinct.first {
            return .resolved(only)
        }
        if let name = extractFromName(text) {
            return .unknown(name: name)
        }
        return .resolved(nil)
    }

    /// Pull a "from <Name>" surface out of an utterance the matcher
    /// didn't tag. Conservative — anchored to known terminators so a
    /// long unrelated utterance doesn't sweep up extra tokens.
    private func extractFromName(_ text: String) -> String? {
        let pattern = #"\bfrom\s+([A-Za-z][A-Za-z'\- ]*?)(?:\s*[.?!,]|\s*\bin\b|\s*\babout\b|\s*$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2 else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespaces)
        if captured.isEmpty { return nil }
        return captured
            .split(separator: " ")
            .map { word -> String in
                let first = word.prefix(1).uppercased()
                let rest = word.dropFirst().lowercased()
                return first + rest
            }
            .joined(separator: " ")
    }

    // MARK: - Disambiguation resume / cancel / voice path (5.3b)

    /// User picked a candidate (touch tap or — once listening is wired —
    /// a voice match). Reconstruct the filter intent at full confidence and
    /// run the normal speaking flow.
    func resumeDisambiguation(with candidate: Candidate) {
        guard case .active(.disambiguating(let suspended, _))
                = stateMachine.currentState else { return }

        stateMachine.updateContext {
            $0.pendingDisambiguation = nil
            $0.disambiguationFailedAttempts = 0
        }
        stateMachine.transition(to: .active(.processing(.thinking)))

        Task { [weak self] in
            guard let self else { return }
            await self.completeFilterTurn(utterance: suspended.utterance,
                                          sender: candidate.entityRef)
        }
    }

    /// User cancelled disambiguation (touch Cancel button or mic-tap
    /// per the 5.3b brief). Silent return to rest — the absence of
    /// speech is the acknowledgment, mirroring `.stop`. The rest-entry
    /// sweep in `handle(_:)` clears pendingDisambiguation.
    func cancelDisambiguation() {
        let rest = dialogState(forRest: stateMachine.preferredRestState)
        stateMachine.transition(to: rest)
        #if DEBUG
        print("[disambig] cancelled")
        #endif
    }

    private func completeFilterTurn(utterance: String, sender: String) async {
        let classified = ClassifiedIntent(intent: .filter, confidence: 1.0)
        let baseResponse = responseGenerator.generate(
            for: classified,
            utterance: utterance,
            resolvedSender: sender,
            context: stateMachine.context
        )
        let returnTo = stateMachine.preferredRestState

        await utteranceLog.record(
            utterance: utterance,
            classified: classified,
            ranking: [],
            response: baseResponse
        )
        stateMachine.recordTurn(
            user: utterance,
            system: baseResponse.text,
            category: baseResponse.category
        )

        #if DEBUG
        print("[disambig] resumed sender=\(sender)")
        print("[response] \"\(baseResponse.text)\" category=\(baseResponse.category)")
        #endif

        if case .active(.processing) = stateMachine.currentState {
            if baseResponse.text.isEmpty {
                stateMachine.transition(to: dialogState(forRest: returnTo))
            } else {
                stateMachine.transition(to: .active(.speaking(response: baseResponse,
                                                              returnTo: returnTo)))
            }
        }
    }

    private func handleDisambiguationUtterance(_ text: String,
                                               suspended: SuspendedIntent,
                                               candidates: [Candidate]) async {
        let lower = text.lowercased()

        // Cancel surfaces — silent return to rest. Wider than just .stop
        // anchors so users have natural exit phrasings.
        let cancelTerms = ["never mind", "cancel", "stop", "forget it", "skip it"]
        if cancelTerms.contains(where: { lower.contains($0) }) {
            cancelDisambiguation()
            return
        }

        // Ordinal first ("the first one", "number two").
        let ordinals = entityMatcher.match(text: text,
                                           domain: .ordinal,
                                           context: stateMachine.context)
        if let ord = ordinals.first,
           let index = Int(ord.canonical),
           index >= 1, index <= candidates.count {
            resumeDisambiguation(with: candidates[index - 1])
            return
        }

        // Canonical / partial canonical match. Matches if the utterance
        // contains the full label OR any word from the label longer than
        // two characters — catches "Tony Jones" → "jones" and "Smith"
        // alike, but doesn't trip on stopwords.
        if let chosen = candidates.first(where: { cand in
            let labelLower = cand.label.lowercased()
            if lower.contains(labelLower) { return true }
            return labelLower.split(separator: " ").contains {
                $0.count > 2 && lower.contains($0)
            }
        }) {
            resumeDisambiguation(with: chosen)
            return
        }

        // No match — count the miss and either retry or bail.
        stateMachine.updateContext { $0.disambiguationFailedAttempts += 1 }
        let misses = stateMachine.context.disambiguationFailedAttempts
        let surface = stateMachine.context.pendingDisambiguation?.surface
            ?? suspended.utterance

        if misses >= 2 {
            let response = SpokenResponse(
                text: ResponseTemplateRegistry.disambiguationExit,
                category: .answer)
            stateMachine.updateContext {
                $0.pendingDisambiguation = nil
                $0.disambiguationFailedAttempts = 0
            }
            await utteranceLog.record(
                utterance: text,
                classified: ClassifiedIntent(intent: .unknown, confidence: 0.0),
                ranking: [],
                response: response)
            stateMachine.recordTurn(user: text,
                                    system: response.text,
                                    category: response.category)
            #if DEBUG
            print("[disambig] bail after \(misses) misses")
            #endif
            stateMachine.transition(to: .active(.speaking(
                response: response,
                returnTo: stateMachine.preferredRestState)))
            return
        }

        // Retry — re-stash pending so speaking-finish lands back in
        // .disambiguating, and speak the retry prompt.
        let pending = PendingDisambiguation(suspendedIntent: suspended,
                                            surface: surface,
                                            candidates: candidates)
        stateMachine.updateContext { $0.pendingDisambiguation = pending }
        let prompt = ResponseTemplateRegistry.disambiguationRetry(
            heardSurface: surface, candidates: candidates)
        let response = SpokenResponse(text: prompt, category: .disambiguation)
        await utteranceLog.record(
            utterance: text,
            classified: ClassifiedIntent(intent: .unknown, confidence: 0.0),
            ranking: [],
            response: response)
        stateMachine.recordTurn(user: text,
                                system: response.text,
                                category: response.category)
        #if DEBUG
        print("[disambig] retry (miss \(misses))")
        #endif
        stateMachine.transition(to: .active(.speaking(
            response: response,
            returnTo: stateMachine.preferredRestState)))
    }

    /// Apply per-intent side effects after the response is generated.
    /// `.open` resolves the entity and fires the deep link; `.exit` forces a
    /// return to `.idle` so a conversation-mode session ends cleanly. The
    /// pair `(response, returnTo)` lets the caller record what was actually
    /// spoken and route the state machine to the right rest state.
    private func resolveSideEffects(classified: ClassifiedIntent,
                                    utterance: String,
                                    baseResponse: SpokenResponse,
                                    context: DialogContext) async -> (SpokenResponse, RestState) {
        let defaultRest = stateMachine.preferredRestState

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
    private struct OpenOutcome {
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

    // MARK: - Reply (Phase C)

    /// Resolve a `.reply` turn: pull the named sender from scope, find
    /// their latest unread message (or an ordinal-selected one), and
    /// hand Outlook a compose URL with `to` and `Re:` subject pre-filled.
    /// Outlook iOS doesn't expose a per-message-id reply scheme, so this
    /// is the closest the documented compose surface gets to "reply to
    /// message N." The user lands inside an unaddressed reply they can
    /// finish in Outlook.
    private func handleReply(utterance: String, context: DialogContext) async -> OpenOutcome {
        let emails = context.summary?.emails ?? []
        let matches = entityMatcher.match(text: utterance,
                                          domain: .person,
                                          context: context)
        if matches.isEmpty {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.replyNoSender,
                category: .answer))
        }

        // Distinct canonicals first — fall back to ambiguity refusal when
        // the matcher tagged two different real people. The disambig
        // surface from 5.3b is wired for `.filter`, not `.reply`; the
        // simpler "be more specific" answer keeps reply terse for v1.
        var seen = Set<String>()
        let distinct: [String] = matches.compactMap {
            seen.insert($0.canonical).inserted ? $0.canonical : nil
        }
        if distinct.count > 1 {
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openAmbiguous,
                category: .answer))
        }
        let canonical = distinct[0]
        let candidates = emails.filter {
            $0.from.localizedCaseInsensitiveCompare(canonical) == .orderedSame
        }
        guard !candidates.isEmpty else {
            let surface = matches.first?.surface ?? canonical
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
            let surface = matches.first?.surface ?? canonical
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

        let surface = matches.first?.surface ?? email.from
        let opened = await openURL(url)
        if opened.spoken != nil {
            // openURL only sets a spoken response on failure; pass it through.
            return opened
        }
        return OpenOutcome(spoken: SpokenResponse(
            text: ResponseTemplateRegistry.replyOpening(to: surface),
            category: .answer))
    }

    // MARK: - Join meeting (Phase C)

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
        let ok = await UIApplication.shared.open(url)
        #if DEBUG
        print("[open] \(url.absoluteString) ok=\(ok)")
        #endif
        if !ok {
            logger.error("openURL failed for \(url.absoluteString, privacy: .public)")
            return OpenOutcome(spoken: SpokenResponse(
                text: ResponseTemplateRegistry.openLaunchFailed,
                category: .error))
        }
        return OpenOutcome(spoken: nil)
    }

    /// Drive the state machine out of `.speaking` when the synthesizer
    /// finishes or is cancelled. The `returnTo` carried in the speaking
    /// payload picks tap-to-talk's idle or conversation mode's listening.
    private func handle(tts event: TTSEvent) async {
        logger.debug("tts: \(String(describing: event))")
        #if DEBUG
        print("[tts] \(event)")
        #endif

        switch event {
        case .finished, .cancelled:
            if case .active(.speaking(_, let returnTo)) = stateMachine.currentState {
                // A disambiguation prompt (or its retry) was just spoken —
                // land in `.disambiguating` so the panel renders, instead
                // of dropping back to rest and losing the suspended intent.
                if let pending = stateMachine.context.pendingDisambiguation {
                    stateMachine.transition(to: .active(.disambiguating(
                        suspendedIntent: pending.suspendedIntent,
                        candidates: pending.candidates
                    )))
                } else {
                    stateMachine.transition(to: dialogState(forRest: returnTo))
                }
            }
        default:
            break
        }
    }

    private func dialogState(forRest rest: RestState) -> DialogState {
        switch rest {
        case .idle: return .active(.idle)
        case .listening: return .active(.listening)
        }
    }

    private func beginListening() async {
        let auth = await speechService.requestAuthorization()
        guard auth == .authorized else {
            logger.error("speech authorization not granted: \(String(describing: auth), privacy: .public)")
            #if DEBUG
            print("[coordinator] auth not granted: \(auth)")
            #endif
            stateMachine.transition(to: .active(.idle))
            return
        }
        audioController.configure(for: .listening)
        do {
            try speechService.startListening(contextualStrings: [])
        } catch {
            logger.error("startListening failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[coordinator] startListening failed: \(error.localizedDescription)")
            #endif
            stateMachine.transition(to: .active(.idle))
        }
    }
}
