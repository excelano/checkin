// WatchSessionReceiver.swift
// CheckInWatch Watch App
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit
import os

/// Watch-side WatchConnectivity link. Receives the encoded status
/// snapshot from the phone and forwards it to the glance and the watch
/// widgets. Also sends user-originated presence / Out-of-Office actions
/// back to the phone, where Inbox runs the actual Graph call.
///
/// Holds no Microsoft credentials. The snapshot it stores in the watch
/// App Group is the same non-credential status payload the iOS widget
/// already reads from the phone's App Group.
@Observable
final class WatchSessionReceiver: NSObject {
    /// Most recently received snapshot. The glance reads this directly;
    /// the watch widgets read from the App Group (which this class
    /// keeps in sync with `snapshot`).
    private(set) var snapshot: CheckInSnapshot?
    /// True once the WCSession has activated. Until then we can't
    /// reliably check `isReachable` or queue user-info.
    private(set) var isActivated: Bool = false

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin.watch", category: "session-receiver")

    override init() {
        super.init()
        // Load any previously-pushed snapshot so the glance has something
        // to show on cold launch before a fresh push arrives.
        let initial = CheckInSnapshot.loadFromAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
        Task { @MainActor in self.snapshot = initial }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Send a presence change to the phone. Live message when reachable,
    /// `transferUserInfo` fallback otherwise (queued until the next
    /// reachable connection). The phone is the only side that talks to
    /// Graph; the canonical confirmation is the snapshot push that comes
    /// back after the mutation.
    func sendPresence(_ presence: Presence) {
        send([
            WireKey.actionKind: ActionKind.setPresence.rawValue,
            WireKey.presence: presence.rawValue
        ])
    }

    /// Send an Out-of-Office toggle to the phone. Same delivery
    /// semantics as `sendPresence`.
    func sendOutOfOffice(_ on: Bool) {
        send([
            WireKey.actionKind: ActionKind.setOutOfOffice.rawValue,
            WireKey.outOfOfficeOn: on
        ])
    }

    /// Outcome of a watch-initiated refresh request, used by the glance
    /// to decide whether to surface a "Phone unreachable" hint after
    /// the pull-to-refresh spinner finishes.
    enum RefreshResult {
        /// A fresh snapshot landed before the wait window expired.
        case refreshed
        /// The phone isn't reachable right now — there's no way to ask
        /// it to refresh until the link comes back.
        case phoneUnreachable
        /// The request was sent but no fresh snapshot arrived inside
        /// the wait window. Treated like unreachable from the user's
        /// perspective: the data on screen hasn't moved.
        case timedOut
    }

    /// Ask the phone for a fresh refresh. Returns when a new snapshot
    /// lands (detected by the `updatedAt` advancing), when the wait
    /// window expires, or immediately when the phone isn't reachable.
    /// Drives the glance's `.refreshable` modifier — its spinner stays
    /// up until this returns, so the user sees it stop exactly when
    /// fresh data arrives.
    @MainActor
    func sendRefreshRequest() async -> RefreshResult {
        guard WCSession.isSupported() else { return .phoneUnreachable }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return .phoneUnreachable
        }
        let before = snapshot?.updatedAt
        session.sendMessage(
            [WireKey.actionKind: ActionKind.refresh.rawValue],
            replyHandler: nil,
            errorHandler: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.logger.error("refresh sendMessage failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        )
        let start = Date()
        while Date().timeIntervalSince(start) < 10 {
            if let updatedAt = snapshot?.updatedAt, updatedAt != before {
                return .refreshed
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return .timedOut
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(payload)
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.logger.error("sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription, privacy: .public)")
                    session.transferUserInfo(payload)
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    @MainActor
    fileprivate func applyIncoming(_ context: [String: Any]) {
        guard let data = context[WireKey.snapshot] as? Data else {
            logger.error("applyIncoming: missing snapshot payload")
            return
        }
        guard let decoded = try? JSONDecoder().decode(CheckInSnapshot.self, from: data) else {
            logger.error("applyIncoming: failed to decode snapshot")
            return
        }
        snapshot = decoded
        decoded.saveToAppGroup(suite: CheckInSnapshot.watchAppGroupIdentifier)
        WidgetCenter.shared.reloadAllTimelines()
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

extension WatchSessionReceiver: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            let message = error.localizedDescription
            Task { @MainActor in
                self.logger.error("activation error: \(message, privacy: .public)")
                self.isActivated = (activationState == .activated)
            }
            return
        }
        let pending = session.receivedApplicationContext
        Task { @MainActor in
            self.isActivated = (activationState == .activated)
            // Adopt the receivedApplicationContext that was waiting at
            // activation, so a watch launched after the phone has
            // already pushed sees the latest state immediately.
            if !pending.isEmpty {
                self.applyIncoming(pending)
            }
        }
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyIncoming(applicationContext)
        }
    }
}
