// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import BackgroundTasks
import MSAL
import SwiftUI
import UIKit
import UserNotifications

@main
struct CheckInApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authService: AuthService
    private let inbox: Inbox

    init() {
        let auth = AuthService()
        let graph = GraphClient(authService: auth, enableTeams: Constants.teamsEnabled)
        let inbox = Inbox(graphClient: graph, teamsEnabled: Constants.teamsEnabled)
        // Wire the sign-out hook before exposing the AuthService — when
        // the user signs out (potentially to switch to a different
        // account), Inbox drops its summary and the cached user id so
        // the next refresh starts clean.
        auth.onSignOut = { [inbox] in inbox.reset() }
        _authService = State(initialValue: auth)
        self.inbox = inbox
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService, inbox: inbox)
                .onOpenURL { url in
                    // MSAL sign-in / sign-out completion callbacks come
                    // through with our redirect scheme prefix.
                    if url.scheme?.hasPrefix("msauth") == true {
                        MSALPublicClientApplication.handleMSALResponse(
                            url, sourceApplication: nil
                        )
                        return
                    }
                    // Widget Links always route through the host app —
                    // forward any non-MSAL URLs (Teams join links from
                    // the widget's Join pill, etc.) to iOS so the
                    // appropriate target app receives them.
                    UIApplication.shared.open(url)
                }
        }
        .backgroundTask(.appRefresh(Constants.backgroundRefreshIdentifier)) {
            // Schedule the next run first — if the refresh hangs or the
            // task is killed by iOS at its time limit, we still want to
            // be on the schedule.
            scheduleNextBackgroundRefresh()
            await inbox.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                scheduleNextBackgroundRefresh()
            }
        }
    }

    /// Submit a new request with our identifier. iOS supersedes any
    /// existing pending request with the same identifier, so this is
    /// idempotent. Whether and when it actually runs is at the system's
    /// discretion (usage patterns, battery, time of day).
    private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Constants.backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Constants.backgroundRefreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
