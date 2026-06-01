// PresenceGlyph.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// SF-Symbol icon styled to match Teams' presence palette. Shared by the
/// in-app presence menu and the widget's quick-set buttons so both
/// surfaces show the same glyph for a given state. Uses
/// `.symbolRenderingMode(.palette)` for two-tone glyphs (checkmark on
/// green, minus on red, etc.); single-tone styling would otherwise
/// render everything as the container's tint color.
public struct PresenceGlyph: View {
    private let presence: Presence

    public init(_ presence: Presence) {
        self.presence = presence
    }

    public var body: some View {
        // Symbol and tint come from `Presence` (the single source of truth);
        // only the palette wiring lives here. Busy and DND deliberately share
        // the same minus-on-red glyph: Microsoft gives DND a glyph and leaves
        // Busy bare, which makes their icon set inconsistent, so CheckIn uses
        // a uniform "colored circle with a glyph" and lets the adjacent label
        // tell the two apart.
        switch presence {
        case .beRightBack, .away:
            // A clock is a single-layer symbol, so it renders monochrome in
            // the presence tint rather than as a glyph punched into a circle.
            Image(systemName: presence.glyphSymbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(presence.tint)
        default:
            Image(systemName: presence.glyphSymbolName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, presence.tint)
        }
    }
}
