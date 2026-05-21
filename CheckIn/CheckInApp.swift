// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import MSAL

@main
struct CheckInApp: App {
    @State private var authService: AuthService
    @State private var stateMachine: StateMachine
    private let coordinator: SessionCoordinator
    private let inboxActions: InboxActions

    init() {
        let auth = AuthService()
        let sm = StateMachine()
        // Hydrate the rest-state preference from AppStorage so a user who
        // chose Conversation in a prior session lands in .listening from
        // first turn instead of waiting for them to reopen Settings. Voice
        // disabled overrides conversation mode — no auto-arm of a hidden
        // mic.
        let storedMode = UserDefaults.standard.string(forKey: AppStorageKey.listeningMode) ?? "tapToTalk"
        let voiceOn = (UserDefaults.standard.object(forKey: AppStorageKey.voiceEnabled) as? Bool) ?? true
        sm.preferredRestState = (voiceOn && storedMode == "conversation") ? .listening : .idle
        let speech = AppleSpeechService()
        let tts = AppleTTSService()
        let earcons = AppleEarconPlayer()
        let audioController = AudioSessionController(earconPlayer: earcons)
        let graph = GraphClient(authService: auth, enableTeams: Constants.teamsEnabled)
        let summary = GraphSummaryService(graphClient: graph,
                                          teamsEnabled: Constants.teamsEnabled)
        let classifier: any IntentClassifier = NLEmbeddingIntentClassifier()
        let generator: any ResponseGenerator = PersonaResponseGenerator()
        let entityMatcher: any EntityMatcher = NLTaggerEntityMatcher()
        let utteranceLog: any UtteranceLog
        #if DEBUG
        utteranceLog = FileUtteranceLog()
        #else
        utteranceLog = NoOpUtteranceLog()
        #endif
        _authService = State(initialValue: auth)
        _stateMachine = State(initialValue: sm)
        // Bind mutation kinds to GraphClient methods. The dispatcher
        // closure is invoked from `IntentExecutor.executeMutation` after
        // the user confirms; the executor itself stays free of the
        // Graph dependency for testability.
        let mutationDispatcher: (MutationKind, [String]) async -> Result<Void, Error> = { kind, ids in
            do {
                for id in ids {
                    switch kind {
                    case .markRead, .bulkMarkRead:
                        try await graph.markEmailRead(id: id)
                    case .flag, .bulkFlag:
                        try await graph.flagEmail(id: id)
                    case .delete, .bulkDelete:
                        try await graph.softDeleteEmail(id: id)
                    }
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        // InboxActions exists in front of the coordinator so the new
        // command path can route through it. The coordinator picks up
        // the same executor / interpreter pair and short-circuits
        // recognized voice phrases through it before the legacy intent
        // path is consulted.
        let actions = InboxActions(graphClient: graph,
                                   summaryService: summary,
                                   stateMachine: sm)
        self.inboxActions = actions
        let executor = CommandExecutor(inboxActions: actions, stateMachine: sm)
        let interpreter: any Interpreter = PhraseInterpreter()
        self.coordinator = SessionCoordinator(
            stateMachine: sm,
            speechService: speech,
            ttsService: tts,
            audioController: audioController,
            summaryService: summary,
            intentClassifier: classifier,
            responseGenerator: generator,
            entityMatcher: entityMatcher,
            utteranceLog: utteranceLog,
            commandExecutor: executor,
            interpreter: interpreter,
            mutationDispatcher: mutationDispatcher
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService,
                        stateMachine: stateMachine,
                        inboxActions: inboxActions)
                .task { coordinator.start() }
                .onOpenURL { url in
                    // Pass the MSAL redirect callback URL back to MSAL.
                    MSALPublicClientApplication.handleMSALResponse(
                        url, sourceApplication: nil
                    )
                }
        }
    }
}
