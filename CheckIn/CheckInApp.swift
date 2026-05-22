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
    private let inboxActions: InboxActions

    init() {
        let auth = AuthService()
        let sm = StateMachine()

        let graph = GraphClient(authService: auth, enableTeams: Constants.teamsEnabled)
        let summary = GraphSummaryService(graphClient: graph,
                                          teamsEnabled: Constants.teamsEnabled)

        _authService = State(initialValue: auth)
        _stateMachine = State(initialValue: sm)

        self.inboxActions = InboxActions(graphClient: graph,
                                         summaryService: summary,
                                         stateMachine: sm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService,
                        stateMachine: stateMachine,
                        inboxActions: inboxActions)
                .onOpenURL { url in
                    // Pass the MSAL redirect callback URL back to MSAL.
                    MSALPublicClientApplication.handleMSALResponse(
                        url, sourceApplication: nil
                    )
                }
        }
    }
}
