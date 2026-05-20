// SummaryView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UIKit

/// The single main screen per D27. Shows the at-a-glance summary plus the
/// voice surface. Tapping any item deep-links to Outlook or Teams. The mic
/// button is the primary voice control for both modes (D17): in tap-to-talk
/// it starts a turn; in conversation mode it cancels listening to return to
/// idle.
///
/// Phase 4 establishes the surface and the state-driven indicators. Phase 5
/// wires the real SpeechService start/stop to the listening transitions and
/// the GraphClient fetch to refresh.
struct SummaryView: View {
    var stateMachine: StateMachine
    var authService: AuthService

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                summaryContent
                Spacer()
                voiceArea
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: helpBinding) {
            HelpView(focus: helpFocus)
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView(authService: authService, stateMachine: stateMachine)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                openHelp()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title2)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Help")
            .accessibilityHint("Show what you can ask")

            Spacer()

            Text("CheckIn")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    // MARK: - Summary content

    private var summaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let summary = stateMachine.context.summary {
                    if let meeting = summary.meeting {
                        MeetingCard(meeting: meeting,
                                    onTap: { deepLink(DeepLinkService.outlookCalendar) })
                    }
                    if !summary.emails.isEmpty {
                        SectionHeader(title: "Email", count: summary.emails.count)
                        ForEach(summary.emails) { email in
                            EmailRow(email: email,
                                     onTap: { deepLink(DeepLinkService.outlookInbox) })
                        }
                    }
                    if !summary.chats.isEmpty {
                        SectionHeader(title: "Teams", count: summary.chats.count)
                        ForEach(summary.chats) { chat in
                            ChatRow(chat: chat,
                                    onTap: { deepLink(DeepLinkService.teams) })
                        }
                    }
                    if summary.emails.isEmpty && summary.chats.isEmpty && summary.meeting == nil {
                        emptyDayState
                    }
                } else {
                    notFetchedState
                }
            }
            .padding(.top, 16)
        }
    }

    private var notFetchedState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            Image(systemName: "mic.fill")
                .font(.system(size: 38))
                .foregroundStyle(Brand.accent)
            Text("Tap the mic and ask")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("\u{201C}what's on my plate\u{201D}")
                .font(.body)
                .foregroundStyle(Brand.textMuted)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDayState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 38))
                .foregroundStyle(Brand.accent)
            Text("Nothing pending.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Inbox at zero, no Teams pings, no meeting up next.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Voice area (caption + mic)

    private var voiceArea: some View {
        VStack(spacing: 14) {
            // The disambig panel renders as soon as pendingDisambiguation
            // is set in context, not when state == .disambiguating. The
            // state machine sits in .speaking while the prompt TTS plays,
            // then transitions to .disambiguating on finish — binding to
            // pending lets the candidate panel appear immediately so the
            // user can tap-pick without waiting through the prompt.
            if let pending = stateMachine.context.pendingDisambiguation {
                DisambiguatingPanel(utterance: pending.suspendedIntent.utterance,
                                    candidates: pending.candidates,
                                    onSelect: { stateMachine.onCandidateSelected?($0) },
                                    onCancel: { stateMachine.onDisambiguationCancelled?() })
            } else {
                switch stateMachine.currentState {
                case .active(.listening):
                    ListeningIndicator()
                case .active(.processing):
                    ThinkingIndicator()
                case .active(.speaking(let response, _)):
                    CaptioningView(text: response.text)
                case .active(.confirming(let action)):
                    ConfirmingPanel(action: action,
                                    onYes: { /* Day 2 wires the executor */ },
                                    onNo: { stateMachine.transition(to: .active(restState())) })
                default:
                    EmptyView()
                }
            }

            micButton
        }
    }

    private var micButton: some View {
        Button {
            micTapped()
        } label: {
            Image(systemName: micSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(micEnabled ? Brand.accent : Brand.accentDim)
                .clipShape(Circle())
                .shadow(color: Brand.accent.opacity(0.3), radius: 12)
        }
        .accessibilityLabel(micAccessibilityLabel)
        .accessibilityHint(micAccessibilityHint)
    }

    private var micSymbol: String {
        switch stateMachine.currentState {
        case .active(.listening), .active(.disambiguating), .active(.confirming):
            return "stop.fill"
        case .active(.speaking):
            return "stop.fill"
        default:
            return "mic.fill"
        }
    }

    private var micEnabled: Bool {
        switch stateMachine.currentState {
        case .active(.processing): return false
        case .active: return true
        default: return false
        }
    }

    private var micAccessibilityLabel: String {
        switch stateMachine.currentState {
        case .active(.listening), .active(.disambiguating): return "Stop listening"
        case .active(.speaking): return "Stop speaking"
        default: return "Microphone"
        }
    }

    private var micAccessibilityHint: String {
        switch stateMachine.currentState {
        case .active(.idle): return "Tap to start a voice turn"
        case .active(.listening): return "Tap to finish speaking"
        case .active(.speaking): return "Tap to interrupt and speak"
        default: return ""
        }
    }

    // MARK: - Actions

    private func micTapped() {
        switch stateMachine.currentState {
        case .active(.idle):
            stateMachine.transition(to: .active(.listening))
        case .active(.listening):
            // Tap-during-listening means "I'm done, process it." The
            // coordinator finalizes the recognizer on this transition; the
            // final transcript arrives shortly after as an isFinal update.
            stateMachine.transition(to: .active(.processing(.thinking)))
        case .active(.disambiguating):
            // Mic-tap during disambiguation = cancel (per 5.3b brief).
            // Routes through the coordinator so pending state clears too.
            stateMachine.onDisambiguationCancelled?()
        case .active(.speaking):
            // Barge-in per D8: TTSService.stop() lands with the speaking
            // wiring; for now the transition alone restarts listening.
            stateMachine.transition(to: .active(.listening))
        default:
            break
        }
    }

    private func openHelp() {
        // Allow help from any active substate per D30 universal intent.
        guard case .active = stateMachine.currentState else { return }
        stateMachine.transition(to: .active(.helpDisplayed(returnTo: stateMachine.preferredRestState)))
    }

    private func openSettings() {
        guard case .active = stateMachine.currentState else { return }
        stateMachine.transition(to: .active(.settingsDisplayed(returnTo: stateMachine.preferredRestState)))
    }

    private func deepLink(_ url: URL?) {
        guard let url, UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
        // Deep-link is transient; if listening/speaking, return to rest.
        switch stateMachine.currentState {
        case .active(.idle): break
        default: stateMachine.transition(to: .active(restState()))
        }
    }

    private func restState() -> ActiveSubstate {
        stateMachine.preferredRestState == .listening ? .listening : .idle
    }

    // MARK: - Sheet bindings

    private var helpBinding: Binding<Bool> {
        Binding(
            get: {
                if case .active(.helpDisplayed) = stateMachine.currentState { return true }
                return false
            },
            set: { presented in
                if !presented {
                    if case .active(.helpDisplayed(let ret)) = stateMachine.currentState {
                        stateMachine.transition(to: .active(ret == .listening ? .listening : .idle))
                    }
                }
            }
        )
    }

    private var settingsBinding: Binding<Bool> {
        Binding(
            get: {
                if case .active(.settingsDisplayed) = stateMachine.currentState { return true }
                return false
            },
            set: { presented in
                if !presented {
                    if case .active(.settingsDisplayed(let ret)) = stateMachine.currentState {
                        stateMachine.transition(to: .active(ret == .listening ? .listening : .idle))
                    }
                }
            }
        )
    }

    private var helpFocus: HelpFocus {
        if !stateMachine.context.recentRefusals.isEmpty { return .afterRefusal }
        if !stateMachine.context.recentRedirects.isEmpty { return .afterRedirect }
        return .neutral
    }
}

// MARK: - Sub-views

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.textMuted)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(Brand.bgDarker)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.top, 4)
    }
}

