// PresenceStyle.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

public extension Presence {
    /// The tint Teams uses for this presence — the colored half of the
    /// "black glyph on a colored circle" treatment. The single source for the
    /// presence palette, so `PresenceGlyph`, the Control Center buttons, and
    /// the watch's presence ring can't drift apart.
    var tint: Color {
        switch self {
        case .available: return .green
        case .busy, .doNotDisturb: return .red
        case .beRightBack, .away: return .yellow
        case .offline, .unknown: return .gray
        }
    }
}

public extension OutOfOfficeGlyph {
    /// Out-of-Office styling, kept beside the presence palette so the OOO
    /// glyph, the Control Center toggle, and the watch ring share one symbol
    /// and tint. OOO isn't a `Presence`, hence the separate home.
    static let symbolName = "arrow.up.forward.circle.fill"
    static let tint = Color.purple
}

/// The status glyph with Out-of-Office taking precedence over presence,
/// matching how every surface renders state: OOO dominates when on. Collapses
/// the repeated `if isOutOfOffice { OutOfOfficeGlyph() } else
/// { PresenceGlyph(presence) }` into one shared view.
public struct StatusGlyph: View {
    private let presence: Presence
    private let isOutOfOffice: Bool

    public init(presence: Presence, isOutOfOffice: Bool) {
        self.presence = presence
        self.isOutOfOffice = isOutOfOffice
    }

    public var body: some View {
        if isOutOfOffice {
            OutOfOfficeGlyph()
        } else {
            PresenceGlyph(presence)
        }
    }
}
