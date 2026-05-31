// CheckInControls.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents
import CheckInKit
import SwiftUI
import WidgetKit

// iOS 18 Control Center controls. The Out-of-Office toggle reflects live
// state from the App Group snapshot; the presence buttons are fixed
// quick-sets covering every status the app exposes. Each runs its intent in
// this extension process, where the bundle registers `StatusActions` — the
// same path the interactive widget buttons use. Gated to iOS 18 because
// `ControlWidget` doesn't exist below it and the app's deployment floor is 17.6.

@available(iOS 18.0, *)
struct OutOfOfficeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: ControlKind.outOfOffice,
            provider: OutOfOfficeValueProvider()
        ) { isOn in
            ControlWidgetToggle(
                "Out of Office",
                isOn: isOn,
                action: SetOutOfOfficeIntent()
            ) { _ in
                Label("Out of Office", systemImage: "arrow.up.forward.circle.fill")
            }
            .tint(.purple)
        }
        .displayName("Out of Office")
        .description("Turn Outlook automatic replies on or off.")
    }
}

@available(iOS 18.0, *)
struct OutOfOfficeValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        CheckInSnapshot.loadFromAppGroup()?.isOutOfOffice ?? false
    }
}

/// Shared shape for a one-tap presence control: a button that sets a fixed
/// status. Every presence control below is the same configuration differing
/// only in kind, status, glyph, and copy, so they all route through here.
@available(iOS 18.0, *)
private func statusControl(
    kind: String,
    status: StatusAppEnum,
    label: LocalizedStringKey,
    systemImage: String,
    tint: Color,
    displayName: LocalizedStringResource,
    description: LocalizedStringResource
) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind) {
        ControlWidgetButton(action: SetPresenceIntent(status: status)) {
            Label(label, systemImage: systemImage)
        }
        .tint(tint)
    }
    .displayName(displayName)
    .description(description)
}

@available(iOS 18.0, *)
struct SetAvailableControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setAvailable, status: .available,
            label: "Available", systemImage: "checkmark.circle.fill", tint: .green,
            displayName: "Set Available",
            description: "Set your Microsoft 365 status to Available."
        )
    }
}

@available(iOS 18.0, *)
struct SetBusyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setBusy, status: .busy,
            label: "Busy", systemImage: "minus.circle.fill", tint: .red,
            displayName: "Set Busy",
            description: "Set your Microsoft 365 status to Busy."
        )
    }
}

@available(iOS 18.0, *)
struct SetDoNotDisturbControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setDoNotDisturb, status: .doNotDisturb,
            label: "Do Not Disturb", systemImage: "minus.circle.fill", tint: .red,
            displayName: "Set Do Not Disturb",
            description: "Set your Microsoft 365 status to Do Not Disturb."
        )
    }
}

@available(iOS 18.0, *)
struct SetBeRightBackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setBeRightBack, status: .beRightBack,
            label: "Be Right Back", systemImage: "clock.fill", tint: .yellow,
            displayName: "Set Be Right Back",
            description: "Set your Microsoft 365 status to Be Right Back."
        )
    }
}

@available(iOS 18.0, *)
struct SetAwayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setAway, status: .away,
            label: "Away", systemImage: "clock.fill", tint: .yellow,
            displayName: "Set Away",
            description: "Set your Microsoft 365 status to Away."
        )
    }
}

@available(iOS 18.0, *)
struct SetOfflineControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.setOffline, status: .offline,
            label: "Offline", systemImage: "xmark.circle.fill", tint: .gray,
            displayName: "Set Offline",
            description: "Set your Microsoft 365 status to Offline."
        )
    }
}

@available(iOS 18.0, *)
struct ResetStatusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        statusControl(
            kind: ControlKind.resetStatus, status: .resetToAuto,
            label: "Reset to auto", systemImage: "arrow.counterclockwise", tint: .cyan,
            displayName: "Reset to auto",
            description: "Clear your status and let Microsoft 365 detect it automatically."
        )
    }
}
