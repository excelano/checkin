// ChatRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ChatRow: View {
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
                        Text(truncate(chat.preview, maxLen: 200))
                            .font(.body)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(4)
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
        .accessibilityHint("Preview message")
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
