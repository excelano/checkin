// MessagePreviewSheet.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

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

    @State private var showingComposer = false
    @State private var emailBody: String?
    @State private var bodyFetchFailed = false
    @State private var didAutoMarkRead = false
    /// Set when the user taps the orange conflict indicator on the
    /// meeting info row. Drives a sheet-on-sheet presentation of
    /// `ConflictResolutionSheet`. Same flow as the calendar card's
    /// conflict button, scoped to the preview's lifetime.
    @State private var conflictTarget: Meeting?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            if showingComposer {
                ReplyComposerView(
                    inbox: inbox,
                    target: target,
                    onBack: { showingComposer = false },
                    onSent: { dismiss() }
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
            await autoMarkReadIfNeeded()
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
            Divider().overlay(Brand.bgDarker)
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
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Brand.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Brand.bgDarker)
                .clipShape(Capsule())
            Spacer()
        }
    }

    /// Same Accept/Maybe/Decline triplet that lives on the meeting
    /// card and the email row. Routing the tap through
    /// `Inbox.respondToMeeting` keeps the meeting card, email list,
    /// and badge in sync — same downstream path as the calendar card.
    @ViewBuilder
    private func rsvpRow(for meeting: Meeting) -> some View {
        HStack(spacing: 8) {
            RsvpButton(response: .accepted, label: "Accept", icon: "checkmark",
                       outlineColor: Brand.accent) {
                Task {
                    await inbox.respondToMeeting(.accepted, meetingId: meeting.id)
                    dismiss()
                }
            }
            RsvpButton(response: .tentativelyAccepted, label: "Maybe", icon: "questionmark",
                       outlineColor: Brand.accent) {
                Task {
                    await inbox.respondToMeeting(.tentativelyAccepted, meetingId: meeting.id)
                    dismiss()
                }
            }
            RsvpButton(response: .declined, label: nil, icon: "xmark",
                       outlineColor: Brand.accent) {
                Task {
                    await inbox.respondToMeeting(.declined, meetingId: meeting.id)
                    dismiss()
                }
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
            }
        case .chat(let chat):
            VStack(alignment: .leading, spacing: 6) {
                if !chat.topic.isEmpty {
                    Text(chat.topic)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(chat.from)
                        .font(.subheadline)
                        .foregroundStyle(Brand.accent)
                    Spacer(minLength: 8)
                    Text(relativeTime(chat.sent))
                        .font(.caption)
                        .foregroundStyle(Brand.textMuted)
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
            // Chat preview body is already populated from the summary
            // fetch's `lastMessagePreview.body.content`. No second
            // round-trip needed.
            if chat.preview.isEmpty {
                Text("(no message body)")
                    .font(.body)
                    .foregroundStyle(Brand.textMuted)
                    .italic()
            } else {
                Text(chat.preview)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
        }
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
        dismiss()
    }
}
