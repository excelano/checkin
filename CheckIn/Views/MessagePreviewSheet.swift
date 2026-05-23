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
                bodyText
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Brand.bgDarker)
            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
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
                    Text("(no message body)")
                        .font(.body)
                        .foregroundStyle(Brand.textMuted)
                        .italic()
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
            if case .email = target.kind {
                Button {
                    Task { await markUnreadAndDismiss() }
                } label: {
                    Label("Mark unread", systemImage: "envelope.badge")
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
        guard case .email(let email) = target.kind,
              !didAutoMarkRead,
              emailBody != nil else { return }
        didAutoMarkRead = true
        await inbox.markRead(emailId: email.id)
    }

    private func markUnreadAndDismiss() async {
        if case .email(let email) = target.kind {
            await inbox.markUnread(email)
        }
        dismiss()
    }
}
