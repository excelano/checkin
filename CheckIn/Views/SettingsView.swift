// SettingsView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import AVFoundation

/// Settings sheet over the main screen per D27. Sections per D5 (Voice),
/// D17 (Listening Mode), D10 (Voice Recognition Tuning), D25 (Advanced).
/// Sign-out lives here per STATES.md.
///
/// Phase 4 establishes the surface and the @AppStorage keys. Phase 5 wires
/// the live effects: voice picker into TTSService, mode change into the
/// rest-state preference on StateMachine, voice tuning into a contact
/// fetch, custom client ID into AuthService.
struct SettingsView: View {
    var authService: AuthService
    var stateMachine: StateMachine

    @Environment(\.dismiss) private var dismiss

    // D5 Voice
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""
    @AppStorage("speechRate") private var speechRate: Double = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("verbosityFull") private var verbosityFull: Bool = false

    // D17 Listening Mode
    @AppStorage("listeningMode") private var listeningMode: String = "tapToTalk"

    // D10 Voice Recognition Tuning
    @AppStorage("voiceTuningEnabled") private var voiceTuningEnabled: Bool = false
    @State private var showTuningDisclosure = false

    // D25 Advanced
    @AppStorage("customClientID") private var customClientID: String = ""
    @AppStorage("customAuthority") private var customAuthority: String = ""
    @State private var showAdvancedExplainer = false

    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                listeningModeSection
                voiceTuningSection
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
            .sheet(isPresented: $showTuningDisclosure) {
                VoiceTuningDisclosureSheet(enabled: $voiceTuningEnabled)
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

    // MARK: - Voice (D5)

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

    // MARK: - Listening Mode (D17)

    private var listeningModeSection: some View {
        Section {
            Picker("Mode", selection: $listeningMode) {
                Text("Tap to talk").tag("tapToTalk")
                Text("Conversation mode").tag("conversation")
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .onChange(of: listeningMode) { _, new in
                stateMachine.preferredRestState = (new == "conversation") ? .listening : .idle
            }
        } header: {
            Text("Listening Mode")
        } footer: {
            Text("Tap to talk: each turn requires a mic tap. Conversation mode: the mic stays hot between turns until you say \u{201C}done\u{201D} or close the app.")
        }
    }

    // MARK: - Voice Recognition Tuning (D10)

    private var voiceTuningSection: some View {
        Section {
            Toggle("Voice Recognition Tuning", isOn: Binding(
                get: { voiceTuningEnabled },
                set: { newValue in
                    if newValue {
                        // Don't flip on without the disclosure; the sheet
                        // sets the AppStorage value when the user accepts.
                        showTuningDisclosure = true
                    } else {
                        voiceTuningEnabled = false
                        Task { @MainActor in
                            CustomLanguageModelManager().disable()
                        }
                    }
                }
            ))
        } header: {
            Text("Voice Recognition Tuning")
        } footer: {
            Text("Off by default. When on, CheckIn biases speech recognition toward your contacts. Contact data stays on this device.")
        }
    }

    // MARK: - Advanced (D25)

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
        stateMachine.transition(to: .signedOut)
        stateMachine.resetContext()
        dismiss()
    }
}

// MARK: - D10 disclosure sheet

private struct VoiceTuningDisclosureSheet: View {
    @Binding var enabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("How Voice Recognition Tuning works")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    paragraph("CheckIn builds a small recognition model from your contact display names. The model lets the speech recognizer hear \u{201C}Hernandez\u{201D} or \u{201C}MacAuley\u{201D} correctly the first time.")
                    paragraph("The model is built on this device. Nothing about your contacts is sent anywhere. The model attaches to the on-device speech recognizer; recognition itself stays local.")
                    paragraph("Turning the toggle off clears the model immediately. You can clear it any time.")
                    paragraph("The base recognition path works without this. If you decline, contact names may sometimes be misheard; you can still correct them by saying the first name alone or selecting from a list.")
                    Spacer(minLength: 24)
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Not now")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Brand.bgDarker)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button {
                            enabled = true
                            // Phase 5 wires the contact fetch + buildModel call.
                            dismiss()
                        } label: {
                            Text("Turn on")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Brand.accent)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(20)
            }
            .background(Brand.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Brand.textMuted)
    }
}

// MARK: - D25 explainer sheet

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
