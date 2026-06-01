// OutOfOfficeGlyph.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// The Out-of-Office indicator — a black arrow on a purple circle, in
/// the same palette style as `PresenceGlyph`. Shared so the in-app
/// presence menu and the widget's status row display OOO identically.
public struct OutOfOfficeGlyph: View {
    public init() {}

    public var body: some View {
        Image(systemName: Self.symbolName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, Self.tint)
    }
}
