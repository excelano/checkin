// PhoneConnectivity.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation
import WatchConnectivity
import os

/// Phone-side WatchConnectivity link to the CheckIn watch app. Pushes the
/// status snapshot to the watch whenever the phone refreshes or mutates
/// status, and receives presence / Out-of-Office action requests from
/// the watch glance, routing them through the same Inbox entry points
/// Siri uses (`applyPresence`, `applyOutOfOffice`).
///
/// No Microsoft credentials cross this link. Payloads are an encoded
/// `CheckInSnapshot` (phone → watch) and a small action dictionary
/// (watch → phone). The phone holds the only token and runs every
/// Graph call; the watch just relays user intent.
@MainActor
final class PhoneConnectivity: NSObject {
    private let setPresence: (Presence) async throws -> Void
    private let setOutOfOffice: (Bool) async throws -> Void
    private let refresh: () async -> Void
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "phone-connectivity")

    init(
        setPresence: @escaping (Presence) async throws -> Void,
        setOutOfOffice: @escaping (Bool) async throws -> Void,
        refresh: @escaping () async -> Void
    ) {
        self.setPresence = setPresence
        self.setOutOfOffice = setOutOfOffice
        self.refresh = refresh
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Push the given snapshot to the watch via
    /// `updateApplicationContext(_:)`. iOS coalesces back-to-back updates
    /// to the latest payload, so calling this on every refresh is fine —
    /// the watch always sees the most recent state, even if it was off
    /// the wrist when older updates were sent.
    func push(_ snapshot: CheckInSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            logger.error("push: failed to encode snapshot")
            return
        }
        do {
            try session.updateApplicationContext([WireKey.snapshot: data])
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Push whatever snapshot is currently sitting in the App Group.
    /// Used after `CheckInSnapshot.patchAndReload(...)` updates the App
    /// Group blob from an intent that ran without a full refresh, so
    /// the watch still gets the patched presence / OOO state even when
    /// there's no fresh `summary` to rebuild a snapshot from.
    func pushFromAppGroup() {
        guard let snapshot = CheckInSnapshot.loadFromAppGroup() else { return }
        push(snapshot)
    }

    fileprivate func handleAction(_ payload: [String: Any]) {
        guard let kindRaw = payload[WireKey.actionKind] as? String,
              let kind = ActionKind(rawValue: kindRaw) else {
            logger.error("handleAction: missing or unknown kind")
            return
        }
        switch kind {
        case .setPresence:
            guard let raw = payload[WireKey.presence] as? String,
                  let presence = Presence(rawValue: raw) else {
                logger.error("handleAction(setPresence): missing or unknown presence")
                return
            }
            Task { @MainActor in
                do {
                    try await self.setPresence(presence)
                } catch {
                    self.logger.error("setPresence from watch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .setOutOfOffice:
            guard let on = payload[WireKey.outOfOfficeOn] as? Bool else {
                logger.error("handleAction(setOutOfOffice): missing on flag")
                return
            }
            Task { @MainActor in
                do {
                    try await self.setOutOfOffice(on)
                } catch {
                    self.logger.error("setOutOfOffice from watch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .refresh:
            // The watch is asking for fresh data. Run the same refresh
            // path the foreground app uses; `Inbox.refresh()` ends by
            // calling `publishStatusSnapshot()`, which the watch sees
            // arrive as the updated `updatedAt` on its end.
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    enum WireKey {
        static let snapshot = "snapshot"
        static let actionKind = "kind"
        static let presence = "presence"
        static let outOfOfficeOn = "on"
    }

    enum ActionKind: String {
        case setPresence
        case setOutOfOffice
        case refresh
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in
                self.logger.error("activation error: \(message, privacy: .public)")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleAction(message)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handleAction(message)
        }
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleAction(userInfo)
        }
    }
}
