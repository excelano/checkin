// CustomMessageSheet.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Edit the Teams custom status message — short text that shows under
/// the user's name in Teams alongside their presence glyph. Independent
/// of presence; you can have any combination of the two.
struct CustomMessageSheet: View {
    let initialMessage: String
    let onSave: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($fieldFocused)
                        .listRowBackground(Brand.bgDarker)
                    Button("Clear", role: .destructive) {
                        onClear()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Brand.bgDarker)
                    .disabled(initialMessage.isEmpty)
                } footer: {
                    Text("Shown under your name in Teams.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Brand.bg)
            .navigationTitle("Custom message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .foregroundStyle(Brand.accent)
                    .disabled(draft == initialMessage)
                }
            }
            .onAppear {
                draft = initialMessage
                fieldFocused = true
            }
        }
        .preferredColorScheme(.dark)
    }
}
