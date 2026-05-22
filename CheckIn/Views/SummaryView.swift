// SummaryView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import UIKit

struct SummaryView: View {
    var inbox: Inbox
    var authService: AuthService

    @State private var showSettings = false
    @State private var showConflictSheet = false

    var body: some View {
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
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(authService: authService)
        }
        .sheet(isPresented: $showConflictSheet) {
            ConflictResolutionSheet(inbox: inbox)
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
        HStack {
            // Reserves the slot for a future action; keeps the title
            // centered against the gear button on the right.
            Color.clear.frame(width: 44, height: 44)

            Spacer()

            Text("CheckIn")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)

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
        .padding(.top, 8)
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = inbox.summary {
            if summary.meeting == nil
                && summary.laterToday.isEmpty
                && summary.emails.isEmpty
                && summary.chats.isEmpty {
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
                                onTap: { joinOrCalendar(meeting) },
                                onRsvp: { response in
                                    Task { await inbox.respondToMeeting(response) }
                                })
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 6, trailing: 0))
                        .contextMenu {
                            meetingContextMenu(for: meeting)
                        }
                }
            }
            if !summary.laterToday.isEmpty {
                Section {
                    ForEach(summary.laterToday) { meeting in
                        LaterMeetingRow(meeting: meeting, onTap: { joinOrCalendar(meeting) })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .contextMenu {
                                meetingContextMenu(for: meeting)
                            }
                    }
                } header: {
                    sectionHeader(title: "Later today", count: summary.laterToday.count)
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
                    sectionHeader(title: "Chats", count: summary.chats.count)
                }
            }
            if !summary.emails.isEmpty {
                let extras = summary.totalUnreadEmails - summary.emails.count
                Section {
                    ForEach(summary.emails) { email in
                        let senderCount = summary.emails.filter {
                            !email.fromAddress.isEmpty && $0.fromAddress == email.fromAddress
                        }.count
                        let subjectKey = email.subject.normalizedSubjectKey
                        let subjectCount = subjectKey.isEmpty ? 0 : summary.emails.filter {
                            $0.subject.normalizedSubjectKey == subjectKey
                        }.count
                        EmailRow(email: email, onTap: { replyTo(email) })
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
                                    Task { await inbox.markRead(emailId: email.id) }
                                } label: {
                                    Label("Mark read", systemImage: "envelope.open")
                                }
                                Button {
                                    Task { await inbox.setFlagged(!email.isFlagged, emailId: email.id) }
                                } label: {
                                    Label(email.isFlagged ? "Unflag" : "Flag",
                                          systemImage: email.isFlagged ? "flag.slash" : "flag")
                                }
                                if senderCount > 1 || subjectCount > 1 {
                                    Divider()
                                    if senderCount > 1 {
                                        Button {
                                            Task { await inbox.markAllFromSenderRead(email.fromAddress) }
                                        } label: {
                                            Label("Mark \(senderCount) from this sender read",
                                                  systemImage: "envelope.open")
                                        }
                                    }
                                    if subjectCount > 1 {
                                        Button {
                                            Task { await inbox.markAllWithSubjectRead(email.subject) }
                                        } label: {
                                            Label("Mark \(subjectCount) with this subject read",
                                                  systemImage: "envelope.open")
                                        }
                                    }
                                }
                                if !email.fromAddress.isEmpty {
                                    Divider()
                                    Button {
                                        UIPasteboard.general.string = email.fromAddress
                                    } label: {
                                        Label("Copy sender address", systemImage: "doc.on.doc")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    Task { await inbox.deleteEmail(emailId: email.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
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
                                onMarkAllRead: { Task { await inbox.markAllVisibleRead() } },
                                onMarkOtherRead: { Task { await inbox.markOtherInboxRead() } },
                                onMarkMeetingNoticesRead: { Task { await inbox.markMeetingNoticesRead() } },
                                onMarkMailingListsRead: { Task { await inbox.markMailingListsRead() } },
                                onFlagAll: { Task { await inbox.setFlaggedAllVisible(true) } },
                                onUnflagAll: { Task { await inbox.setFlaggedAllVisible(false) } },
                                onShowAll: { Task { await inbox.setShowingAllEmails(true) } },
                                onShowCapped: { Task { await inbox.setShowingAllEmails(false) } }
                            )
                        }
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Brand.bg)
        .refreshable { await inbox.refresh() }
    }

    private var emptyDayScrollable: some View {
        ScrollView {
            emptyDayState
                .padding(.top, 60)
        }
        .refreshable { await inbox.refresh() }
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
            Spacer()
            trailing()
        }
    }

    @ViewBuilder
    private func meetingContextMenu(for meeting: Meeting) -> some View {
        if meeting.hasConflict {
            Button {
                showConflictSheet = true
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
        Button {
            deepLink(DeepLinkService.outlookCalendar)
        } label: {
            Label("Open Outlook Calendar", systemImage: "calendar")
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
            Text("No meetings in the next 24 hours, no pending chats, no unread emails.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func deepLink(_ url: URL?) {
        guard let url, UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

private struct BulkActionsMenu: View {
    let emails: [Email]
    let totalUnread: Int
    let isShowingAll: Bool
    let onMarkAllRead: () -> Void
    let onMarkOtherRead: () -> Void
    let onMarkMeetingNoticesRead: () -> Void
    let onMarkMailingListsRead: () -> Void
    let onFlagAll: () -> Void
    let onUnflagAll: () -> Void
    let onShowAll: () -> Void
    let onShowCapped: () -> Void

    var body: some View {
        let unflaggedCount = emails.filter { !$0.isFlagged }.count
        let flaggedCount = emails.count - unflaggedCount
        let otherCount = emails.filter { $0.inferenceClassification == "other" }.count
        let meetingNoticeCount = emails.filter(\.isMeetingNotice).count
        let mailingListCount = emails.filter { $0.isMailingList }.count
        let canExpand = !isShowingAll && totalUnread > emails.count

        Menu {
            Button(action: onMarkAllRead) {
                Label("Mark \(emails.count) read", systemImage: "envelope.open")
            }
            if otherCount > 0 {
                Button(action: onMarkOtherRead) {
                    Label("Mark \(otherCount) in Other read", systemImage: "tray.2")
                }
            }
            if meetingNoticeCount > 0 {
                Button(action: onMarkMeetingNoticesRead) {
                    Label("Mark \(meetingNoticeCount) meeting notices read", systemImage: "calendar.badge.checkmark")
                }
            }
            if mailingListCount > 0 {
                Button(action: onMarkMailingListsRead) {
                    Label("Mark \(mailingListCount) mailing lists read", systemImage: "newspaper")
                }
            }
            if unflaggedCount > 0 {
                Button(action: onFlagAll) {
                    Label("Flag \(unflaggedCount)", systemImage: "flag")
                }
            }
            if flaggedCount > 0 {
                Button(action: onUnflagAll) {
                    Label("Unflag \(flaggedCount)", systemImage: "flag.slash")
                }
            }
            if canExpand {
                Divider()
                Button(action: onShowAll) {
                    Label("Show all \(totalUnread)", systemImage: "list.bullet")
                }
            } else if isShowingAll {
                Divider()
                Button(action: onShowCapped) {
                    Label("Show top 20", systemImage: "list.bullet")
                }
            }
        } label: {
            ZStack {
                // Invisible text reserves the same vertical space as the
                // count pill, so the two capsules render the same height
                // despite an SF Symbol having no ascender/descender.
                Text("0").opacity(0)
                Image(systemName: "ellipsis")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(Brand.bgDarker)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Bulk email actions")
    }
}

private struct MeetingCard: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onRsvp: (MeetingResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        // TimelineView re-renders this label every 15s so
                        // "in 5 min" naturally counts down and flips to
                        // "Starting soon" without needing a refresh.
                        TimelineView(.periodic(from: .now, by: 15)) { _ in
                            Text(untilTime(meeting.start))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isMeetingImminent(meeting.start) ? .orange : Brand.accent)
                        }
                        if !meeting.organizer.isEmpty {
                            Text("with \(meeting.organizer)")
                                .font(.subheadline)
                                .foregroundStyle(Brand.textMuted)
                                .lineLimit(2)
                        }
                    }
                    if meeting.hasConflict {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Overlaps another meeting")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Open in Outlook calendar")

            switch meeting.responseStatus {
            case .notResponded:
                rsvpRow
            case .accepted, .tentativelyAccepted, .declined:
                respondedPill
            case .none, .organizer:
                EmptyView()
            }
        }
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rsvpRow: some View {
        HStack(spacing: 8) {
            rsvpButton(.accepted, label: "Accept", icon: "checkmark")
            rsvpButton(.tentativelyAccepted, label: "Maybe", icon: "questionmark")
            rsvpButton(.declined, label: nil, icon: "xmark")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func rsvpButton(_ response: MeetingResponse, label: String?, icon: String) -> some View {
        Button {
            onRsvp(response)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                if let label {
                    Text(label).font(.subheadline.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Brand.bg)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: response))
    }

    private func accessibilityLabel(for response: MeetingResponse) -> String {
        switch response {
        case .accepted: return "Accept meeting"
        case .tentativelyAccepted: return "Tentatively accept meeting"
        case .declined: return "Decline meeting"
        default: return ""
        }
    }

    private var respondedPill: some View {
        HStack {
            Text(respondedLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Brand.bg)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var respondedLabel: String {
        switch meeting.responseStatus {
        case .accepted: return "Accepted"
        case .tentativelyAccepted: return "Tentative"
        case .declined: return "Declined"
        default: return ""
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Next meeting", meeting.subject, untilTime(meeting.start)]
        if !meeting.organizer.isEmpty { parts.append("with \(meeting.organizer)") }
        return parts.joined(separator: ", ")
    }
}

private struct ConflictResolutionSheet: View {
    var inbox: Inbox

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("These meetings overlap. Adjust your response on one or both.")
                        .font(.footnote)
                        .foregroundStyle(Brand.textMuted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    if let meeting = inbox.summary?.meeting {
                        ConflictMeetingRow(
                            meeting: meeting,
                            onRsvp: { response in
                                Task { await inbox.respondToMeeting(response, meetingId: meeting.id) }
                            },
                            onDelete: {
                                Task { await inbox.deleteMeeting(meetingId: meeting.id) }
                            }
                        )
                        ForEach(conflicting(with: meeting)) { other in
                            ConflictMeetingRow(
                                meeting: other,
                                onRsvp: { response in
                                    Task { await inbox.respondToMeeting(response, meetingId: other.id) }
                                },
                                onDelete: {
                                    Task { await inbox.deleteMeeting(meetingId: other.id) }
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.bg)
            .navigationTitle("Overlapping meetings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func conflicting(with meeting: Meeting) -> [Meeting] {
        (inbox.summary?.laterToday ?? []).filter { other in
            other.start < meeting.end && meeting.start < other.end
        }
    }
}

private struct ConflictMeetingRow: View {
    let meeting: Meeting
    let onRsvp: (MeetingResponse) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.subject)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("\(formatTimeOfDay(meeting.start)) \u{2013} \(formatTimeOfDay(meeting.end))")
                .font(.subheadline)
                .foregroundStyle(Brand.accent)
            if meeting.responseStatus.canRsvp, !meeting.organizer.isEmpty {
                Text("with \(meeting.organizer)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
            }
            if let label = respondedLabel {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Brand.bg)
                    .clipShape(Capsule())
            }
            if meeting.responseStatus.canRsvp {
                HStack(spacing: 8) {
                    rsvpButton(.accepted, label: "Accept", icon: "checkmark")
                    rsvpButton(.tentativelyAccepted, label: "Maybe", icon: "questionmark")
                    rsvpButton(.declined, label: "Decline", icon: "xmark")
                }
            } else {
                deleteButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rsvpButton(_ response: MeetingResponse, label: String, icon: String) -> some View {
        Button {
            onRsvp(response)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.subheadline.weight(.semibold))
                Text(label).font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(meeting.responseStatus == response ? Brand.accent.opacity(0.25) : Brand.bg)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 4) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                Text("Delete").font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Brand.bg)
            .foregroundStyle(.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var respondedLabel: String? {
        switch meeting.responseStatus {
        case .accepted: return "Accepted"
        case .tentativelyAccepted: return "Tentative"
        case .declined: return "Declined"
        case .organizer, .none, .notResponded: return nil
        }
    }
}

private struct LaterMeetingRow: View {
    let meeting: Meeting
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(Brand.accent)
                    .frame(width: 20)
                Text(formatTimeOfDay(meeting.start))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                Text(meeting.subject)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatTimeOfDay(meeting.start)): \(meeting.subject)")
        .accessibilityHint("Open in Teams or Outlook calendar")
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
                    if !email.preview.isEmpty {
                        Text(email.preview)
                            .font(.footnote)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 14)
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
                    if let line = participantsLine {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Teams chat from \(chat.from)")
        .accessibilityHint("Open in Teams")
    }

    /// Empty for 1:1 chats. Full "with A, B, C" when the joined names fit
    /// in about two caption lines; collapses to "with A, B +N" past that.
    private var participantsLine: String? {
        guard !chat.otherParticipants.isEmpty else { return nil }
        let joined = chat.otherParticipants.joined(separator: ", ")
        if joined.count <= 95 { return "with \(joined)" }
        let head = chat.otherParticipants.prefix(2).joined(separator: ", ")
        let extra = chat.otherParticipants.count - 2
        return "with \(head) +\(extra)"
    }
}
