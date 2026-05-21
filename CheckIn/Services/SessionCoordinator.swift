// SessionCoordinator.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UIKit
import os

/// Translates `StateMachine` transitions into service side effects. The
/// state machine stays free of service dependencies; the coordinator owns
/// the consequence side: configure the audio session, start the recognizer
/// on entry to listening, run the dialog layer, drive `TTSService`, fetch
/// from `GraphClient` when needed, and route disambiguation.
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
    private let disambiguationController: DisambiguationController
    private let intentExecutor: IntentExecutor
    private let transitionRouter = TransitionRouter()

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "coordinator")

    private var transitionTask: Task<Void, Never>?
    private var transcriptTask: Task<Void, Never>?
    private var ttsEventTask: Task<Void, Never>?

    /// In-flight summary fetch, if any. Held so that an intent dispatched
    /// during the cold-boot load (or a stale-cache refresh) can await the
    /// same fetch instead of racing or duplicating it.
    private var pendingFetch: Task<Void, Never>?

    init(stateMachine: StateMachine,
         speechService: any SpeechService,
         ttsService: any TTSService,
         audioController: AudioSessionController,
         summaryService: any SummaryService,
         intentClassifier: any IntentClassifier,
         responseGenerator: any ResponseGenerator,
         entityMatcher: any EntityMatcher,
         utteranceLog: any UtteranceLog,
         mutationDispatcher: @escaping (MutationKind, [String]) async -> Result<Void, Error>
            = { _, _ in .success(()) }) {
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
        self.intentExecutor = IntentExecutor(
            entityMatcher: entityMatcher,
            urlOpener: { url in
                await UIApplication.shared.open(url)
            },
            mutationDispatcher: mutationDispatcher
        )
        self.disambiguationController = DisambiguationController(
            stateMachine: stateMachine,
            responseGenerator: responseGenerator,
            entityMatcher: entityMatcher,
            intentExecutor: intentExecutor,
            utteranceLog: utteranceLog
        )
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
        stateMachine.onConfirmationAccepted = { [weak self] in
            self?.acceptConfirmation()
        }
        stateMachine.onConfirmationCancelled = { [weak self] in
            self?.cancelConfirmation()
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
        stateMachine.onConfirmationAccepted = nil
        stateMachine.onConfirmationCancelled = nil
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

        // Account boundary: a transition into .signedOut means the user
        // tapped Sign Out (or auth fell off). Drop per-account caches so
        // the next signed-in account starts clean. Cancel any in-flight
        // fetch so its result can't land in the next session's context
        // — the Task itself bails on `Task.isCancelled` before writing.
        if case .signedOut = event.to {
            summaryService.reset()
            pendingFetch?.cancel()
            pendingFetch = nil
        }

        // Sign-in (or cold-boot from .signedOut into .active). Kick off
        // an initial summary load so the first user turn has data
        // without racing the cache. Intent dispatches that arrive before
        // the fetch returns will await this same Task via the TTL gate.
        if case .signedOut = event.from, case .active = event.to {
            startSummaryFetch(reason: "boot")
        }

        let effects = transitionRouter.sideEffects(
            from: event.from,
            to: event.to,
            preferredRestState: stateMachine.preferredRestState
        )
        for effect in effects {
            await apply(effect)
        }
    }

    private func apply(_ effect: TransitionRouter.SideEffect) async {
        switch effect {
        case .configureAudio(let phase):
            // Speaking / inactive configures: log a failure but let the
            // turn continue. The synth still runs under whichever category
            // stayed active, and the next phase change will retry.
            // Listening configures don't reach this path — beginListening
            // does that one directly so it can bail to idle on failure.
            do {
                try audioController.configure(for: phase)
            } catch {
                logger.error("audio configure(\(String(describing: phase), privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("[coordinator] audio configure failed for \(phase): \(error.localizedDescription)")
                #endif
            }
        case .speak(let response):
            do {
                try ttsService.speak(response.text)
            } catch {
                logger.error("tts.speak failed: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                print("[coordinator] tts.speak failed: \(error.localizedDescription)")
                #endif
                stateMachine.transition(to: .active(.idle))
            }
        case .stopTTSIfSpeaking:
            if ttsService.isSpeaking {
                ttsService.stop()
            }
        case .beginListening:
            await beginListening()
        case .stopListening:
            speechService.stopListening()
        case .cancelListening:
            speechService.cancel()
        case .cancelListeningIfActive:
            if speechService.isListening {
                speechService.cancel()
            }
        case .playEarcon(let earcon):
            audioController.play(earcon)
        case .resetDisambigFailedAttempts:
            if stateMachine.context.disambiguationFailedAttempts != 0 {
                stateMachine.updateContext {
                    $0.disambiguationFailedAttempts = 0
                }
            }
        }
    }

    private func needsSummary(_ intent: Intent) -> Bool {
        switch intent {
        case .summary, .filter, .refresh: return true
        case .reply, .join, .timeQuery: return true
        case .markRead, .flag, .delete: return true
        default: return false
        }
    }

    /// True when the intent is a single-email mutation. Bulk variants
    /// will join this set in Phase 7.
    private func isMutation(_ intent: Intent) -> Bool {
        switch intent {
        case .markRead, .flag, .delete: return true
        default: return false
        }
    }

    private func mutationKind(_ intent: Intent) -> MutationKind? {
        switch intent {
        case .markRead: return .markRead
        case .flag:     return .flag
        case .delete:   return .delete
        default:        return nil
        }
    }

    /// Start a summary fetch if one isn't already in flight. The Task
    /// stamps `context.summaryFetchedAt` so the TTL gate can read freshness
    /// off the context rather than tracking it here. Coalesces — repeat
    /// calls while a fetch is pending are no-ops. `reason` tags the
    /// debug print so cold-boot / stale / refresh fetches can be told
    /// apart in the console.
    private func startSummaryFetch(reason: String) {
        if pendingFetch != nil { return }
        pendingFetch = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("[summary] fetching reason=\(reason)")
            #endif
            let summary = await self.summaryService.fetchSummary()
            // Sign-out during the fetch cancels the Task. Bail before
            // writing context so the next session starts clean.
            if Task.isCancelled { return }
            self.stateMachine.updateContext {
                $0.summary = summary
                $0.summaryFetchedAt = Date()
            }
            #if DEBUG
            let m = summary.meeting != nil ? "meeting" : "no-meeting"
            print("[summary] fetched: emails=\(summary.emails.count) chats=\(summary.chats.count) \(m) emailErr=\(summary.emailError ?? "nil") chatErr=\(summary.chatError ?? "nil")")
            #endif
            self.pendingFetch = nil
        }
    }

    /// Block on the in-flight fetch if there is one. Concurrent intent
    /// dispatches share the same Task; whoever runs the gate first
    /// triggers the fetch and the rest await its result.
    private func awaitPendingFetch() async {
        await pendingFetch?.value
    }

    /// Start a fetch (coalesced with any in-flight one) and block until
    /// it completes. Used by `.refresh` and by the stale-cache branch
    /// of the TTL gate.
    private func fetchSummaryBlocking(reason: String) async {
        startSummaryFetch(reason: reason)
        await pendingFetch?.value
    }

    /// True if the cached summary is missing or older than the configured
    /// refresh interval. Returns false when the user has chosen "Never"
    /// (interval == nil) and a summary already exists — that's the
    /// explicit opt-out from auto-refresh.
    private func isSummaryStale() -> Bool {
        guard let fetchedAt = stateMachine.context.summaryFetchedAt else { return true }
        guard let interval = AppStorageKey.summaryRefreshInterval else { return false }
        return Date().timeIntervalSince(fetchedAt) > interval
    }

    private func handle(_ update: TranscriptUpdate) async {
        logger.debug("transcript: \(update.text) (final=\(update.isFinal))")
        #if DEBUG
        print("[transcript] \"\(update.text)\" final=\(update.isFinal)")
        #endif

        guard update.isFinal else { return }

        // A transcript arriving while disambiguating means the user is
        // voice-picking a candidate, not starting a fresh intent turn.
        if case .active(.disambiguating(let suspended, let candidates, let surface))
            = stateMachine.currentState {
            await disambiguationController.handleUtterance(update.text,
                                                           suspended: suspended,
                                                           candidates: candidates,
                                                           surface: surface)
            return
        }

        // A transcript arriving while confirming means the user is voice-
        // answering the yes/no, not starting a fresh intent turn. Cheap
        // lexical match — the classifier's `.yes`/`.no` anchors live on
        // the same vocabulary but routing them through it here would
        // require carrying intent state across an extra hop for no gain.
        if case .active(.confirming) = stateMachine.currentState {
            handleConfirmationUtterance(update.text)
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

        // TTL gate. `.refresh` always re-fetches — that's the explicit
        // user ask. Other summary-reading intents (.summary, .filter,
        // .reply, .join, .timeQuery) use the cache when fresh and
        // re-fetch only when stale. Intents that don't read the summary
        // (.help, .stop, .settings, .open of meeting/calendar without a
        // person, etc.) skip the gate entirely. Any dispatch that lands
        // while the cold-boot load is still in flight awaits the same
        // Task rather than racing or duplicating it.
        if classified.intent == .refresh {
            await fetchSummaryBlocking(reason: "refresh")
        } else if needsSummary(classified.intent) {
            await awaitPendingFetch()
            if isSummaryStale() {
                await fetchSummaryBlocking(reason: "stale")
            }
        }

        let resolution = resolveSender(intent: classified.intent,
                                       text: update.text)

        let response: SpokenResponse
        let followUp: SpeakingFollowUp

        switch resolution {
        case .needsDisambiguation(let surface, let candidates):
            let origin: DisambigOrigin
            if let kind = mutationKind(classified.intent) {
                origin = .mutation(kind)
            } else if classified.intent == .reply {
                origin = .reply
            } else {
                origin = .filter
            }
            let suspended = SuspendedIntent(utterance: update.text,
                                            origin: origin)
            let pending = PendingDisambiguation(suspendedIntent: suspended,
                                                surface: surface,
                                                candidates: candidates)
            let text = ResponseTemplateRegistry.disambiguationPrompt(
                heardSurface: surface, candidates: candidates)
            response = SpokenResponse(text: text, category: .disambiguation)
            followUp = .disambiguate(pending)
            #if DEBUG
            print("[disambig] prompt origin=\(origin) surface=\(surface) candidates=\(candidates.map { $0.label })")
            #endif

        case .unknown(let name):
            let text: String
            if classified.intent == .reply {
                text = ResponseTemplateRegistry.replyUnknownSender(name)
            } else if isMutation(classified.intent) {
                text = ResponseTemplateRegistry.openNotFound(name)
            } else {
                text = ResponseTemplateRegistry.filterUnknownSender(name)
            }
            response = SpokenResponse(text: text, category: .answer)
            followUp = .rest(stateMachine.preferredRestState)
            #if DEBUG
            print("[\(classified.intent)] unknown sender name=\(name)")
            #endif

        case .resolved(let sender):
            if let kind = mutationKind(classified.intent) {
                let outcome = intentExecutor.handleMutation(
                    kind: kind,
                    utterance: update.text,
                    context: stateMachine.context,
                    preferredSender: sender
                )
                if let pending = outcome.pending {
                    let promptText = ResponseTemplateRegistry.confirmationPrompt(
                        pending.description)
                    response = SpokenResponse(text: promptText,
                                              category: .confirmation)
                    followUp = .confirm(pending)
                } else {
                    response = outcome.refusal
                        ?? SpokenResponse(text: "", category: .answer)
                    followUp = .rest(stateMachine.preferredRestState)
                }
                #if DEBUG
                if let p = outcome.pending {
                    print("[mutation] pending kind=\(p.kind) targets=\(p.targets) description=\"\(p.description)\"")
                } else {
                    print("[mutation] refused kind=\(kind)")
                }
                #endif
            } else {
                let baseResponse = responseGenerator.generate(
                    for: classified,
                    utterance: update.text,
                    resolvedSender: sender,
                    context: stateMachine.context
                )
                let result = await intentExecutor.resolveSideEffects(
                    classified: classified,
                    utterance: update.text,
                    baseResponse: baseResponse,
                    context: stateMachine.context,
                    defaultRest: stateMachine.preferredRestState
                )
                response = result.0
                followUp = .rest(result.1)
            }
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
                // strand the state machine there. Silent paths only occur
                // when followUp is .rest — disambig prompts always speak.
                if case .rest(let restState) = followUp {
                    switch restState {
                    case .idle: stateMachine.transition(to: .active(.idle))
                    case .listening: stateMachine.transition(to: .active(.listening))
                    }
                }
            } else {
                stateMachine.transition(
                    to: .active(.speaking(response: response, followUp: followUp))
                )
            }
        }
    }

    // MARK: - Sender resolution

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
        switch intent {
        case .filter, .reply, .markRead, .flag, .delete:
            break
        default:
            return .resolved(nil)
        }
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

    // MARK: - Disambiguation (delegated)

    /// View-layer entry point. The panel only sees the `StateMachine`, so
    /// `start()` wires the panel's selection callback to this method, which
    /// forwards to `DisambiguationController`.
    func resumeDisambiguation(with candidate: Candidate) {
        disambiguationController.resume(with: candidate)
    }

    /// View-layer entry point for cancel (touch Cancel or mic-tap). Same
    /// rationale as `resumeDisambiguation`.
    func cancelDisambiguation() {
        disambiguationController.cancel()
    }

    // MARK: - Confirmation

    /// User said yes to the pending mutation (touch Yes, voice .yes, or
    /// equivalent). Routes the mutation through `IntentExecutor` →
    /// the injected dispatcher → Microsoft Graph. The success or failure
    /// SpokenResponse comes back from the executor; success plays the
    /// confirmation earcon ahead of the announcement.
    func acceptConfirmation() {
        guard case .active(.confirming(let mutation))
                = stateMachine.currentState else { return }
        let pending = mutation
        // Transition to processing while the Graph call is in flight so
        // the UI shows the thinking indicator rather than holding the
        // confirming panel through the round-trip.
        stateMachine.transition(to: .active(.processing(.thinking)))
        Task { [weak self] in
            guard let self else { return }
            let response = await self.intentExecutor.executeMutation(pending)
            if response.category == .confirmation {
                self.audioController.play(.confirmation)
            }
            self.stateMachine.recordTurn(user: "yes",
                                         system: response.text,
                                         category: response.category)
            if case .active(.processing) = self.stateMachine.currentState {
                self.stateMachine.transition(to: .active(.speaking(
                    response: response,
                    followUp: .rest(self.stateMachine.preferredRestState))))
            }
        }
    }

    /// User said no / cancel. No Graph call regardless of phase; just a
    /// short ack and rest.
    func cancelConfirmation() {
        guard case .active(.confirming) = stateMachine.currentState else { return }
        let response = SpokenResponse(
            text: ResponseTemplateRegistry.confirmationCancelled,
            category: .confirmation)
        stateMachine.recordTurn(user: "no",
                                system: response.text,
                                category: response.category)
        stateMachine.transition(to: .active(.speaking(
            response: response,
            followUp: .rest(stateMachine.preferredRestState))))
    }

    /// Voice answer path while in `.confirming`. Conversation mode keeps
    /// the recognizer hot through the prompt, so this fires when the user
    /// speaks "yes" or "no" instead of tapping. Anything else is ignored —
    /// the user can re-speak. (Two-miss bail like disambig is overkill
    /// here: the touch affordances are always present.)
    private func handleConfirmationUtterance(_ text: String) {
        let lower = text.lowercased()
        let yesTerms = ["yes", "yeah", "yep", "confirm", "do it", "go ahead", "sure"]
        let noTerms = ["no", "nope", "cancel", "stop", "nevermind", "never mind", "forget it"]
        if yesTerms.contains(where: { lower.contains($0) }) {
            acceptConfirmation()
        } else if noTerms.contains(where: { lower.contains($0) }) {
            cancelConfirmation()
        }
        // Ambiguous utterance — leave the machine where it is. The panel
        // stays up and the recognizer cycles for another try.
    }

    /// Drive the state machine out of `.speaking` when the synthesizer
    /// finishes or is cancelled. The `followUp` carried in the speaking
    /// payload routes either to a rest state (tap-to-talk's idle,
    /// conversation mode's listening) or onward to `.disambiguating`
    /// when a disambig prompt just finished.
    private func handle(tts event: TTSEvent) async {
        logger.debug("tts: \(String(describing: event))")
        #if DEBUG
        print("[tts] \(event)")
        #endif

        switch event {
        case .finished, .cancelled:
            if let next = transitionRouter.nextStateAfterSpeaking(stateMachine.currentState) {
                stateMachine.transition(to: next)
            }
        default:
            break
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
        do {
            try audioController.configure(for: .listening)
        } catch {
            logger.error("audio configure for listening failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[coordinator] audio configure for listening failed: \(error.localizedDescription)")
            #endif
            stateMachine.transition(to: .active(.idle))
            return
        }
        do {
            try speechService.startListening()
        } catch {
            logger.error("startListening failed: \(error.localizedDescription, privacy: .public)")
            #if DEBUG
            print("[coordinator] startListening failed: \(error.localizedDescription)")
            #endif
            stateMachine.transition(to: .active(.idle))
        }
    }
}
