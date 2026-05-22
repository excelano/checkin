// SummaryView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UIKit

/// The single main screen. Numbered list of meeting / emails / chats with
/// per-row taps and swipes wired to `InboxActions`. When the voice
/// toggle is on, a microphone button is shown for visual chrome — tapping
/// it cycles the local `isMicActive` flag and shows a listening indicator,
/// but no recognizer runs. Voice plumbing is gone; the mic is a placeholder
/// for the future voice surface.
struct SummaryView: View {
    var stateMachine: StateMachine
    var authService: AuthService
    var inboxActions: InboxActions

    @AppStorage(AppStorageKey.voiceEnabled) private var voiceEnabled: Bool = true
    @State private var isMicActive: Bool = false

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
            HelpView()
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

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = stateMachine.context.summary {
            if summary.meeting == nil && summary.emails.isEmpty && summary.chats.isEmpty {
                emptyDayScrollable
            } else {
                itemsList(summary: summary)
            }
        } else {
            notFetchedState
        }
    }

    private func itemsList(summary: CheckInSummary) -> some View {
        List {
            if let meeting = summary.meeting {
                Section {
                    MeetingCard(meeting: meeting,
                                onTap: { joinOrCalendar(meeting) })
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 0))
                }
            }
            if !summary.emails.isEmpty {
                Section {
                    ForEach(summary.emails) { email in
                        EmailRow(email: email, onTap: { replyTo(email) })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    Task { await inboxActions.markRead(emailId: email.id) }
                                } label: {
                                    Label("Mark Read", systemImage: "envelope.open")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task { await inboxActions.setFlagged(!email.isFlagged, emailId: email.id) }
                                } label: {
                                    Label(email.isFlagged ? "Unflag" : "Flag",
                                          systemImage: email.isFlagged ? "flag.slash" : "flag")
                                }
                                .tint(.orange)
                            }
                    }
                } header: {
                    sectionHeader(title: "Email", count: summary.emails.count)
                }
            }
            if !summary.chats.isEmpty {
                Section {
                    ForEach(summary.chats) { chat in
                        ChatRow(chat: chat, onTap: { openChat(chat) })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                } header: {
                    sectionHeader(title: "Teams", count: summary.chats.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
        .refreshable { await inboxActions.refresh() }
    }

    private var emptyDayScrollable: some View {
        ScrollView {
            emptyDayState
                .padding(.top, 60)
        }
        .refreshable { await inboxActions.refresh() }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
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
    }

    // MARK: - Tap actions

    private func joinOrCalendar(_ meeting: Meeting) {
        if let urlString = meeting.joinUrl,
           let url = DeepLinkService.passthrough(urlString) {
            UIApplication.shared.open(url) { ok in
                if !ok { deepLink(DeepLinkService.outlookCalendar) }
            }
            return
        }
        deepLink(DeepLinkService.outlookCalendar)
    }

    private func replyTo(_ email: Email) {
        if !email.fromAddress.isEmpty,
           let url = DeepLinkService.outlookReply(to: email.fromAddress,
                                                  subject: email.subject) {
            UIApplication.shared.open(url) { ok in
                if !ok { deepLink(DeepLinkService.outlookInbox) }
            }
            return
        }
        deepLink(DeepLinkService.outlookInbox)
    }

    private func openChat(_ chat: ChatMessage) {
        if let urlString = chat.webUrl,
           let url = DeepLinkService.passthrough(urlString) {
            UIApplication.shared.open(url) { ok in
                if !ok { deepLink(DeepLinkService.teams) }
            }
            return
        }
        deepLink(DeepLinkService.teams)
    }

    private var notFetchedState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            ProgressView().tint(Brand.accent)
            Text("Loading your day…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDayState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
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

    // MARK: - Voice area (placeholder)

    @ViewBuilder
    private var voiceArea: some View {
        if voiceEnabled {
            VStack(spacing: 14) {
                if isMicActive {
                    ListeningIndicator()
                }
                micButton
            }
        }
    }

    private var micButton: some View {
        Button {
            isMicActive.toggle()
        } label: {
            Image(systemName: isMicActive ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Brand.accent)
                .clipShape(Circle())
                .shadow(color: Brand.accent.opacity(0.3), radius: 12)
        }
        .accessibilityLabel(isMicActive ? "Stop listening" : "Microphone")
        .accessibilityHint("Voice commands are not wired up yet")
    }

    // MARK: - Actions

    private func openHelp() {
        guard case .active = stateMachine.currentState else { return }
        stateMachine.transition(to: .active(.helpDisplayed))
    }

    private func openSettings() {
        guard case .active = stateMachine.currentState else { return }
        stateMachine.transition(to: .active(.settingsDisplayed))
    }

    private func deepLink(_ url: URL?) {
        guard let url, UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
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
                    if case .active(.helpDisplayed) = stateMachine.currentState {
                        stateMachine.transition(to: .active(.idle))
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
                    if case .active(.settingsDisplayed) = stateMachine.currentState {
                        stateMachine.transition(to: .active(.idle))
                    }
                }
            }
        )
    }
}

// MARK: - Sub-views

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
                            .lineLimit(2)
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
                    HStack(spacing: 6) {
                        Text(email.from).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if email.isFlagged {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Flagged")
                        }
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Reply in Outlook")
    }

    private var accessibilityLabel: String {
        let flagPrefix = email.isFlagged ? "Flagged email" : "Email"
        return "\(flagPrefix) from \(email.from): \(email.subject)"
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
