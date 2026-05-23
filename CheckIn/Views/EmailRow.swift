// EmailRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct EmailRow: View {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Preview message")
    }

    private var accessibilityLabel: String {
        let flagPrefix = email.isFlagged ? "Flagged email" : "Email"
        return "\(flagPrefix) from \(email.from): \(email.subject)"
    }
}
