// CheckInApp.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import BackgroundTasks
import CheckInKit
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
        let inbox = Inbox(graphClient: graph, authService: auth, teamsEnabled: Constants.teamsEnabled)
        // Wire the sign-out hook before exposing the AuthService — when
        // the user signs out (potentially to switch to a different
        // account), Inbox drops its summary and the cached user id so
        // the next refresh starts clean.
        auth.onSignOut = { [inbox] in inbox.reset() }
        _authService = State(initialValue: auth)
        self.inbox = inbox
        // Watch-side relay. Activated here so the WCSession is live by the
        // time the first refresh pushes a snapshot. The closures route
        // watch-originated actions through the same Inbox entry points
        // Siri uses — same silent-token preflight, same optimistic
        // mutate-then-revert path, same snapshot patch on completion.
        inbox.phoneConnectivity = PhoneConnectivity(
            setPresence: { [inbox] in try await inbox.applyPresence($0) },
            setOutOfOffice: { [inbox] in try await inbox.applyOutOfOffice($0) },
            refresh: { [inbox] in await inbox.refresh() }
        )
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        // Expose the live services to App Intents. The system runs this
        // init before any intent's perform() — whether the process is
        // launched for the UI or background-launched to run a shortcut —
        // so @Dependency resolution in the intents finds them here.
        AppDependencyManager.shared.add(dependency: inbox)
        AppDependencyManager.shared.add(dependency: auth)
        // The status-mutating intents (Set Status / Set Out of Office)
        // live in CheckInKit so the widget extension can reference them.
        // They can't name `Inbox`, and AppIntents keys @Dependency by
        // concrete type (not protocol), so they resolve this StatusActions
        // box wired to the live Inbox here.
        AppDependencyManager.shared.add(
            dependency: StatusActions(
                presence: { [inbox] in try await inbox.applyPresence($0) },
                outOfOffice: { [inbox] in try await inbox.applyOutOfOffice($0) }
            )
        )
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
            // be on the schedule. The await hops to the main actor; the
            // closure already does the same for inbox.refresh() below.
            await scheduleNextBackgroundRefresh()
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
