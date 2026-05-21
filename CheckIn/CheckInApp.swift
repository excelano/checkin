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

    init() {
        let auth = AuthService()
        let sm = StateMachine()
        // Hydrate the rest-state preference from AppStorage so a user who
        // chose Conversation in a prior session lands in .listening from
        // first turn instead of waiting for them to reopen Settings.
        let storedMode = UserDefaults.standard.string(forKey: AppStorageKey.listeningMode) ?? "tapToTalk"
        sm.preferredRestState = (storedMode == "conversation") ? .listening : .idle
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
        self.coordinator = SessionCoordinator(
            stateMachine: sm,
            speechService: speech,
            ttsService: tts,
            audioController: audioController,
            summaryService: summary,
            intentClassifier: classifier,
            responseGenerator: generator,
            entityMatcher: entityMatcher,
            utteranceLog: utteranceLog
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService,
                        stateMachine: stateMachine)
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
