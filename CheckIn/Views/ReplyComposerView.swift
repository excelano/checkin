// ReplyComposerView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
#if DEBUG
import os
private let log = Logger(subsystem: "com.excelano.checkin", category: "compose")
#endif

/// Lean reply composer for both chats and emails. Swapped in place of
/// the preview body inside `MessagePreviewSheet` — no second sheet.
///
/// Email replies always use Graph's `/replyAll` endpoint (degrades to
/// reply-to-sender automatically when the message has only one
/// recipient). Chat replies post a new message into the existing
/// thread.
///
/// On Send the view goes to a loading state; Graph success calls
/// `onSent` (which dismisses the parent sheet); Graph failure surfaces
/// the error inline and leaves the composer state intact so the user
/// can retry without re-typing.
struct ReplyComposerView: View {
    var inbox: Inbox
    let target: MessagePreviewTarget
    let onBack: () -> Void
    let onSent: () -> Void

    @State private var draft: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Divider().overlay(Brand.bgDarker)
            replyingToLine
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .background(Brand.bg)
                .font(.body)
                .foregroundStyle(.white)
                .tint(Brand.accent)
                .focused($focused)
                .padding(.horizontal, 14)
                .disabled(isSending)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            Spacer()
            if isSending {
                ProgressView().tint(Brand.accent)
            } else {
                Button {
                    Task { await send() }
                } label: {
                    Text("Send")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(canSend ? Brand.accent : Brand.bgDarker)
                        .foregroundStyle(canSend ? .white : Brand.textMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
    }

    @ViewBuilder
    private var replyingToLine: some View {
        Text(replyingToText)
            .font(.caption)
            .foregroundStyle(Brand.textMuted)
            .lineLimit(2)
    }

    private var replyingToText: String {
        switch target.kind {
        case .email(let email):
            // Reply-all default. The "and N others" tail is a hint that
            // the reply will fan out — exact recipient list lives on
            // Graph's side and shows up in the user's Sent folder.
            return "Replying to \(email.from)\(otherRecipientsTail)"
        case .chat(let chat):
            if chat.otherParticipants.isEmpty {
                return "Replying in chat with \(chat.from)"
            }
            let others = chat.otherParticipants.count
            return "Replying in chat with \(chat.from) and \(others) other\(others == 1 ? "" : "s")"
        }
    }

    /// We don't currently fetch the full To/Cc list for an email — the
    /// summary row only carries the sender's name and address. So we
    /// can't show an accurate participant count in the "Replying to"
    /// line. Returning empty until we have a richer model; Graph still
    /// does the right thing on the wire.
    private var otherRecipientsTail: String { "" }

    private var canSend: Bool {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .chat(let chat) = target.kind, chat.chatId == nil { return false }
        return !isSending
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        #if DEBUG
        log.info("send begin")
        #endif
        isSending = true
        errorMessage = nil
        do {
            switch target.kind {
            case .email(let email):
                #if DEBUG
                log.info("send: replyAllToEmail id=\(email.id, privacy: .public) len=\(text.count, privacy: .public)")
                #endif
                try await inbox.replyAllToEmail(emailId: email.id, comment: text)
                #if DEBUG
                log.info("send: replyAllToEmail returned")
                #endif
            case .chat(let chat):
                guard let chatId = chat.chatId else {
                    throw GraphError.invalidResponse
                }
                #if DEBUG
                log.info("send: sendChatMessage chatId=\(chatId, privacy: .public) len=\(text.count, privacy: .public)")
                #endif
                try await inbox.sendChatMessage(chatId: chatId, content: text)
                #if DEBUG
                log.info("send: sendChatMessage returned")
                #endif
            }
            isSending = false
            #if DEBUG
            log.info("send: invoking onSent")
            #endif
            onSent()
            #if DEBUG
            log.info("send: onSent returned")
            #endif
        } catch {
            isSending = false
            #if DEBUG
            log.error("send failed: \(error.localizedDescription, privacy: .public)")
            #endif
            errorMessage = "Couldn't send: \(error.localizedDescription)"
        }
    }
}
