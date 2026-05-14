// Brand.swift
// CheckIn
// Excelano brand colors — Tatsiana palette (2021 origin, navy + cyan).
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

enum Brand {
    static let bg        = Color(hex: 0x0D2D5B)
    static let bgDarker  = Color(hex: 0x06142A)
    static let accent    = Color(hex: 0x00ADEE)
    static let accentDim = Color(hex: 0x0072A4)
    static let textMuted = Color(hex: 0x6a8899)
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
