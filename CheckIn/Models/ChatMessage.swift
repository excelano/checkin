// ChatMessage.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    /// Graph chat id (the thread, not the individual message). Used to
    /// post a reply via `POST /me/chats/{chatId}/messages`. Optional
    /// because some legacy chats don't populate it — reply is disabled
    /// for those.
    let chatId: String?
    let topic: String
    let from: String
    let preview: String
    let sent: Date
    /// Other people in the thread besides you and the sender. Empty for
    /// 1:1 chats.
    let otherParticipants: [String]
    /// Graph-supplied `https://teams.microsoft.com/l/chat/...` URL. iOS
    /// routes it to the Teams app when installed. Optional because legacy
    /// chats and some tenants don't populate it.
    let webUrl: String?
}