private struct MeetingCard: View {
    let meeting: Meeting
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(Brand.accent)
                    Text(meeting.subject)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text(untilTime(meeting.start))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                    if !meeting.organizer.isEmpty {
                        Text("with \(meeting.organizer)")
                            .font(.subheadline)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.bgDarker)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Open in Outlook calendar")
    }

    private var accessibilityLabel: String {
        var parts = ["Next meeting", meeting.subject, untilTime(meeting.start)]
        if !meeting.organizer.isEmpty { parts.append("with \(meeting.organizer)") }
        return parts.joined(separator: ", ")
    }
}

private struct EmailRow: View {
    let email: Email
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope")
                    .foregroundStyle(Brand.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(email.from).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(relativeTime(email.received))
                            .font(.caption)
                            .foregroundStyle(Brand.textMuted)
                    }
                    Text(email.subject).font(.body).foregroundStyle(.white).lineLimit(2)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Email from \(email.from): \(email.subject)")
        .accessibilityHint("Open in Outlook")
    }
}

private struct ChatRow: View {
    let chat: ChatMessage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Brand.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(chat.from).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(relativeTime(chat.sent))
                            .font(.caption)
                            .foregroundStyle(Brand.textMuted)
                    }
                    if !chat.topic.isEmpty {
                        Text(chat.topic).font(.body).foregroundStyle(.white).lineLimit(2)
                    } else {
                        Text(truncate(chat.preview, maxLen: 60))
                            .font(.body)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Teams chat from \(chat.from)")
        .accessibilityHint("Open in Teams")
    }
}

private struct DisambiguatingPanel: View {
    let utterance: String
    let candidates: [Candidate]
    let onSelect: (Candidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You said \u{201C}\(utterance)\u{201D}")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
            Text("Which one?")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    HStack {
                        Text("\(index + 1).")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                            .frame(width: 28, alignment: .leading)
                        Text(candidate.label)
                            .font(.body)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Brand.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Option \(index + 1): \(candidate.label)")
            }
            Button("Cancel", action: onCancel)
                .foregroundStyle(Brand.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ConfirmingPanel: View {
    let action: PendingAction
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(action.description)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button(action: onNo) {
                    Text("No")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Brand.bgDarker)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button(action: onYes) {
                    Text("Yes")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Brand.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
