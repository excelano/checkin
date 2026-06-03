// SummaryView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI
import UIKit
#if DEBUG
import os
private let log = Logger(subsystem: "com.excelano.checkin", category: "summary")
#endif

struct SummaryView: View {
    var inbox: Inbox
    var authService: AuthService

    @State private var showSettings = false
    @State private var showCustomMessageSheet = false
    /// The meeting whose conflict the user wants to resolve. Driving the
    /// sheet via `.sheet(item:)` (rather than a Bool + separate id) means
    /// the sheet correctly targets whichever meeting was long-pressed.
    @State private var conflictTarget: Meeting?
    /// The chat or email the user tapped to preview. On iPhone (compact)
    /// it drives a `.sheet(item:)`; on iPad (regular) it drives the
    /// split-view detail column instead.
    @State private var previewTarget: MessagePreviewTarget?
    /// Reference clock that drives "which meeting is currently active"
    /// recomputation. A background task nudges this every 30 seconds so
    /// back-to-back meetings transition without waiting for a refresh.
    @State private var clockTick: Date = .now

    /// iPad (regular width) gets a NavigationSplitView; iPhone (compact)
    /// keeps the single-column panel with sheet-based previews.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isRegularWidth {
                NavigationSplitView {
                    panel
                        .toolbar(.hidden, for: .navigationBar)
                } detail: {
                    SummaryDetailPane(
                        inbox: inbox,
                        target: previewTarget,
                        onClose: { previewTarget = nil }
                    )
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                panel
                    .sheet(item: $previewTarget) { target in
                        MessagePreviewSheet(
                            inbox: inbox,
                            target: target,
                            onClose: { previewTarget = nil }
                        )
                    }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(authService: authService, inbox: inbox)
        }
        .sheet(isPresented: $showCustomMessageSheet) {
            CustomMessageSheet(
                initialMessage: inbox.customStatusMessage,
                onSave: { text in
                    Task { await inbox.setCustomStatusMessage(text) }
                },
                onClear: {
                    Task { await inbox.setCustomStatusMessage("") }
                }
            )
        }
        .sheet(item: $conflictTarget) { target in
            ConflictResolutionSheet(inbox: inbox, primaryMeetingId: target.id)
        }
        .task {
            // Re-evaluate "current meeting" every 30 seconds so a
            // just-ended meeting transitions to the back-to-back one
            // without waiting for the next Graph refresh. Cheap — the
            // helpers read from already-cached state.
            while !Task.isCancelled {
                clockTick = .now
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// The status panel: title bar, failure banner, the item list, and the
    /// floating undo / error banners. Rendered bare on iPhone and as the
    /// sidebar of the split view on iPad.
    private var panel: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if inbox.lastRefreshFailed {
                    failureBanner
                        .padding(.top, 8)
                }
                summaryContent
                Spacer()
            }
            .padding(.horizontal, 16)
            .ignoresSafeArea(.container, edges: .bottom)

            VStack(spacing: 8) {
                Spacer()
                transientErrorBanner
                    .padding(.horizontal, 16)
                    .animation(.easeInOut(duration: 0.25), value: inbox.transientMessage)
                undoBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .animation(.easeInOut(duration: 0.25), value: inbox.pendingUndo?.summary)
            }
        }
    }

    @ViewBuilder
    private var transientErrorBanner: some View {
        if let message = inbox.transientMessage {
            let isError = message.kind == .error
            HStack(spacing: 12) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(isError ? .orange : Brand.accent)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    inbox.dismissTransientMessage()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textMuted)
                }
                .accessibilityLabel(isError ? "Dismiss error" : "Dismiss message")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.bgDarker)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let action = inbox.pendingUndo {
            HStack(spacing: 12) {
                Text(action.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Undo") {
                    Task { await inbox.performUndo() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.accent)
                Button {
                    inbox.dismissUndo()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textMuted)
                }
                .accessibilityLabel("Dismiss undo")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Brand.bgDarker)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var failureBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
            Text("Couldn't reach Microsoft \u{2014} pull to retry")
                .font(.footnote.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var topBar: some View {
        ZStack {
            Text("CheckIn")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

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
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = inbox.summary {
            itemsList(summary: summary)
        } else {
            notFetchedState
        }
    }

    private func itemsList(summary: CheckInSummary) -> some View {
        // Precompute the per-sender and per-subject counts once rather
        // than filtering the email list inside the ForEach. With "Show
        // all" the visible list can grow to ~200 emails, where the
        // O(N²) inline version became measurable.
        let senderCounts: [String: Int] = summary.emails.reduce(into: [:]) { acc, e in
            guard !e.fromAddress.isEmpty else { return }
            acc[e.fromAddress, default: 0] += 1
        }
        let subjectCounts: [String: Int] = summary.emails.reduce(into: [:]) { acc, e in
            let key = e.subject.normalizedSubjectKey
            guard !key.isEmpty else { return }
            acc[key, default: 0] += 1
        }
        // Pick the current meeting and the remaining "Later today" list
        // from the cached meeting set using `clockTick` — a background
        // task in `body` advances it every 30 seconds, so back-to-back
        // meetings rotate cleanly without a refresh. Pass each meeting's
        // explicit id to `respondToMeeting` so RSVPs target the rotated
        // meeting, not whatever `nextMeeting` happens to be.
        let activeMeeting = inbox.currentMeeting(at: clockTick)
        let laterMeetings = inbox.remainingLaterToday(at: clockTick)
        return List {
            if let meeting = activeMeeting {
                Section {
                    MeetingCard(meeting: meeting,
                                onTap: { joinOrCalendar(meeting) },
                                onRsvp: { response in
                                    Task { await inbox.respondToMeeting(response, meetingId: meeting.id) }
                                },
                                onConflictTap: { conflictTarget = meeting })
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 0))
                        .contextMenu {
                            meetingContextMenu(for: meeting)
                        }
                }
            }
            if !laterMeetings.isEmpty {
                Section {
                    ForEach(laterMeetings) { meeting in
                        LaterMeetingRow(meeting: meeting,
                                        onTap: { joinOrCalendar(meeting) },
                                        onConflictTap: { conflictTarget = meeting })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .contextMenu {
                                meetingContextMenu(for: meeting)
                            }
                    }
                } header: {
                    sectionHeader(title: "Later today", count: laterMeetings.count)
                }
            }
            Section {
                if summary.chats.isEmpty {
                    emptyStateButton(label: "Mark unread: today's chats",
                                     icon: "bubble.left.fill",
                                     isBusy: inbox.activeBulkActivity == .todaysChats) {
                        Task { await inbox.markTodayChatsUnread() }
                    }
                }
                ForEach(summary.chats) { chat in
                    ChatRow(chat: chat, onTap: {
                        #if DEBUG
                        log.info("chat tap chatId=\(chat.chatId ?? "nil", privacy: .public)")
                        #endif
                        previewTarget = .chat(chat)
                    })
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if chat.chatId != nil {
                                Button {
                                    Task { await inbox.markChatRead(chat) }
                                } label: {
                                    Label("Mark Read", systemImage: "checkmark.bubble")
                                }
                                .tint(.green)
                            }
                        }
                        .contextMenu {
                            if chat.chatId != nil {
                                Button {
                                    previewTarget = .chat(chat, openComposer: true)
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                                Button {
                                    Task { await inbox.markChatRead(chat) }
                                } label: {
                                    Label("Mark read", systemImage: "checkmark.bubble")
                                }
                            }
                            if let url = chat.webUrl {
                                // Divider only when there's actual content
                                // above it — otherwise a webUrl-only chat
                                // would render with a leading separator.
                                if chat.chatId != nil { Divider() }
                                Button {
                                    UIPasteboard.general.string = url
                                } label: {
                                    Label("Copy chat link", systemImage: "doc.on.doc")
                                }
                                Button {
                                    openChat(chat)
                                } label: {
                                    Label("Open in Teams", systemImage: "arrow.up.forward.app")
                                }
                            }
                        }
                }
            } header: {
                sectionHeader(title: "Chats", count: summary.chats.count) {
                    HStack(spacing: 8) {
                        Button {
                            showCustomMessageSheet = true
                        } label: {
                            Text(inbox.customStatusMessage.isEmpty
                                ? "Set message…"
                                : inbox.customStatusMessage)
                                .font(.caption.italic())
                                .foregroundStyle(Brand.textMuted)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .accessibilityLabel(inbox.customStatusMessage.isEmpty
                            ? "Set custom status message"
                            : "Custom status message: \(inbox.customStatusMessage)")
                        .accessibilityHint("Tap to edit")
                        PresenceMenu(
                            presence: inbox.currentPresence,
                            isOutOfOffice: inbox.isOutOfOffice,
                            onSelect: { selection in
                                Task { await inbox.setPresence(selection) }
                            },
                            onSelectOutOfOffice: {
                                Task { await inbox.setOutOfOffice(!inbox.isOutOfOffice) }
                            }
                        )
                    }
                }
            }
            let extras = summary.totalUnreadEmails - summary.emails.count
            Section {
                if summary.emails.isEmpty {
                    emptyStateButton(label: "Mark unread: today's emails",
                                     icon: "envelope.badge",
                                     isBusy: inbox.activeBulkActivity == .todaysEmails) {
                        Task { await inbox.markTodayUnread() }
                    }
                }
                ForEach(summary.emails) { email in
                        let senderCount = email.fromAddress.isEmpty
                            ? 0
                            : senderCounts[email.fromAddress, default: 0]
                        let subjectCount = subjectCounts[email.subject.normalizedSubjectKey, default: 0]
                        // Look up the meeting only for actionable invites —
                        // skips the search for the common non-invite case.
                        let matchingMeeting = email.isInvite ? inbox.meetingMatching(email) : nil
                        EmailRow(
                            email: email,
                            matchingMeeting: matchingMeeting,
                            onTap: {
                                #if DEBUG
                                log.info("email tap id=\(email.id, privacy: .public)")
                                #endif
                                previewTarget = .email(email)
                            },
                            onRsvp: { response in
                                if let id = matchingMeeting?.id {
                                    Task { await inbox.respondToMeeting(response, meetingId: id) }
                                }
                            },
                            onConflictTap: {
                                if let m = matchingMeeting { conflictTarget = m }
                            }
                        )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    Task { await inbox.markRead(emailId: email.id) }
                                } label: {
                                    Label("Mark Read", systemImage: "envelope.open")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Task { await inbox.setFlagged(!email.isFlagged, emailId: email.id) }
                                } label: {
                                    Label(email.isFlagged ? "Unflag" : "Flag",
                                          systemImage: email.isFlagged ? "flag.slash" : "flag")
                                }
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    previewTarget = .email(email, openComposer: true)
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                                Button {
                                    Task { await inbox.markRead(emailId: email.id) }
                                } label: {
                                    Label("Mark read", systemImage: "envelope.open")
                                }
                                if senderCount > 1 {
                                    Button {
                                        Task { await inbox.markAllFromSenderRead(email.fromAddress) }
                                    } label: {
                                        Label("Mark read: \(senderCount) from this sender",
                                              systemImage: "envelope.open")
                                    }
                                }
                                if subjectCount > 1 {
                                    Button {
                                        Task { await inbox.markAllWithSubjectRead(email.subject) }
                                    } label: {
                                        Label("Mark read: \(subjectCount) with this subject",
                                              systemImage: "envelope.open")
                                    }
                                }
                                Button {
                                    Task { await inbox.setFlagged(!email.isFlagged, emailId: email.id) }
                                } label: {
                                    Label(email.isFlagged ? "Unflag" : "Flag",
                                          systemImage: email.isFlagged ? "flag.slash" : "flag")
                                }
                                if !email.fromAddress.isEmpty {
                                    Divider()
                                    Button {
                                        UIPasteboard.general.string = email.fromAddress
                                    } label: {
                                        Label("Copy sender address", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                    }
                } header: {
                    sectionHeader(
                        title: "Email",
                        count: summary.emails.count,
                        subtitle: {
                            if extras > 0 {
                                Text("+ \(extras) more unread")
                                    .font(.footnote)
                                    .foregroundStyle(Brand.textMuted)
                            }
                        },
                        trailing: {
                            BulkActionsMenu(
                                emails: summary.emails,
                                totalUnread: summary.totalUnreadEmails,
                                isShowingAll: inbox.showingAllEmails,
                                userMailDomain: inbox.userMailDomain,
                                isBusy: inbox.activeBulkActivity == .todaysEmails
                                    || inbox.activeBulkActivity == .flaggedEmails,
                                onMarkAllRead: { Task { await inbox.markAllVisibleRead() } },
                                onMarkOtherRead: { Task { await inbox.markOtherInboxRead() } },
                                onMarkMeetingNoticesRead: { Task { await inbox.markMeetingNoticesRead() } },
                                onMarkMailingListsRead: { Task { await inbox.markMailingListsRead() } },
                                onMarkExternalRead: { Task { await inbox.markExternalSendersRead() } },
                                onFlagAll: { Task { await inbox.setFlaggedAllVisible(true) } },
                                onUnflagAll: { Task { await inbox.setFlaggedAllVisible(false) } },
                                onShowAll: { Task { await inbox.setShowingAllEmails(true) } },
                                onShowCapped: { Task { await inbox.setShowingAllEmails(false) } },
                                onMarkTodayUnread: { Task { await inbox.markTodayUnread() } },
                                onMarkFlaggedUnread: { Task { await inbox.markFlaggedUnread() } }
                            )
                        }
                    )
                }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
        .refreshable { await inbox.refresh() }
    }

/// Inline action shown inside a section when there are no rows to
    /// display. Subtle styling (muted text, footnote font) so the empty
    /// state doesn't shout louder than the populated state.
    private func emptyStateButton(label: String,
                                  icon: String,
                                  isBusy: Bool = false,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(label)
            } icon: {
                if isBusy {
                    ProgressView().controlSize(.small).tint(Brand.textMuted)
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.footnote)
            .foregroundStyle(Brand.textMuted)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        sectionHeader(title: title, count: count, subtitle: { EmptyView() }, trailing: { EmptyView() })
    }

    private func sectionHeader<Trailing: View>(
        title: String,
        count: Int,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        sectionHeader(title: title, count: count, subtitle: { EmptyView() }, trailing: trailing)
    }

    private func sectionHeader<Subtitle: View, Trailing: View>(
        title: String,
        count: Int,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
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
            subtitle()
            Spacer(minLength: 8)
            trailing()
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func meetingContextMenu(for meeting: Meeting) -> some View {
        if meeting.hasConflict {
            Button {
                conflictTarget = meeting
            } label: {
                Label("Resolve conflict", systemImage: "exclamationmark.triangle")
            }
            Divider()
        }
        if meeting.responseStatus.canRsvp {
            if meeting.responseStatus != .accepted {
                Button {
                    Task { await inbox.respondToMeeting(.accepted, meetingId: meeting.id) }
                } label: {
                    Label("Accept", systemImage: "checkmark")
                }
            }
            if meeting.responseStatus != .tentativelyAccepted {
                Button {
                    Task { await inbox.respondToMeeting(.tentativelyAccepted, meetingId: meeting.id) }
                } label: {
                    Label("Tentative", systemImage: "questionmark")
                }
            }
            if meeting.responseStatus != .declined {
                Button(role: .destructive) {
                    Task { await inbox.respondToMeeting(.declined, meetingId: meeting.id) }
                } label: {
                    Label("Decline", systemImage: "xmark")
                }
            }
            Divider()
        }
        if let urlString = meeting.joinUrl {
            Button {
                UIPasteboard.general.string = urlString
            } label: {
                Label("Copy join link", systemImage: "doc.on.doc")
            }
        }
        if meeting.responseStatus.canRsvp,
           let email = meeting.organizerEmail, !email.isEmpty {
            Button {
                UIPasteboard.general.string = email
            } label: {
                Label("Copy organizer email", systemImage: "doc.on.doc")
            }
        }
        // Delete is hidden when Decline is already available — they
        // functionally do the same thing from the user's perspective
        // (get the meeting off the day's view). Decline is shown
        // whenever the user can RSVP and hasn't already declined.
        let canDecline = meeting.responseStatus.canRsvp && meeting.responseStatus != .declined
        if !canDecline {
            Divider()
            Button(role: .destructive) {
                Task { await inbox.deleteMeeting(meetingId: meeting.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Open the Teams join URL when there is one. Calendar-only events
    /// without a join URL no longer hand off elsewhere — tap is a no-op
    /// and the meeting context menu carries the remaining actions.
    private func joinOrCalendar(_ meeting: Meeting) {
        guard let urlString = meeting.joinUrl,
              let url = DeepLinkService.passthrough(urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func openChat(_ chat: ChatMessage) {
        openChatInTeams(webUrl: chat.webUrl)
    }

    @ViewBuilder
    private var notFetchedState: some View {
        if inbox.lastRefreshFailed {
            VStack(spacing: 12) {
                Spacer(minLength: 80)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Couldn't load")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Pull down to retry.")
                    .font(.callout)
                    .foregroundStyle(Brand.textMuted)
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        } else {
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
    }

}
