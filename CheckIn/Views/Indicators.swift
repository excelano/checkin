// Indicators.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Visible state cue while `active.listening` is current. The mic icon is
/// surrounded by a pulsing ring keyed to a slow phase so the user can see
/// the system is hot. Reduce-motion swaps the pulse for a steady ring per
/// D22.
struct ListeningIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Brand.accent, lineWidth: 3)
                .frame(width: 96, height: 96)
                .scaleEffect(reduceMotion ? 1.0 : (pulse ? 1.15 : 1.0))
                .opacity(reduceMotion ? 0.9 : (pulse ? 0.3 : 0.9))
                .animation(reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                           value: pulse)
            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Brand.accent)
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Listening")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Visible state cue while `active.processing` is current. Three dots that
/// fade in sequence; reduce-motion replaces them with the static word
/// "Thinking" per D22.
struct ThinkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        Group {
            if reduceMotion {
                Text("Thinking")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Brand.textMuted)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Brand.accent)
                            .frame(width: 10, height: 10)
                            .opacity(phase == i ? 1.0 : 0.25)
                    }
                }
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                        phase = (phase + 1) % 3
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thinking")
    }
}

/// On-screen captioning of the spoken response per D22. Always visible
/// during `active.speaking` and stays for a beat after the speech ends so
/// a user who looked away briefly can still read it.
struct CaptioningView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Brand.bgDarker)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Brand.accentDim, lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
