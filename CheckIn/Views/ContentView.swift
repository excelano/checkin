// ContentView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ContentView: View {
    var authService: AuthService
    var inbox: Inbox

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authService.isAuthenticated {
                SummaryView(inbox: inbox, authService: authService)
                    .task {
                        // .task re-fires when sheets dismiss; the nil-guard
                        // keeps subsequent re-mounts from re-fetching.
                        if inbox.summary == nil {
                            await inbox.refresh()
                        }
                    }
            } else {
                SignInView(authService: authService)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && authService.isAuthenticated {
                Task { await inbox.refreshIfStale() }
            }
        }
    }
}

private struct SignInView: View {
    var authService: AuthService

    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundStyle(Brand.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(authService: authService)
        }
    }

    private func signIn() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                _ = try await authService.signIn(enableTeams: Constants.teamsEnabled)
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
