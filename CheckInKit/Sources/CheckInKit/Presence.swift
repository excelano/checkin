// Presence.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The user's Microsoft 365 presence as we model it. Mirrors the subset of
/// Graph's availability values we let the user set explicitly via
/// `setUserPreferredPresence`, plus `.unknown` for the pre-fetch /
/// post-reset / fetch-failure case.
///
/// `String`-backed so it encodes cleanly into `CheckInSnapshot` for the
/// widget and Control Center controls to read.
public enum Presence: String, Codable, Hashable {
    case available
    case busy
    case doNotDisturb
    case beRightBack
    case away
    case offline
    case unknown

    public var displayName: String {
        switch self {
        case .available: return "Available"
        case .busy: return "Busy"
        case .doNotDisturb: return "Do not disturb"
        case .beRightBack: return "Be right back"
        case .away: return "Away"
        case .offline: return "Offline"
        case .unknown: return "—"
        }
    }

    /// Map a Graph availability string to one of our enum cases. Graph
    /// includes idle variants ("AvailableIdle", "BusyIdle") and several
    /// activity-based states that we collapse into our simpler model.
    public init(graphAvailability: String) {
        switch graphAvailability {
        case "Available", "AvailableIdle": self = .available
        case "Busy", "BusyIdle": self = .busy
        case "DoNotDisturb": self = .doNotDisturb
        case "BeRightBack": self = .beRightBack
        case "Away": self = .away
        case "Offline": self = .offline
        default: self = .unknown
        }
    }

    /// Availability string for Graph's `setUserPreferredPresence` body.
    /// Nil for `.unknown`, which is "no preference" rather than a real
    /// state to set.
    public var graphAvailability: String? {
        switch self {
        case .available: return "Available"
        case .busy: return "Busy"
        case .doNotDisturb: return "DoNotDisturb"
        case .beRightBack: return "BeRightBack"
        case .away: return "Away"
        case .offline: return "Offline"
        case .unknown: return nil
        }
    }

    /// Activity string paired with the availability for Graph's setter.
    /// Graph requires Offline + OffWork as the only legal pairing for
    /// the offline case; everything else mirrors availability.
    public var graphActivity: String? {
        switch self {
        case .offline: return "OffWork"
        default: return graphAvailability
        }
    }

    /// The filled SF Symbol that depicts this presence as a "colored circle
    /// with a glyph" (see `PresenceGlyph`). The single source of truth for
    /// presence iconography: `PresenceGlyph` renders it directly, the Control
    /// Center buttons reuse it, and the watch corner complication derives its
    /// punched-out form by dropping the `.circle.fill` suffix.
    public var glyphSymbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .busy, .doNotDisturb: return "minus.circle.fill"
        case .beRightBack, .away: return "clock.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    /// The presences a user can explicitly choose, in display order. Shared by
    /// the iPhone presence menu, the watch picker, and the Shortcuts enums so
    /// the option list can't drift between surfaces. Excludes `.unknown`,
    /// which is "reset to automatic" rather than a state to pick directly.
    public static let settableStates: [Presence] = [
        .available, .busy, .doNotDisturb, .beRightBack, .away, .offline
    ]
}
