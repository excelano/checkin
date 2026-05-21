// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import AVFoundation

/// Settings sheet over the main screen. Sections for Voice,
/// Listening Mode, and Advanced. Sign-out lives here per STATES.md.
/// Voice Recognition Tuning is deferred.
struct SettingsView: View {
    var authService: AuthService
    var stateMachine: StateMachine

    @Environment(\.dismiss) private var dismiss

    // Voice
    @AppStorage(AppStorageKey.voiceIdentifier) private var voiceIdentifier: String = ""
    @AppStorage(AppStorageKey.speechRate) private var speechRate: Double = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage(AppStorageKey.verbosityFull) private var verbosityFull: Bool = false

    // Listening Mode
    @AppStorage(AppStorageKey.listeningMode) private var listeningMode: String = "tapToTalk"

    // Summary refresh cadence (minutes; 0 = Never)
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
                listeningModeSection
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
            Picker("Voice", selection: $voiceIdentifier) {
                Text("System default").tag("")
                ForEach(localeVoices(), id: \.identifier) { voice in
                    Text(voiceLabel(voice)).tag(voice.identifier)
                }
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Speech rate")
                    Spacer()
                    Text(rateLabel(speechRate))
                        .foregroundStyle(Brand.textMuted)
                        .monospacedDigit()
                }
                Slider(value: $speechRate,
                       in: Double(AVSpeechUtteranceMinimumSpeechRate)
                            ... Double(AVSpeechUtteranceMaximumSpeechRate)) {
                    Text("Speech rate")
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill").foregroundStyle(Brand.textMuted)
                } maximumValueLabel: {
                    Image(systemName: "hare.fill").foregroundStyle(Brand.textMuted)
                }
            }
            Toggle("Full summaries", isOn: $verbosityFull)
        } header: {
            Text("Voice")
        } footer: {
            Text("CheckIn defaults to terse summaries. Turn on full summaries when you want every detail spoken.")
        }
    }

    private func localeVoices() -> [AVSpeechSynthesisVoice] {
        let prefix = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.name < $1.name }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = " (Premium)"
        case .enhanced: quality = " (Enhanced)"
        default: quality = ""
        }
        return "\(voice.name) \u{2014} \(voice.language)\(quality)"
    }

    private func rateLabel(_ rate: Double) -> String {
        let pct = Int((rate / Double(AVSpeechUtteranceDefaultSpeechRate)) * 100)
        return "\(pct)%"
    }

    // MARK: - Listening Mode

    private var listeningModeSection: some View {
        Section {
            Picker("Mode", selection: $listeningMode) {
                Text("Tap to talk").tag("tapToTalk")
                Text("Conversation").tag("conversation")
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .onChange(of: listeningMode) { _, new in
                stateMachine.preferredRestState = (new == "conversation") ? .listening : .idle
            }
            .onAppear {
                // Keep the live preferredRestState in sync with the stored
                // setting on every sheet open. AppStorage carries the
                // selection across launches; the state machine resets it
                // on init, so it'd otherwise drift back to .idle.
                stateMachine.preferredRestState = (listeningMode == "conversation") ? .listening : .idle
            }
        } header: {
            Text("Listening Mode")
        } footer: {
            Text("Tap to talk: each turn requires a mic tap. Conversation: I keep the mic open between turns and finalize when you stop speaking.")
        }
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        Section {
            Picker("Refresh", selection: $summaryRefreshMinutes) {
                Text("1 minute").tag(1)
                Text("2 minutes").tag(2)
                Text("3 minutes").tag(3)
                Text("5 minutes").tag(5)
                Text("10 minutes").tag(10)
                Text("Never").tag(0)
            }
        } header: {
            Text("Refresh")
        } footer: {
            Text("How often CheckIn re-fetches your inbox, calendar, and chats in the background. Saying \"refresh\" forces a fetch regardless of this setting.")
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
        // Defer so the sheet dismissal animation can settle before
        // ContentView swaps SummaryView for SignInView.
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
                    Text("Create an Azure App Registration in your tenant. Add msauth.com.excelano.checkin://auth as a redirect URI. Enable the public client flow. Grant Mail.Read, Calendars.Read, and Chat.Read. Paste the client ID and authority above.")
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
