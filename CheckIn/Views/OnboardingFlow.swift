// OnboardingFlow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import AVFoundation
import Speech

/// First-run onboarding. Four steps: welcome, permissions, mode,
/// firstQuery. Each step has a single substantive action and a skip with a
/// safe default. The flow drives the state machine through
/// `OnboardingSubstate` and completes by flipping `hasCompletedOnboarding`
/// to true and transitioning to `active.idle` (tap-to-talk) or
/// `active.listening` (conversation).
///
/// Per STATES.md sign-in happens upstream in the signedOut state, before
/// this flow runs. So step 2 here is permissions only, not sign-in.
struct OnboardingFlow: View {
    var stateMachine: StateMachine

    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @AppStorage(AppStorageKey.listeningMode) private var listeningMode: String = "tapToTalk"

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            switch stateMachine.currentState {
            case .onboarding(.welcome):
                WelcomeStep(onContinue: { advance(to: .permissions) })
            case .onboarding(.permissions):
                PermissionsStep(onContinue: { advance(to: .mode) },
                                onSkip:     { advance(to: .mode) })
            case .onboarding(.mode):
                ModeStep(selection: $listeningMode,
                         onContinue: { advance(to: .firstQuery) })
            case .onboarding(.firstQuery):
                FirstQueryStep(onContinue: { complete() },
                               onSkip:     { complete() })
            default:
                // Defensive: if we land in a non-onboarding state, complete.
                Color.clear.onAppear { complete() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance(to next: OnboardingSubstate) {
        stateMachine.transition(to: .onboarding(next))
    }

    private func complete() {
        hasCompletedOnboarding = true
        let restState: RestState = (listeningMode == "conversation") ? .listening : .idle
        stateMachine.preferredRestState = restState
        stateMachine.transition(to: .active(restState == .listening ? .listening : .idle))
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("CheckIn")
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
            Text("A voice-first daily check-in for your M365 calendar, email, and chats.")
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 8) {
                bullet("I open what you ask in Outlook or Teams.")
                bullet("I don't read email bodies.")
                bullet("I don't track or analyze you.")
                bullet("Content stays on your device or with your own M365 service.")
            }
            Text("Privacy details live in PRIVACY.md alongside the source code.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
            Spacer()
            Button(action: onContinue) {
                Text("Get started")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.body.weight(.semibold))
            }
        }
        .padding(28)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{2022}").foregroundStyle(Brand.accent)
            Text(text).foregroundStyle(.white)
        }
        .font(.body)
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsStep: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var micGranted = false
    @State private var speechGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("Permissions")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)

            permissionRow(
                granted: micGranted,
                title: "Microphone",
                grantLabel: "Grant microphone access",
                explanation: "I listen when you talk to me. Listening only happens on your device."
            ) {
                requestMic()
            }

            permissionRow(
                granted: speechGranted,
                title: "Speech recognition",
                grantLabel: "Grant speech recognition access",
                explanation: "I figure out what you said using on-device speech recognition. Nothing leaves your phone."
            ) {
                requestSpeech()
            }

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.body.weight(.semibold))
            }
            Button("Skip for now", action: onSkip)
                .foregroundStyle(Brand.textMuted)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .onAppear(perform: refreshGrantedState)
    }

    private func permissionRow(granted: Bool,
                               title: String,
                               grantLabel: String,
                               explanation: String,
                               action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.white)
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Brand.accent)
                }
            }
            Text(explanation).font(.callout).foregroundStyle(Brand.textMuted)
            if !granted {
                Button("Grant", action: action)
                    .foregroundStyle(Brand.accent)
                    .padding(.top, 4)
                    .accessibilityLabel(grantLabel)
            }
        }
        .padding(14)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Reconcile local toggle state with the system on every appear. Without
    /// this, a returning user who previously granted both permissions sees
    /// stale "Grant" buttons.
    private func refreshGrantedState() {
        micGranted = AVAudioApplication.shared.recordPermission == .granted
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func requestMic() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { micGranted = granted }
        }
    }

    private func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { speechGranted = status == .authorized }
        }
    }
}

// MARK: - Step 3: Listening mode

private struct ModeStep: View {
    @Binding var selection: String
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("How do you want to talk to me?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            modeOption(value: "tapToTalk",
                       title: "Tap to talk",
                       subtitle: "I listen when you tap the mic. Best in shared or noisy spaces.")
            modeOption(value: "conversation",
                       title: "Conversation mode",
                       subtitle: "The mic stays hot between turns. Best for hands-free use. Say \u{201C}done\u{201D} to leave.")

            Text("You can change this later in Settings.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.body.weight(.semibold))
            }
        }
        .padding(28)
    }

    private func modeOption(value: String, title: String, subtitle: String) -> some View {
        Button {
            selection = value
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selection == value
                      ? "largecircle.fill.circle"
                      : "circle")
                    .font(.title3)
                    .foregroundStyle(selection == value ? Brand.accent : Brand.textMuted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.callout).foregroundStyle(Brand.textMuted)
                }
                Spacer()
            }
            .padding(14)
            .background(selection == value ? Brand.bgDarker : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selection == value ? Brand.accent : Brand.textMuted.opacity(0.3),
                                  lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    }
}

// MARK: - Step 4: First query

private struct FirstQueryStep: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var invitation: String = ResponseTemplateRegistry.onboardingInvitations.randomElement()
        ?? ResponseTemplateRegistry.onboardingInvitations[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("First check-in")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(invitation)
                .font(.title3)
                .foregroundStyle(.white)

            Text("At any time, say \u{201C}what can I say\u{201D} or tap the question mark.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)

            Spacer()

            Button(action: onContinue) {
                Text("Open my summary")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.body.weight(.semibold))
            }
            Button("Skip", action: onSkip)
                .foregroundStyle(Brand.textMuted)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
    }
}
