// PresenceMenu.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Top-bar pill showing the user's current Teams presence and exposing
/// the five settable states + a Reset to clear the user-preferred
/// presence (Teams resumes auto-detection from calendar/idle/etc).
struct PresenceMenu: View {
    let presence: TeamsPresence
    let isOutOfOffice: Bool
    let customStatusMessage: String
    let onSelect: (TeamsPresence) -> Void
    let onOpenSettings: () -> Void
    let onEditCustomMessage: () -> Void

    var body: some View {
        if isOutOfOffice {
            Button(action: onOpenSettings) {
                ZStack {
                    Text("0").opacity(0)
                    outOfOfficeGlyph
                }
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Out of office")
            .accessibilityHint("Open settings to manage")
        } else {
            Menu {
                menuButton(for: .available)
                menuButton(for: .busy)
                menuButton(for: .doNotDisturb)
                menuButton(for: .beRightBack)
                menuButton(for: .away)
                menuButton(for: .offline)
                Divider()
                Button(action: onEditCustomMessage) {
                    Label {
                        Text(customStatusMessage.isEmpty ? "Custom message…" : customStatusMessage)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                }
                Divider()
                Button {
                    onSelect(.unknown)
                } label: {
                    Label("Reset to auto", systemImage: "arrow.counterclockwise")
                }
            } label: {
                ZStack {
                    // Invisible text reserves the count-pill's vertical
                    // footprint, so the chats section header doesn't grow
                    // taller than the email section header.
                    Text("0").opacity(0)
                    presenceGlyph(presence)
                }
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Teams presence: \(presence.displayName)")
            .accessibilityHint("Change your presence")
        }
    }

    private var outOfOfficeGlyph: some View {
        Image(systemName: "arrow.up.forward.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .purple)
    }

    private func menuButton(for state: TeamsPresence) -> some View {
        Button { onSelect(state) } label: {
            Label {
                Text(state.displayName + (presence == state ? "  ✓" : ""))
            } icon: {
                presenceGlyph(state)
            }
        }
    }

    /// SF-Symbol icon styled to match Teams' presence palette. Uses
    /// `.symbolRenderingMode(.palette)` to set two-tone glyphs (checkmark
    /// on green, minus on red, etc.) — single-tone Menu icon styling
    /// would otherwise render everything as the menu's tint color.
    @ViewBuilder
    private func presenceGlyph(_ state: TeamsPresence) -> some View {
        switch state {
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
        case .busy:
            // Both palette slots set to .red so the red value renders
            // through the same pipeline as DND's white-on-red palette,
            // keeping the two reds visually identical.
            Image(systemName: "circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .red)
        case .doNotDisturb:
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        case .beRightBack, .away:
            Image(systemName: "clock.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow)
        case .offline:
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .gray)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.gray)
        }
    }
}
