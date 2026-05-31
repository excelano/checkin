// CheckInKitTests.swift
// CheckInKitTests
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Testing
@testable import CheckInKit

/// Records the values forwarded through a `StatusActions` box.
@MainActor
final class StatusRecorder {
    var appliedPresence: Presence?
    var appliedOutOfOffice: Bool?
}

@MainActor
struct StatusActionsTests {
    /// `StatusActions` forwards each call to the handler the app wired in.
    /// (The intents' `@Dependency` resolution can't be unit-tested —
    /// `@Dependency` is injected only when the system runs an intent, not
    /// when `perform()` is called directly — so that path is verified
    /// on-device via Siri / the widget instead.)
    @Test func statusActionsForwardToHandlers() async throws {
        let recorder = StatusRecorder()
        let actions = StatusActions(
            presence: { recorder.appliedPresence = $0 },
            outOfOffice: { recorder.appliedOutOfOffice = $0 }
        )

        try await actions.applyPresence(.busy)
        try await actions.applyOutOfOffice(true)

        #expect(recorder.appliedPresence == .busy)
        #expect(recorder.appliedOutOfOffice == true)
    }
}

struct CheckInSnapshotTests {
    private static let sample = CheckInSnapshot(
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        nextMeetingSubject: "Status sync",
        nextMeetingStart: Date(timeIntervalSince1970: 1_700_001_000),
        nextMeetingEnd: Date(timeIntervalSince1970: 1_700_002_800),
        nextMeetingOrganizer: "David",
        nextMeetingJoinUrl: "https://teams.microsoft.com/l/meetup-join/preview",
        unreadEmailCount: 7,
        chatCount: 3,
        presence: .busy,
        isOutOfOffice: true
    )

    /// Encode + decode preserves every field, including the `Presence` enum
    /// (which only round-trips because we conformed it to `Codable` when
    /// adding it to the snapshot).
    @Test func snapshotRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.sample)
        let decoded = try JSONDecoder().decode(CheckInSnapshot.self, from: data)

        #expect(decoded.updatedAt == Self.sample.updatedAt)
        #expect(decoded.nextMeetingSubject == Self.sample.nextMeetingSubject)
        #expect(decoded.nextMeetingStart == Self.sample.nextMeetingStart)
        #expect(decoded.nextMeetingEnd == Self.sample.nextMeetingEnd)
        #expect(decoded.nextMeetingOrganizer == Self.sample.nextMeetingOrganizer)
        #expect(decoded.nextMeetingJoinUrl == Self.sample.nextMeetingJoinUrl)
        #expect(decoded.unreadEmailCount == Self.sample.unreadEmailCount)
        #expect(decoded.chatCount == Self.sample.chatCount)
        #expect(decoded.presence == Self.sample.presence)
        #expect(decoded.isOutOfOffice == Self.sample.isOutOfOffice)
    }

    /// `settingStatus` patches only presence + OOO, leaving the rest of the
    /// snapshot intact. This is the path the intent-driven mutation takes
    /// when the caller has no fresh summary to rebuild the snapshot from.
    @Test func settingStatusPatchesOnlyPresenceAndOOO() {
        let patched = Self.sample.settingStatus(
            presence: .doNotDisturb,
            isOutOfOffice: false
        )

        #expect(patched.presence == .doNotDisturb)
        #expect(patched.isOutOfOffice == false)
        #expect(patched.updatedAt == Self.sample.updatedAt)
        #expect(patched.nextMeetingSubject == Self.sample.nextMeetingSubject)
        #expect(patched.nextMeetingStart == Self.sample.nextMeetingStart)
        #expect(patched.nextMeetingOrganizer == Self.sample.nextMeetingOrganizer)
        #expect(patched.nextMeetingJoinUrl == Self.sample.nextMeetingJoinUrl)
        #expect(patched.unreadEmailCount == Self.sample.unreadEmailCount)
        #expect(patched.chatCount == Self.sample.chatCount)
    }
}
