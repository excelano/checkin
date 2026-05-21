// ContentView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Top-level auth and onboarding gate. Routes off the
/// `StateMachine.currentState` top-level case:
///   `.signedOut`  -> SignInView
///   `.onboarding` -> OnboardingFlow
///   `.active`     -> SummaryView
///
/// On launch this bootstraps from `AuthService.isAuthenticated`: an existing
/// MSAL token jumps past sign-in directly into onboarding (first run) or
/// active. The state machine remains the single source of truth thereafter.
struct ContentView: View {
    var authService: AuthService
    var stateMachine: StateMachine

    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppStorage(AppStorageKey.listeningMode) private var listeningMode: String = "tapToTalk"
    @AppStorage(AppStorageKey.voiceEnabled) private var voiceEnabled: Bool = true

    var body: some View {
        Group {
            switch stateMachine.currentState {
            case .signedOut:
                SignInView(authService: authService,
                           onAuthenticated: bootstrapAfterAuth)
            case .onboarding:
                OnboardingFlow(stateMachine: stateMachine)
            case .active:
                SummaryView(stateMachine: stateMachine, authService: authService)
            }
        }
        .onAppear { bootstrapOnLaunch() }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            // Detect external deauthentication (server-revoked token, MDM
            // wipe, manual cache clear) so SummaryView stops rendering with
            // a dead session.
            if !isAuth, case .active = stateMachine.currentState {
                stateMachine.transition(to: .signedOut)
                stateMachine.resetContext()
            }
        }
    }

    /// On cold launch, if MSAL already restored a session, advance the
    /// state machine past `.signedOut` directly. The state machine starts
    /// at `.signedOut` per its declaration; this function jumps it to the
    /// correct landing state.
    private func bootstrapOnLaunch() {
        guard case .signedOut = stateMachine.currentState else { return }
        if authService.isAuthenticated {
            bootstrapAfterAuth()
        }
    }

    /// Land the user in onboarding (first run) or active (returning user).
    /// Conversation mode opens directly to `.listening` — but only when
    /// voice commands are enabled. Voice off forces tap-to-talk rest
    /// semantics regardless of the stored listening-mode preference.
    private func bootstrapAfterAuth() {
        if !hasCompletedOnboarding {
            stateMachine.transition(to: .onboarding(.welcome))
        } else {
            let conversation = voiceEnabled && listeningMode == "conversation"
            stateMachine.preferredRestState = conversation ? .listening : .idle
            stateMachine.transition(to: .active(conversation ? .listening : .idle))
        }
    }
}

// MARK: - Sign-in screen

private struct SignInView: View {
    var authService: AuthService
    var onAuthenticated: () -> Void

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("CheckIn")
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
            Text("Sign in with your Microsoft 365 account to get started.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: signIn) {
                HStack(spacing: 8) {
                    if isSigningIn { ProgressView().tint(.white) }
                    Text(isSigningIn ? "Signing In\u{2026}" : "Sign In with Microsoft")
                }
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Brand.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isSigningIn)
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                _ = try await authService.signIn(enableTeams: Constants.teamsEnabled)
                onAuthenticated()
            } catch {
                #if DEBUG
                let ns = error as NSError
                print("[CheckIn AuthError] domain=\(ns.domain) code=\(ns.code) localized=\(ns.localizedDescription) userInfo=\(ns.userInfo)")
                #endif
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
