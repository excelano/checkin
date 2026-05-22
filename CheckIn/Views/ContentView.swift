// ContentView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Top-level auth gate. Routes off the state machine top-level case:
///   `.signedOut`  -> SignInView
///   `.active`     -> SummaryView
/// Onboarding is gone; first launch lands directly in active after sign-in.
struct ContentView: View {
    var authService: AuthService
    var stateMachine: StateMachine
    var inboxActions: InboxActions

    var body: some View {
        Group {
            switch stateMachine.currentState {
            case .signedOut:
                SignInView(authService: authService,
                           onAuthenticated: bootstrapAfterAuth)
            case .active:
                SummaryView(stateMachine: stateMachine,
                            authService: authService,
                            inboxActions: inboxActions)
                    .task {
                        // Initial fetch on landing in active. Skipped when
                        // the summary is already loaded; the no-op re-task
                        // on sheet dismissal then costs nothing.
                        if stateMachine.context.summary == nil {
                            await inboxActions.refresh()
                        }
                    }
            }
        }
        .onAppear { bootstrapOnLaunch() }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if !isAuth, case .active = stateMachine.currentState {
                stateMachine.transition(to: .signedOut)
                stateMachine.resetContext()
            }
        }
    }

    private func bootstrapOnLaunch() {
        guard case .signedOut = stateMachine.currentState else { return }
        if authService.isAuthenticated {
            bootstrapAfterAuth()
        }
    }

    private func bootstrapAfterAuth() {
        stateMachine.transition(to: .active(.idle))
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
