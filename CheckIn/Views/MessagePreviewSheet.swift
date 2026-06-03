// MessagePreviewSheet.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI
#if DEBUG
import os
private let log = Logger(subsystem: "com.excelano.checkin", category: "preview")
#endif

/// Drives the preview sheet via `.sheet(item:)`. `openComposer` lets a
/// long-press "Reply" action jump straight to the composer without
/// showing the preview body first.
struct MessagePreviewTarget: Identifiable {
    enum Kind {
        case email(Email)
        case chat(ChatMessage)
    }

    let kind: Kind
    let openComposer: Bool

    var id: String {
        switch kind {
        case .email(let e): return "email-\(e.id)"
        case .chat(let c): return "chat-\(c.id.uuidString)"
        }
    }

    static func email(_ e: Email, openComposer: Bool = false) -> Self {
        .init(kind: .email(e), openComposer: openComposer)
    }

    static func chat(_ c: ChatMessage, openComposer: Bool = false) -> Self {
        .init(kind: .chat(c), openComposer: openComposer)
    }
}

/// Lean preview of a chat or email. Header at top, scrollable body in
/// the middle, action bar pinned to the bottom. Email opens swap to
/// `ReplyComposerView` in place; we don't push a second sheet.
struct MessagePreviewSheet: View {
    var inbox: Inbox
    let target: MessagePreviewTarget
    /// Parent-supplied close action. iPhone presents this view in a
    /// `.sheet(item:)` and the iPad split view renders it as the detail
    /// pane; both bind the same `previewTarget` and pass
    /// `{ previewTarget = nil }`. The previous `@Environment(\.dismiss)`
    /// silently did nothing in the split-view detail context.
    let onClose: () -> Void

