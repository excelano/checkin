// WatchGlanceView.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// The single-screen CheckIn glance for Apple Watch. Reads from the
/// session receiver's pushed snapshot — no Graph calls here, no
/// credentials, no fetch logic. Tapping the presence pill opens a
/// picker sheet matching the iPhone's PresenceMenu (Available, Busy,
/// Do not disturb, Be right back, Away, Offline, Out of office, Reset
/// to auto). The selected action is sent to the phone, which runs the
/// actual Graph call and pushes a fresh snapshot back.
struct WatchGlanceView: View {
    let receiver: WatchSessionReceiver
    @State private var showingPicker: Bool = false
    @State private var pendingAction: Bool = false
    @State private var showUnreachableToast: Bool = false
    @State private var refreshing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    meetingLine
                    laterTodaySection
                }
                .padding(.horizontal, 4)
            }
            pinnedCountsRow
        }
        .overlay(alignment: .top) {
            if showUnreachableToast {
                Text("Phone unreachable")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: .capsule)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showUnreachableToast)
        .task {
            await autoRefreshIfStale()
        }
        .sheet(isPresented: $showingPicker) {
            PresencePickerSheet(
                currentPresence: receiver.snapshot?.presence ?? .unknown,
                isOutOfOffice: receiver.snapshot?.isOutOfOffice ?? false,
                onSelectPresence: { selection in
                    showingPicker = false
                    pendingAction = true
                    receiver.sendPresence(selection)
                    schedulePendingReset()
                },
                onSelectOutOfOffice: {
                    showingPicker = false
                    pendingAction = true
                    receiver.sendOutOfOffice(true)
                    schedulePendingReset()
                }
            )
        }
    }

    /// The presence indicator: just the glyph, tappable, rendered as a
    /// plain button so it carries no chrome. Lives at the trailing edge
    /// of whatever the top row of the glance is showing. While a
    /// presence change is in flight, swaps to a small progress spinner.
    @ViewBuilder
    private var presenceIcon: some View {
        Button {
            guard receiver.snapshot != nil else { return }
            showingPicker = true
        } label: {
            glyphContent
                .font(.caption.weight(.semibold))
                .opacity(pendingAction ? 0 : 1)
                .overlay {
                    if pendingAction {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(receiver.snapshot == nil)
    }

    /// The static glyph for the current presence/OOO state. Pulled out
    /// of `presenceIcon` so the spinner can overlay it without changing
    /// the button's layout footprint — the glyph defines the size; the
    /// spinner just paints on top.
    @ViewBuilder
    private var glyphContent: some View {
        if let snapshot = receiver.snapshot, snapshot.isOutOfOffice {
            OutOfOfficeGlyph()
        } else if let snapshot = receiver.snapshot {
            PresenceGlyph(snapshot.presence)
        } else {
            PresenceGlyph(.unknown)
        }
    }

    @ViewBuilder
    private var meetingLine: some View {
        if let snapshot = receiver.snapshot {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if let meeting = snapshot.currentOrNextMeeting(referenceDate: context.date) {
                    meetingBlock(meeting: meeting, referenceDate: context.date)
                } else {
                    noMeetingRow
                }
            }
        } else {
            HStack(spacing: 4) {
                Text("Waiting for phone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                presenceIcon
            }
        }
    }

    private func meetingBlock(meeting: SnapshotMeeting, referenceDate: Date) -> some View {
        let inProgress = meeting.start <= referenceDate
        let imminent = isMeetingImminent(meeting.start, referenceDate: referenceDate)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .foregroundStyle(inProgress ? .orange : Brand.accent)
                Text(meetingTimeRange(start: meeting.start, end: meeting.end))
                    .foregroundStyle(Brand.textMuted)
                Spacer()
                presenceIcon
            }
            .font(.caption2.weight(.semibold))
            Text(meeting.subject)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text(untilTime(meeting.start, referenceDate: referenceDate))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(imminent || inProgress ? .orange : Brand.accent)
                .lineLimit(1)
        }
    }

    private var noMeetingRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .foregroundStyle(Brand.accent)
            Text("No meetings")
                .foregroundStyle(.secondary)
            Spacer()
            presenceIcon
        }
        .font(.caption2.weight(.semibold))
    }

    /// Counts row pinned below the ScrollView so it stays visible as the
    /// user scrolls the meeting list. Sits outside the scroll surface
    /// and trades a small slice of scroll height for always-on context.
    /// The refresh button on the leading edge asks the phone for fresh
    /// data — the icon swaps to a spinner while the round-trip is in
    /// flight, and a brief "Phone unreachable" toast surfaces when the
    /// phone can't be reached or the snapshot doesn't arrive in time.
    @ViewBuilder
    private var pinnedCountsRow: some View {
        HStack(spacing: 10) {
            refreshButton
            Spacer()
            if let snapshot = receiver.snapshot {
                countChip(symbol: "envelope.fill", value: snapshot.unreadEmailCount)
                countChip(symbol: "bubble.left.fill", value: snapshot.chatCount)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            Task { await handleRefresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
                .opacity(refreshing ? 0 : 1)
                .overlay {
                    if refreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(refreshing)
    }

    private func countChip(symbol: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(Brand.accent)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var laterTodaySection: some View {
        if let snapshot = receiver.snapshot {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let later = snapshot.remainingLaterMeetings(referenceDate: context.date)
                if !later.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Divider()
                        Text("LATER TODAY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Brand.textMuted)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(later, id: \.self) { meeting in
                                laterRow(meeting: meeting, referenceDate: context.date)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func laterRow(meeting: SnapshotMeeting, referenceDate: Date) -> some View {
        let live = meeting.start <= referenceDate
            || isMeetingImminent(meeting.start, referenceDate: referenceDate)
        return HStack(spacing: 6) {
            Text(meetingTimeRange(start: meeting.start, end: meeting.end, includePeriod: false))
                .foregroundStyle(live ? .orange : Brand.accent)
                .monospacedDigit()
                .layoutPriority(1)
            Text(meeting.subject)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption2.weight(.semibold))
    }

    /// The phone re-pushes a fresh snapshot after the Graph call
    /// completes; clear the pending flag when the snapshot actually
    /// reflects the change, capped at a few seconds so a stuck request
    /// doesn't lock the pill forever.
    private func schedulePendingReset() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            pendingAction = false
        }
    }

    /// Auto-pull when the glance becomes visible. Only fires if the
    /// cached snapshot is older than the staleness window (or absent),
    /// so quick re-opens within ~a minute don't re-hit Graph. Guards
    /// against firing while a manual refresh is already in flight.
    @MainActor
    private func autoRefreshIfStale() async {
        guard !refreshing else { return }
        let staleness: TimeInterval = 60
        let shouldRefresh: Bool
        if let updatedAt = receiver.snapshot?.updatedAt {
            shouldRefresh = Date().timeIntervalSince(updatedAt) > staleness
        } else {
            shouldRefresh = true
        }
        if shouldRefresh {
            await handleRefresh()
        }
    }

    /// Drives the refresh button. Flips the icon to a spinner while the
    /// round-trip is in flight; surfaces a brief "Phone unreachable"
    /// hint when the watch can't talk to the phone or the fresh
    /// snapshot never arrives.
    @MainActor
    private func handleRefresh() async {
        refreshing = true
        defer { refreshing = false }
        let result = await receiver.sendRefreshRequest()
        switch result {
        case .refreshed:
            break
        case .phoneUnreachable, .timedOut:
            showUnreachableToast = true
            try? await Task.sleep(for: .seconds(2))
            showUnreachableToast = false
        }
    }
}

/// Watch-native presence picker. Same option order as the iPhone's
/// PresenceMenu (Available → Offline, then Out of office, then Reset
/// to auto), but rendered as a List so it feels at home on watchOS.
private struct PresencePickerSheet: View {
    let currentPresence: Presence
    let isOutOfOffice: Bool
    let onSelectPresence: (Presence) -> Void
    let onSelectOutOfOffice: () -> Void

    private let states: [Presence] = [
        .available, .busy, .doNotDisturb, .beRightBack, .away, .offline
    ]

    var body: some View {
        List {
            Section {
                ForEach(states, id: \.self) { state in
                    presenceRow(state)
                }
                outOfOfficeRow
            }
            Section {
                Button {
                    onSelectPresence(.unknown)
                } label: {
                    Label("Reset to auto", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Status")
    }

    private func presenceRow(_ state: Presence) -> some View {
        let isSelected = !isOutOfOffice && currentPresence == state
        return Button {
            onSelectPresence(state)
        } label: {
            HStack(spacing: 8) {
                PresenceGlyph(state)
                Text(state.displayName)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
    }

    private var outOfOfficeRow: some View {
        Button(action: onSelectOutOfOffice) {
            HStack(spacing: 8) {
                OutOfOfficeGlyph()
                Text("Out of office")
                Spacer()
                if isOutOfOffice {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.accent)
                }
            }
        }
    }
}
