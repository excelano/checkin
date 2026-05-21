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
        // chose Conversation in a prior session lands in `.listening`
        // from first turn. Voice disabled overrides conversation mode —
        // no auto-arm of a hidden mic.
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

        _authService = State(initialValue: auth)
        _stateMachine = State(initialValue: sm)

        // Engine objects: InboxActions owns Graph mutations and refresh,
        // CommandExecutor runs Commands, Interpreter parses voice
        // transcripts into Commands. Touch gestures and voice transcripts
        // both produce Commands; the executor is the single execution
        // path.
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
            commandExecutor: executor,
            interpreter: interpreter
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
