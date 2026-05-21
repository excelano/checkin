// DialogContext.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Per-session dialog state held alongside the state machine. Memory only;
/// nothing persists to disk.
struct DialogContext {
    /// The latest summary fetched from Microsoft Graph.
    var summary: CheckInSummary?

    /// When `summary` was last fetched. The TTL gate in `SessionCoordinator`
    /// compares this against `AppStorageKey.summaryRefreshInterval` to decide
    /// whether a read should trigger a refresh first.
    var summaryFetchedAt: Date?
}