    @State private var showingComposer = false
    @State private var emailBody: String?
    @State private var bodyFetchFailed = false
    @State private var didAutoMarkRead = false
    @State private var recipientsExpanded = false
    /// Set when the user taps the orange conflict indicator on the
    /// meeting info row. Drives a sheet-on-sheet presentation of
    /// `ConflictResolutionSheet`. Same flow as the calendar card's
    /// conflict button, scoped to the preview's lifetime.
    @State private var conflictTarget: Meeting?
    /// Chat transcript walked back to the user's last reply, loaded lazily
    /// when the sheet opens. Nil while loading; `threadFetchFailed` true
    /// when the fetch failed, in which case the sheet degrades to the
    /// single last-message preview it already holds.
    @State private var chatThread: ChatThread?
    @State private var threadFetchFailed = false

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            if showingComposer {
                ReplyComposerView(
                    inbox: inbox,
                    target: target,
                    onBack: { showingComposer = false },
                    onSent: { onClose() }
                )
            } else {
                previewBody
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $conflictTarget) { meeting in
            ConflictResolutionSheet(inbox: inbox, primaryMeetingId: meeting.id)
        }
        .task {
            #if DEBUG
            log.info("preview sheet task: openComposer=\(target.openComposer, privacy: .public), kind=\(targetKindString, privacy: .public)")
            #endif
            if target.openComposer && !showingComposer {
                showingComposer = true
                return
            }
            await loadBodyIfNeeded()
            await loadChatThreadIfNeeded()
            await autoMarkReadIfNeeded()
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                Divider().overlay(Brand.bgDarker)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Invitation chrome (calendar icon + time) is driven
                    // by the email — `isInvite` is the canonical source
                    // of truth. The conflict-triangle row inside hides
                    // itself when `matchingMeeting` is nil or has no
                    // conflict.
                    if let invite = inviteData {
                        meetingInfoRow(start: invite.start, end: invite.end)
                    }
                    bodyText
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Brand.bgDarker)
            if let meeting = matchingMeeting {
                switch meeting.responseStatus {
                case .notResponded:
                    rsvpRow(for: meeting)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                case .accepted, .tentativelyAccepted, .declined:
                    respondedPill(label: meeting.responseStatus.displayLabel ?? "")
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                case .none, .organizer:
                    EmptyView()
                }
            } else if inviteData != nil {
                respondedPill(label: "Removed")
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    /// Tuple capturing the data we need to render the invitation
    /// chrome from the email itself: start/end always come from the
    /// `eventMessage` cast fields, so they're available on every
    /// invite — not gated on having a matching Meeting.
    private var inviteData: (start: Date, end: Date)? {
        guard case .email(let email) = target.kind,
              email.isInvite,
              let start = email.meetingStart,
              let end = email.meetingEnd else { return nil }
        return (start, end)
    }

    /// Date + time on its own line, conflict warning (when applicable)
    /// on a separate line below in orange and tappable to open the
    /// conflict resolver — same flow as the calendar card's button.
    /// Time comes from the email's own `eventMessage` fields; the
    /// conflict line requires `matchingMeeting` (only meetings the
    /// matcher resolved carry overlap info).
    @ViewBuilder
    private func meetingInfoRow(start: Date, end: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.footnote)
                Text(formatMeetingTime(start, end: end))
                    .font(.footnote)
            }
            .foregroundStyle(Brand.textMuted)
            if let meeting = matchingMeeting, meeting.hasConflict {
                Button {
                    conflictTarget = meeting
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.footnote)
                        Text("Overlaps another meeting")
                            .font(.footnote)
                    }
                    .foregroundStyle(.orange)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open conflict resolution")
            }
        }
    }

    /// Non-interactive status pill shown in place of the RSVP buttons.
    /// Carries either the user's response ("Accepted" / "Tentative" /
    /// "Declined") or "Removed" when the invite has no corresponding
    /// event in the calendar. Mirrors `EmailRow`'s responded pill so
    /// both surfaces convey the same state with the same chrome.
    private func respondedPill(label: String) -> some View {
        HStack {
            RespondedPill(label: label, style: .filled(Brand.bgDarker))
            Spacer()
        }
    }

    /// Same Accept/Maybe/Decline triplet that lives on the meeting
    /// card and the email row. Routing the tap through
    /// `Inbox.respondToMeeting` keeps the meeting card, email list,
    /// and badge in sync — same downstream path as the calendar card.
    private func rsvpRow(for meeting: Meeting) -> some View {
        RsvpRow(outlineColor: Brand.accent) { response in
            Task {
                await inbox.respondToMeeting(response, meetingId: meeting.id)
                onClose()
            }
        }
    }

    /// Recomputed each render so an RSVP made elsewhere (Outlook,
    /// another device) while the sheet is open is reflected the moment
    /// the summary refreshes. Only set for actionable invites whose
    /// underlying meeting is in today's summary window.
    private var matchingMeeting: Meeting? {
        guard case .email(let email) = target.kind, email.isInvite else { return nil }
        return inbox.meetingMatching(email)
    }

    @ViewBuilder
    private var header: some View {
        switch target.kind {
        case .email(let email):
            VStack(alignment: .leading, spacing: 6) {
                Text(email.subject)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(email.from)
                        .font(.subheadline)
                        .foregroundStyle(Brand.accent)
                    Spacer(minLength: 8)
                    Text(relativeTime(email.received))
                        .font(.caption)
                        .foregroundStyle(Brand.textMuted)
                }
                recipientRow(for: email)
                attachmentIndicator(for: email)
            }
        case .chat(let chat):
            // Sender + time are intentionally omitted: the transcript below
            // carries every message's author and time, so a header row would
            // just duplicate its newest entry. Only the chat-level context
            // the transcript doesn't show (topic, participants) lives here.
            VStack(alignment: .leading, spacing: 6) {
                if !chat.topic.isEmpty {
                    Text(chat.topic)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if !chat.otherParticipants.isEmpty {
                    Text("with \(chat.otherParticipants.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Brand.textMuted)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Email always has a header (subject + sender). A chat shows one only
    /// when it carries context the transcript doesn't — a topic or other
    /// participants — so a 1:1 chat opens straight into its transcript with
    /// no empty chrome.
    private var showsHeader: Bool {
        switch target.kind {
        case .email:
            return true
        case .chat(let chat):
            return !chat.topic.isEmpty || !chat.otherParticipants.isEmpty
        }
    }

    /// Paperclip + "Has attachments" caption shown when Graph reports the
    /// message carries any attachment. Graph's `hasAttachments` flips
    /// `true` for inline images as well (signatures, embedded HTML
    /// screenshots), so this is a presence hint, not a guarantee of a
    /// user-attached file. We avoid loading `/attachments` to keep the
    /// preview free of extra Graph round-trips.
    @ViewBuilder
    private func attachmentIndicator(for email: Email) -> some View {
        if email.hasAttachments {
            HStack(spacing: 4) {
                Image(systemName: "paperclip")
                    .font(.caption)
                Text("Has attachments")
                    .font(.caption)
            }
            .foregroundStyle(Brand.textMuted)
            .accessibilityElement(children: .combine)
        }
    }

    /// Apple Mail-style expandable recipient row. Collapsed: a one-line
    /// summary like "also to: Alice, Bob +3". Expanded: stacked "to:"
    /// and "cc:" lines. Hidden entirely when the email has no other
    /// recipients beyond the sender and the signed-in user.
    @ViewBuilder
    private func recipientRow(for email: Email) -> some View {
        let tos = displayedRecipients(email.toRecipients)
        let ccs = displayedRecipients(email.ccRecipients)
        if !tos.isEmpty || !ccs.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    recipientsExpanded.toggle()
                }
            } label: {
                if recipientsExpanded {
                    expandedRecipients(tos: tos, ccs: ccs)
                } else {
                    collapsedRecipients(tos: tos, ccs: ccs)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recipientsExpanded ? "Hide recipients" : "Show recipients")
        }
    }

    private func collapsedRecipients(tos: [Recipient], ccs: [Recipient]) -> some View {
        HStack(spacing: 4) {
            Text(compactRecipientSummary(tos: tos, ccs: ccs))
                .font(.caption)
                .foregroundStyle(Brand.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(Brand.textMuted)
        }
    }

    private func expandedRecipients(tos: [Recipient], ccs: [Recipient]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !tos.isEmpty {
                Text("to: \(tos.map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Brand.textMuted)
                    .multilineTextAlignment(.leading)
            }
            if !ccs.isEmpty {
                Text("cc: \(ccs.map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Brand.textMuted)
                    .multilineTextAlignment(.leading)
            }
            Image(systemName: "chevron.up")
                .font(.caption2)
                .foregroundStyle(Brand.textMuted)
        }
    }

    /// First two names of the combined To+Cc list followed by "+N" when
    /// more remain. Kept short so the row fits on a single line in the
    /// medium sheet detent.
    private func compactRecipientSummary(tos: [Recipient], ccs: [Recipient]) -> String {
        let all = tos + ccs
        let names = all.map(\.displayName)
        let head = names.prefix(2).joined(separator: ", ")
        let extra = names.count - 2
        if extra > 0 {
            return "also to: \(head) +\(extra)"
        }
        return "also to: \(head)"
    }

    /// Strip the signed-in user out of a recipient list so the UI shows
    /// only "the other people on this email." Case-insensitive on the
    /// SMTP address. Falls through to the unfiltered list when we
    /// haven't fetched the user's mail yet — better to show too many
    /// than to drop everyone.
    private func displayedRecipients(_ recipients: [Recipient]) -> [Recipient] {
        let me = inbox.currentUserMail.lowercased()
        guard !me.isEmpty else { return recipients }
        return recipients.filter { $0.address.lowercased() != me }
    }

    @ViewBuilder
    private var bodyText: some View {
        switch target.kind {
        case .email:
            if let body = emailBody {
                if body.isEmpty {
                    // For invites with empty bodies (the common case)
                    // the meeting info row above is the actual content
                    // — skip the placeholder so the sheet stays tight.
                    if inviteData == nil {
                        Text("(no message body)")
                            .font(.body)
                            .foregroundStyle(Brand.textMuted)
                            .italic()
                    }
                } else {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            } else if bodyFetchFailed {
                Text("Couldn't load the message body. Pull down to dismiss and try again.")
                    .font(.body)
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
                    .tint(Brand.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        case .chat(let chat):
            chatTranscript(for: chat)
        }
    }

    /// The chat preview body. On open we already hold the last message
    /// (`chat.preview`) from the summary fetch, so we render it
    /// immediately and load the earlier run back to the user's last reply
    /// in above it. The fetched transcript replaces the seed when it
    /// lands; a failed fetch degrades silently to the seed alone.
    @ViewBuilder
    private func chatTranscript(for chat: ChatMessage) -> some View {
        if let thread = chatThread, !thread.messages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if thread.hasMore {
                    earlierInTeamsLine(chat)
                }
                ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                    let previous = index > 0 ? thread.messages[index - 1] : nil
                    chatMessageRow(message, showSender: startsNewSenderRun(message, after: previous))
                }
            }
        } else if chatThread == nil && !threadFetchFailed {
            // Loading: seed with the message we already have, spinner above
            // for the earlier context still arriving.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Brand.accent)
                    Text("Loading earlier messages\u{2026}")
                        .font(.caption)
                        .foregroundStyle(Brand.textMuted)
                }
                chatSeedBody(chat.preview)
            }
        } else {
            // Loaded-but-empty or failed: degrade to the single last message.
            chatSeedBody(chat.preview)
        }
    }

    /// The seed / fallback rendering: the one last message we already hold,
    /// matching the sheet's prior chat behavior.
    @ViewBuilder
    private func chatSeedBody(_ text: String) -> some View {
        if text.isEmpty {
            Text("(no message body)")
                .font(.body)
                .foregroundStyle(Brand.textMuted)
                .italic()
        } else {
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        }
    }

    /// One transcript message. The sender label is shown only at the start
    /// of a run from the same person, so consecutive messages group under a
    /// single name. The user's own anchor message sits in a subtle card so
    /// "where I left off" reads at a glance.
    @ViewBuilder
    private func chatMessageRow(_ message: ChatThreadMessage, showSender: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showSender {
                HStack(spacing: 6) {
                    Text(message.isFromMe ? "You" : message.from)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(message.isFromMe ? Brand.accent : Brand.textMuted)
                    Text(relativeTime(message.sent))
                        .font(.caption2)
                        .foregroundStyle(Brand.textMuted)
                }
            }
            Text(message.body.isEmpty ? "(no message text)" : message.body)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(message.isFromMe ? 8 : 0)
        .background(
            message.isFromMe ? Brand.bgDarker : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    /// True when `message` begins a new run of messages from a different
    /// author than the one above it. "You" is its own author so a stretch
    /// of the user's own messages groups together too.
    private func startsNewSenderRun(_ message: ChatThreadMessage,
                                    after previous: ChatThreadMessage?) -> Bool {
        guard let previous else { return true }
        if message.isFromMe != previous.isFromMe { return true }
        return !message.isFromMe && message.from != previous.from
    }

    /// Tappable hint shown at the top of the transcript when the run back
    /// to the user's last reply was longer than the cap, handing the full
    /// history off to Teams.
    @ViewBuilder
    private func earlierInTeamsLine(_ chat: ChatMessage) -> some View {
        Button {
            openChatInTeams(webUrl: chat.webUrl)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                Text("Earlier messages are in Teams")
                    .font(.caption)
            }
            .foregroundStyle(Brand.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open this chat in Teams")
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 12) {
            if canMarkUnread {
                Button {
                    Task { await markUnreadAndDismiss() }
                } label: {
                    Label("Mark unread", systemImage: markUnreadSymbol)
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.accent)
            }
            Spacer()
            Button {
                showingComposer = true
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(canReply ? Brand.accent : Brand.bgDarker)
                    .foregroundStyle(canReply ? .white : Brand.textMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canReply)
        }
    }

    /// Email always offers Mark Unread (we auto-marked it on open).
    /// Chat offers it only when we have a `chatId` to address the
    /// Graph mutation. The same auto-mark-on-open logic applies.
    private var canMarkUnread: Bool {
        switch target.kind {
        case .email: return true
        case .chat(let chat): return chat.chatId != nil
        }
    }

    private var markUnreadSymbol: String {
        switch target.kind {
        case .email: return "envelope.badge"
        case .chat: return "bubble.left.fill"
        }
    }

    #if DEBUG
    private var targetKindString: String {
        switch target.kind {
        case .email(let e): return "email[\(e.id)]"
        case .chat(let c): return "chat[\(c.chatId ?? "no-chat-id")]"
        }
    }
    #endif

    /// True when we have somewhere to send the reply. Email always
    /// supports reply-all (Graph degrades gracefully on single
    /// recipient). Chat requires a chatId.
    private var canReply: Bool {
        switch target.kind {
        case .email: return true
        case .chat(let chat): return chat.chatId != nil
        }
    }

    private func loadBodyIfNeeded() async {
        guard case .email(let email) = target.kind, emailBody == nil else { return }
        do {
            let raw = try await inbox.fetchEmailBody(emailId: email.id)
            #if DEBUG
            // Diagnostic hook for the "weird wrap / mystery character"
            // class of problem. `print()` flows through devicectl's
            // `--console` capture; os.Logger does not. Filter the
            // launched stream with `grep "CHECKIN-DEBUG"`. Kept in
            // place rather than re-added per-investigation because
            // wiring it from scratch under time pressure is annoying.
            // Also dumps email.preview (Graph's bodyPreview, post-
            // cleanEmailPreview) so the summary-row and preview-sheet
            // sources can be compared in one capture.
            let visibleRaw = raw
                .replacingOccurrences(of: "\r\n", with: "[CRLF]")
                .replacingOccurrences(of: "\n", with: "[LF]")
                .replacingOccurrences(of: "\r", with: "[CR]")
            let visiblePreview = email.preview
                .replacingOccurrences(of: "\r\n", with: "[CRLF]")
                .replacingOccurrences(of: "\n", with: "[LF]")
                .replacingOccurrences(of: "\r", with: "[CR]")
            print("CHECKIN-DEBUG email.preview (len=\(email.preview.count)): \(visiblePreview)")
            print("CHECKIN-DEBUG email body raw (len=\(raw.count)): \(visibleRaw)")
            #endif
            emailBody = cleanEmailPreview(raw)
        } catch {
            bodyFetchFailed = true
        }
    }

    /// Load the chat's recent transcript when the sheet opens. No-op for
    /// emails and for chats without a `chatId` (the seed preview stands in).
    /// On failure the sheet keeps showing the seed message it already holds.
    private func loadChatThreadIfNeeded() async {
        guard case .chat(let chat) = target.kind,
              let chatId = chat.chatId,
              chatThread == nil, !threadFetchFailed else { return }
        do {
            chatThread = try await inbox.fetchChatThread(chatId: chatId)
        } catch {
            threadFetchFailed = true
        }
    }

    private func autoMarkReadIfNeeded() async {
        guard !didAutoMarkRead else { return }
        switch target.kind {
        case .email(let email):
            // Email body has to load before we mark read — otherwise a
            // fetch failure would silently mark unread emails as read.
            guard emailBody != nil else { return }
            didAutoMarkRead = true
            await inbox.markRead(emailId: email.id)
        case .chat(let chat):
            // Chat preview body is preloaded with the summary, so no
            // fetch gate — opening the sheet implies the user saw it.
            guard chat.chatId != nil else { return }
            didAutoMarkRead = true
            await inbox.markChatRead(chat)
        }
    }

    private func markUnreadAndDismiss() async {
        switch target.kind {
        case .email(let email):
            await inbox.markUnread(email)
        case .chat(let chat):
            await inbox.markChatUnread(chat)
        }
        onClose()
    }
}
