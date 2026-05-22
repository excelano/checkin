// TeamsPresence.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// The user's Teams presence as we model it. Mirrors the subset of
/// Graph's availability values we let the user set explicitly via
/// `setUserPreferredPresence`, plus `.unknown` for the pre-fetch /
/// post-reset / fetch-failure case.
enum TeamsPresence: Hashable {
    case available
    case busy
    case doNotDisturb
    case beRightBack
    case away
    case offline
    case unknown

    var displayName: String {
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
    init(graphAvailability: String) {
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
    var graphAvailability: String? {
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
    var graphActivity: String? {
        switch self {
        case .offline: return "OffWork"
        default: return graphAvailability
        }
    }
}
