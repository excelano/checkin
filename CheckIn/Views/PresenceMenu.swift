// PresenceMenu.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Top-bar pill showing the user's current Teams presence and exposing
/// the settable states plus Out of Office and Reset to auto.
///
/// OOO lives in the same menu as the Teams presences (rather than in
/// Settings) because conceptually it's another "I'm not available"
/// state. It's a peer of Offline / Away — same menu position, same
/// selection semantics. Under the hood it's a different Graph endpoint
/// (`mailboxSettings/automaticRepliesSetting`), which the Inbox
/// reconciles: picking any Teams presence (or Reset) also disables
/// OOO so the two never claim to be active at once.
struct PresenceMenu: View {
    let presence: TeamsPresence
    let isOutOfOffice: Bool
    let onSelect: (TeamsPresence) -> Void
    let onSelectOutOfOffice: () -> Void

    var body: some View {
        Menu {
            menuButton(for: .available)
            menuButton(for: .busy)
            menuButton(for: .doNotDisturb)
            menuButton(for: .beRightBack)
            menuButton(for: .away)
            menuButton(for: .offline)
            outOfOfficeMenuButton
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
                if isOutOfOffice {
                    outOfOfficeGlyph
                } else {
                    presenceGlyph(presence)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(isOutOfOffice
            ? "Out of office"
            : "Teams presence: \(presence.displayName)")
        .accessibilityHint("Change your presence")
    }

    private var outOfOfficeGlyph: some View {
        Image(systemName: "arrow.up.forward.circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .purple)
    }

    private func menuButton(for state: TeamsPresence) -> some View {
        // Only the Teams presence whose state matches the current value
        // gets the checkmark, and only when OOO isn't the active state.
        let isSelected = !isOutOfOffice && presence == state
        return Button { onSelect(state) } label: {
            Label {
                Text(state.displayName + (isSelected ? "  ✓" : ""))
            } icon: {
                presenceGlyph(state)
            }
        }
    }

    private var outOfOfficeMenuButton: some View {
        Button(action: onSelectOutOfOffice) {
            Label {
                Text("Out of office" + (isOutOfOffice ? "  ✓" : ""))
            } icon: {
                outOfOfficeGlyph
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
