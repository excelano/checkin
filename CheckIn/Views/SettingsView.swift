// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Settings sheet. Voice toggle is visual chrome (the recognizer isn't
/// wired up yet). Auto-refresh and the bring-your-own-Azure overrides
/// stay. Sign-out lives here.
struct SettingsView: View {
    var authService: AuthService
    var stateMachine: StateMachine

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.voiceEnabled) private var voiceEnabled: Bool = true
    @AppStorage(AppStorageKey.summaryRefreshMinutes) private var summaryRefreshMinutes: Int = AppStorageKey.summaryRefreshMinutesDefault

    // Advanced
    @AppStorage(AppStorageKey.customClientID) private var customClientID: String = ""
    @AppStorage(AppStorageKey.customAuthority) private var customAuthority: String = ""
    @State private var showAdvancedExplainer = false

    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                refreshSection
                advancedSection
                signOutSection
            }
            .scrollContentBackground(.hidden)
            .background(Brand.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                        .accessibilityLabel("Close settings")
                }
            }
            .sheet(isPresented: $showAdvancedExplainer) {
                AdvancedExplainerSheet()
            }
            .confirmationDialog("Sign out of CheckIn?",
                                isPresented: $showSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            Toggle("Voice commands", isOn: $voiceEnabled)
        } header: {
            Text("Voice")
        } footer: {
            Text("Toggling voice on shows the microphone button. The recognizer isn't wired up yet — the button is a placeholder.")
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        Section {
            Picker("Auto-refresh", selection: $summaryRefreshMinutes) {
                Text("1 minute").tag(1)
                Text("2 minutes").tag(2)
                Text("3 minutes").tag(3)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("Never").tag(0)
            }
        } header: {
            Text("Auto-refresh")
        } footer: {
            Text("How often CheckIn re-fetches your inbox, calendar, and chats in the background.")
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            TextField("Custom client ID", text: $customClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(.body, design: .monospaced))
            TextField("Custom authority URL", text: $customAuthority)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.URL)
                .font(.system(.body, design: .monospaced))
            Button("Reset to defaults") {
                customClientID = ""
                customAuthority = ""
            }
            .foregroundStyle(.red)
            Button("Why might I want this?") {
                showAdvancedExplainer = true
            }
            .foregroundStyle(Brand.accent)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Override the default Azure App Registration with your own. Leave both fields blank to use Excelano's published registration.")
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Text("Sign Out")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func signOut() {
        authService.signOut()
        dismiss()
        // Defer so the sheet dismissal animation settles before ContentView
        // swaps SummaryView for SignInView.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            stateMachine.transition(to: .signedOut)
            stateMachine.resetContext()
        }
    }
}

// MARK: - Self-host explainer sheet

private struct AdvancedExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Bring your own Azure App Registration")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("CheckIn uses Excelano's published Azure App Registration by default. You can run it against your own registration instead.")
                        .font(.body)
                        .foregroundStyle(Brand.textMuted)
                    Text("Why you might want this:")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Tenant governance requires apps registered through your own process. You want zero shared infrastructure with Excelano. You want to verify the privacy posture by inspecting the configuration end to end.")
                        .font(.body)
                        .foregroundStyle(Brand.textMuted)
                    Text("How:")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Create an Azure App Registration in your tenant. Add msauth.com.excelano.checkin://auth as a redirect URI. Enable the public client flow. Grant Mail.ReadWrite, Calendars.Read, and Chat.ReadWrite. Paste the client ID and authority above.")
                        .font(.body)
                        .foregroundStyle(Brand.textMuted)
                    Text("See SELF-HOSTING.md in the source repository for screenshots and the full walkthrough.")
                        .font(.callout)
                        .foregroundStyle(Brand.textMuted)
                        .padding(.top, 6)
                    Spacer(minLength: 24)
                }
                .padding(20)
            }
            .background(Brand.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
