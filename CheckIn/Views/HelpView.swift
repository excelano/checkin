// HelpView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Help sheet placeholder. Content lives elsewhere for now; the sheet
/// exists so the toolbar's "?" button has somewhere to land.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Text("Help")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Coming back later.")
                    .font(.body)
                    .foregroundStyle(Brand.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
