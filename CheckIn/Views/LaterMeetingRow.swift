// LaterMeetingRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct LaterMeetingRow: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onConflictTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
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
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(formatTimeOfDay(meeting.start)): \(meeting.subject)")
            .accessibilityHint("Join meeting in Teams")

            if meeting.hasConflict {
                Button(action: onConflictTap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
