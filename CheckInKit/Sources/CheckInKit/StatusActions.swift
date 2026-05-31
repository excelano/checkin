// StatusActions.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Surfaces a silent failure to the intent layer so a Siri/Shortcut/widget
/// invocation doesn't speak a success dialog after Graph rejected the
/// write. The underlying error is already logged at the call site; the
/// intent only needs to know the change didn't take effect.
public enum StatusActionError: LocalizedError {
    case applyFailed

    public var errorDescription: String? {
        switch self {
        case .applyFailed:
            return "Couldn't update your Microsoft 365 status. Try again."
        }
    }
}

/// The concrete dependency the status intents resolve through
/// `AppDependencyManager`. "Status" here spans both the Microsoft 365
/// presence and Outlook Out-of-Office auto-replies — the two things a
/// CheckIn quick action changes.
///
/// AppIntents keys `@Dependency` by the value's concrete type, not by a
/// protocol existential, so the intents depend on this box rather than a
/// protocol (a protocol-typed `@Dependency` never resolves and traps at
/// access). The box lives in CheckInKit so `SetPresenceIntent` /
/// `SetOutOfOfficeIntent` can reference it without importing the app's
/// `Inbox`. The app builds one from its `Inbox` and registers it in
/// `CheckInApp.init`; the widget extension registers its own (wired to a
/// lean presence client) for intents fired in-widget on iOS 18+, where
/// `perform()` runs in the extension rather than the app.
///
/// A nonisolated `Sendable` box (so registration and resolution cross
/// concurrency domains freely) whose handlers run on the main actor,
/// where `Inbox` lives.
public final class StatusActions: Sendable {
    private let presenceHandler: @Sendable @MainActor (Presence) async throws -> Void
    private let outOfOfficeHandler: @Sendable @MainActor (Bool) async throws -> Void

    public init(
        presence: @escaping @Sendable @MainActor (Presence) async throws -> Void,
        outOfOffice: @escaping @Sendable @MainActor (Bool) async throws -> Void
    ) {
        self.presenceHandler = presence
        self.outOfOfficeHandler = outOfOffice
    }

    /// Set the preferred Microsoft 365 presence, or reset to automatic
    /// for `.unknown`. Throws if no signed-in account is available.
    public func applyPresence(_ presence: Presence) async throws {
        try await presenceHandler(presence)
    }

    /// Turn Outlook automatic replies on or off. Throws if not signed in.
    public func applyOutOfOffice(_ on: Bool) async throws {
        try await outOfOfficeHandler(on)
    }
}
