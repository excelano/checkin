// ConflictResolutionSheet.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ConflictResolutionSheet: View {
    var inbox: Inbox
    let primaryMeetingId: String

    @Environment(\.dismiss) private var dismiss
    /// IDs captured when the sheet opens. Rows render in this order from
    /// live Inbox state; ids whose meeting no longer exists (deleted)
    /// or has been declined are silently skipped — both actions are
    /// terminal in the resolver context, so the row drops out instead
    /// of sitting there with a "Declined" pill the user can't act on.
    @State private var trackedIds: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("These meetings overlap. Adjust your response on one or both.")
                        .font(.footnote)
                        .foregroundStyle(Brand.textMuted)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    ForEach(trackedIds, id: \.self) { id in
                        if let meeting = lookupMeeting(id: id),
                           meeting.responseStatus != .declined {
                            ConflictMeetingRow(
                                meeting: meeting,
                                onRsvp: { response in
                                    if response == .declined {
                                        trackedIds.removeAll { $0 == meeting.id }
                                    }
                                    Task { await inbox.respondToMeeting(response, meetingId: meeting.id) }
                                },
                                onDelete: {
                                    trackedIds.removeAll { $0 == meeting.id }
                                    Task { await inbox.deleteMeeting(meetingId: meeting.id) }
                                }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.bg)
            .navigationTitle("Overlapping meetings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
            .onAppear { initializeTrackedIds() }
        }
        .preferredColorScheme(.dark)
    }

    /// Snapshot the primary + every meeting overlapping it at open time.
    /// Subsequent renders pull live state by id, so RSVP changes flow
    /// through and deletions just drop the corresponding row.
    /// Candidates are drawn from today's summary, the Phase-2 invite
    /// cache, and the reference pool of plain calendar events so an
    /// invite for a beyond-today meeting can show its overlapping
    /// plain calendar entry.
    private func initializeTrackedIds() {
        guard trackedIds.isEmpty else { return }
        var ids = [primaryMeetingId]
        if let primary = lookupMeeting(id: primaryMeetingId) {
            var candidates: [Meeting] = []
            if let m = inbox.summary?.meeting { candidates.append(m) }
            candidates.append(contentsOf: inbox.summary?.laterToday ?? [])
            candidates.append(contentsOf: inbox.inviteMeetings.values)
            candidates.append(contentsOf: inbox.conflictReferenceMeetings)
            // De-dup by id — an invite and the calendar event it
            // refers to share the same Graph event id and would
            // otherwise produce two rows for the same meeting.
            var seen: Set<String> = [primary.id]
            for candidate in candidates {
                guard !seen.contains(candidate.id) else { continue }
                guard candidate.start < primary.end, primary.start < candidate.end else { continue }
                ids.append(candidate.id)
                seen.insert(candidate.id)
            }
        }
        trackedIds = ids
    }

    private func lookupMeeting(id: String) -> Meeting? {
        if let m = inbox.summary?.meeting, m.id == id { return m }
        if let m = inbox.summary?.laterToday.first(where: { $0.id == id }) { return m }
        if let m = inbox.inviteMeetings.values.first(where: { $0.id == id }) { return m }
        return inbox.conflictReferenceMeetings.first(where: { $0.id == id })
    }
}

struct ConflictMeetingRow: View {
    let meeting: Meeting
    let onRsvp: (MeetingResponse) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meeting.subject)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("\(formatTimeOfDay(meeting.start)) \u{2013} \(formatTimeOfDay(meeting.end))")
                .font(.subheadline)
                .foregroundStyle(Brand.accent)
            if meeting.responseStatus.canRsvp, !meeting.organizer.isEmpty {
                Text("with \(meeting.organizer)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textMuted)
                    .lineLimit(1)
            }
            if let label = meeting.responseStatus.displayLabel {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Brand.bg)
                    .clipShape(Capsule())
            }
            if meeting.responseStatus.canRsvp {
                HStack(spacing: 8) {
                    RsvpButton(response: .accepted,
                               label: "Accept",
                               icon: "checkmark",
                               isCurrentResponse: meeting.responseStatus == .accepted) {
                        onRsvp(.accepted)
                    }
                    RsvpButton(response: .tentativelyAccepted,
                               label: "Maybe",
                               icon: "questionmark",
                               isCurrentResponse: meeting.responseStatus == .tentativelyAccepted) {
                        onRsvp(.tentativelyAccepted)
                    }
                    RsvpButton(response: .declined,
                               label: "Decline",
                               icon: "xmark",
                               isCurrentResponse: meeting.responseStatus == .declined) {
                        onRsvp(.declined)
                    }
                }
            } else {
                deleteButton
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.bgDarker)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            HStack(spacing: 4) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                Text("Delete").font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Brand.bg)
            .foregroundStyle(.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
