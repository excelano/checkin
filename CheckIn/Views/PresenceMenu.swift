// PresenceMenu.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import CheckInKit
import SwiftUI

/// Top-bar pill showing the user's current Microsoft 365 presence and exposing
/// the settable states plus Out of Office and Reset to auto.
///
/// OOO lives in the same menu as the presences (rather than in
/// Settings) because conceptually it's another "I'm not available"
/// state. It's a peer of Offline / Away — same menu position, same
/// selection semantics. Under the hood it's a different Graph endpoint
/// (`mailboxSettings/automaticRepliesSetting`), which the Inbox
/// reconciles: picking any presence (or Reset) also disables
/// OOO so the two never claim to be active at once.
struct PresenceMenu: View {
    let presence: Presence
    let isOutOfOffice: Bool
    let onSelect: (Presence) -> Void
    let onSelectOutOfOffice: () -> Void

    var body: some View {
        Menu {
            ForEach(Presence.settableStates, id: \.self) { state in
                menuButton(for: state)
            }
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
                StatusGlyph(presence: presence, isOutOfOffice: isOutOfOffice)
            }
            .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(isOutOfOffice
            ? "Out of office"
            : "Presence: \(presence.displayName)")
        .accessibilityHint("Change your presence")
    }

    private func menuButton(for state: Presence) -> some View {
        // Only the presence whose state matches the current value
        // gets the checkmark, and only when OOO isn't the active state.
        let isSelected = !isOutOfOffice && presence == state
        return Button { onSelect(state) } label: {
            Label {
                Text(state.displayName + (isSelected ? "  ✓" : ""))
            } icon: {
                PresenceGlyph(state)
            }
        }
    }

    private var outOfOfficeMenuButton: some View {
        Button(action: onSelectOutOfOffice) {
            Label {
                Text("Out of office" + (isOutOfOffice ? "  ✓" : ""))
            } icon: {
                OutOfOfficeGlyph()
            }
        }
    }

}
