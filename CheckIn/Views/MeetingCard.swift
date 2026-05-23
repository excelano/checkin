// MeetingCard.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct MeetingCard: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onRsvp: (MeetingResponse) -> Void
    let onConflictTap: () -> Void

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
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, meeting.hasConflict ? 6 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Join meeting in Teams")

            if meeting.hasConflict {
                Button(action: onConflictTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Overlaps another meeting")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }

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
            RsvpButton(response: .accepted, label: "Accept", icon: "checkmark") {
                onRsvp(.accepted)
            }
            RsvpButton(response: .tentativelyAccepted, label: "Maybe", icon: "questionmark") {
                onRsvp(.tentativelyAccepted)
            }
            RsvpButton(response: .declined, label: nil, icon: "xmark") {
                onRsvp(.declined)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var respondedPill: some View {
        if let label = meeting.responseStatus.displayLabel {
            HStack {
                Text(label)
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
    }

    private var accessibilityLabel: String {
        var parts = ["Next meeting", meeting.subject, untilTime(meeting.start)]
        if !meeting.organizer.isEmpty { parts.append("with \(meeting.organizer)") }
        return parts.joined(separator: ", ")
    }
}
