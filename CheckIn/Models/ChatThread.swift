// ChatThread.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// One message in a chat's recent transcript, as shown in the preview
/// sheet. The list is ordered oldest-first for display: the signed-in
/// user's own last message anchors the top, the unanswered replies follow,
/// and the newest sits nearest the Reply composer.
struct ChatThreadMessage: Identifiable {
    /// Graph chat-message id.
    let id: String
    /// Sender display name.
    let from: String
    /// True for the signed-in user's own messages, so the view can style
    /// the top anchor distinctly.
    let isFromMe: Bool
    /// HTML stripped to plain text, matching the chat preview.
    let body: String
    let sent: Date
}

/// A chat's walked transcript plus whether older history was left off
/// because the run back to the user's last message exceeded the cap.
/// `hasMore` drives the "Open in Teams for the full thread" hint.
struct ChatThread {
    let messages: [ChatThreadMessage]
    let hasMore: Bool
}
