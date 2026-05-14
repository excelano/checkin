// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import MSAL

@main
struct CheckInApp: App {
    @State private var authService = AuthService()
    @State private var stateMachine: StateMachine
    private let coordinator: SessionCoordinator

    init() {
        let sm = StateMachine()
        let speech = AppleSpeechService()
        let classifier: any IntentClassifier = NLEmbeddingIntentClassifier()
        let generator: any ResponseGenerator = PersonaResponseGenerator()
        _stateMachine = State(initialValue: sm)
        self.coordinator = SessionCoordinator(
            stateMachine: sm,
            speechService: speech,
            intentClassifier: classifier,
            responseGenerator: generator
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
