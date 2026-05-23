// EmailRow.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct EmailRow: View {
    let email: Email
    /// Set when this email is a meeting invitation AND the underlying
    /// meeting is in our current summary window. Drives the inline
    /// RSVP buttons and the subject-line conflict triangle. Nil for
    /// everything else.
    let matchingMeeting: Meeting?
    let onTap: () -> Void
    let onRsvp: (MeetingResponse) -> Void
    /// Called when the user taps the orange conflict triangle on the
    /// subject line. SummaryView routes this to its existing conflict-
    /// resolution sheet so the email surface uses the same flow as
    /// the "Later today" rows.
    let onConflictTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area: previewable email body. Uses .onTapGesture
            // instead of an outer Button so the nested triangle Button
            // can take its own tap reliably — nested SwiftUI Buttons
            // have inconsistent behavior across iOS versions.
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
                    subjectLine
                    if !email.preview.isEmpty {
                        Text(email.preview)
                            .font(.body)
                            .foregroundStyle(Brand.textMuted)
                            .lineLimit(4)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Preview message")
            .accessibilityAddTraits(.isButton)

            if let meeting = matchingMeeting {
                meetingInfoRow(for: meeting)
                    .padding(.horizontal, 14)
                    .padding(.bottom, meeting.responseStatus == .notResponded ? 12 : 14)
                if meeting.responseStatus == .notResponded {
                    rsvpRow
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    /// Subject text with the conflict triangle right-justified on the
    /// same row when this invite's meeting overlaps another. Placing
    /// the triangle here puts it close to the subject (its natural
    /// grouping) and far from the Decline button on the RSVP row.
    private var subjectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(email.subject)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(2)
            if matchingMeeting?.hasConflict == true {
                Spacer(minLength: 6)
                Button(action: onConflictTap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Overlaps another meeting")
                .accessibilityHint("Open conflict resolution")
            }
        }
    }

    /// Date + time on the left, plus a small right-justified
    /// responded-state pill ("Accepted" / "Tentative" / "Declined")
    /// when the user has already responded. The conflict triangle
    /// lives on the subject line above; the responded pill sits
    /// directly under it, vertically aligned with the right edge.
    private func meetingInfoRow(for meeting: Meeting) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.footnote)
            Text(formatMeetingTime(meeting.start, end: meeting.end))
                .font(.footnote)
            Spacer(minLength: 8)
            if let label = meeting.responseStatus.displayLabel {
                respondedPill(label: label)
            }
        }
        .foregroundStyle(Brand.textMuted)
    }

    /// Non-interactive status pill shown inline on the meeting info
    /// row when the user has already responded. Outlined with
    /// `Brand.textMuted` so it reads as the softer status indicator
    /// — matches the RSVP buttons' outline treatment on this surface
    /// rather than the filled pill the calendar card uses on its
    /// darker background.
    private func respondedPill(label: String) -> some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(Brand.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay {
                Capsule().strokeBorder(Brand.textMuted, lineWidth: 1)
            }
    }

    private var rsvpRow: some View {
        HStack(spacing: 8) {
            RsvpButton(response: .accepted, label: "Accept", icon: "checkmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.accepted)
            }
            RsvpButton(response: .tentativelyAccepted, label: "Maybe", icon: "questionmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.tentativelyAccepted)
            }
            RsvpButton(response: .declined, label: nil, icon: "xmark",
                       outlineColor: Brand.textMuted) {
                onRsvp(.declined)
            }
        }
    }

    private var accessibilityLabel: String {
        let flagPrefix = email.isFlagged ? "Flagged email" : "Email"
        let invitePrefix = matchingMeeting != nil ? "Meeting invitation" : flagPrefix
        return "\(invitePrefix) from \(email.from): \(email.subject)"
    }
}
