// ContentView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Top-level auth and onboarding gate per D33. Routes off the
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

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("listeningMode") private var listeningMode: String = "tapToTalk"

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
    /// Conversation mode opens directly to `.listening` per D17.
    private func bootstrapAfterAuth() {
        if !hasCompletedOnboarding {
            stateMachine.transition(to: .onboarding(.welcome))
        } else {
            let rest: ActiveSubstate = (listeningMode == "conversation") ? .listening : .idle
            stateMachine.preferredRestState = (listeningMode == "conversation") ? .listening : .idle
            stateMachine.transition(to: .active(rest))
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
                _ = try await authService.signIn(enableTeams: false)
                onAuthenticated()
            } catch {
                let ns = error as NSError
                NSLog("[CheckIn AuthError] domain=%@ code=%ld localized=%@ userInfo=%@",
                      ns.domain, ns.code, ns.localizedDescription, ns.userInfo as NSDictionary)
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
