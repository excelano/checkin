// HelpView.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

/// Where the help sheet should land based on what just happened. Drives
/// which collapsible section opens by default per D30 "lightly contextual."
enum HelpFocus {
    case neutral       // first-time, empty context
    case afterRefusal  // D18 was just emitted; emphasize what I do
    case afterRedirect // D19 was just emitted; emphasize the deep-link path
}

/// The help sheet per D30. Three collapsible sections. Visible content is
/// the full reference; the voice channel speaks the short variant on entry
/// and the long variant on "tell me more." Both surfaces are always
/// reachable: voice via "help" / "what can I say"; touch via the "?" button
/// on the main screen.
struct HelpView: View {
    let focus: HelpFocus
    @Environment(\.dismiss) private var dismiss

    @State private var doNowExpanded: Bool
    @State private var laterExpanded: Bool
    @State private var dontDoExpanded: Bool

    init(focus: HelpFocus = .neutral) {
        self.focus = focus
        // Per D30: "I can do this now" is open by default. Post-refusal
        // also opens "I don't do this" so the user sees both shapes of the
        // boundary at once. Post-redirect leaves the deep-link examples
        // visible under "I can do this now" without expanding "I don't."
        _doNowExpanded = State(initialValue: true)
        _laterExpanded = State(initialValue: false)
        _dontDoExpanded = State(initialValue: focus == .afterRefusal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerBlock

                    DisclosureGroup(isExpanded: $doNowExpanded) {
                        doNowContent
                    } label: {
                        sectionLabel("I can do this now")
                    }

                    DisclosureGroup(isExpanded: $laterExpanded) {
                        laterContent
                    } label: {
                        sectionLabel("Coming later")
                    }

                    DisclosureGroup(isExpanded: $dontDoExpanded) {
                        dontDoContent
                    } label: {
                        sectionLabel("I don't do this")
                    }

                    Spacer(minLength: 24)
                }
                .padding(20)
            }
            .background(Brand.bg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Brand.accent)
                        .accessibilityLabel("Close help")
                }
            }
            .navigationTitle("CheckIn Help")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I know your calendar, email, and chats.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Try \u{201C}what's on my plate\u{201D} or \u{201C}open Tony's email.\u{201D}")
                .font(.body)
                .foregroundStyle(Brand.textMuted)
        }
    }

    // MARK: - Section labels

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.white)
    }

    // MARK: - Content

    private var doNowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            example("Summary",        "what's on my plate", "what do I have today")
            example("Filter by name", "anything from Tony",  "any from Sarah")
            example("Counts",         "how many emails",     "any chats from Tony")
            example("Time",           "when's my next meeting", "how long until my meeting")
            example("Refresh",        "refresh",             "check again")
            example("Open",           "open Tony's email",   "open my next meeting", "open my chat with Sarah")
            example("Reply",          "reply to Tony",       "reply to Sarah's latest")
            example("Join meeting",   "join my next meeting")
            example("Repeat / Stop",  "say that again",      "stop", "exit")
            example("Help",           "what can I say",      "help")
            Text("Tap any item on the summary to open it in Outlook or Teams.")
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private var laterContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            laterRow("Mark read",      "mark Tony's email read")
            laterRow("Flag",           "flag Tony's email")
            laterRow("Soft-delete",    "delete Tony's email")
            laterRow("Bulk actions",   "mark all read except the latest")
        }
        .padding(.top, 8)
    }

    private var dontDoContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            dontDoRow("Read or summarize email bodies",
                      "Tap to open in Outlook.")
            dontDoRow("Compose a reply in this app",
                      "I open Outlook with the recipient set; finish there.")
            dontDoRow("Browse long lists by voice",
                      "The single screen plus deep-link covers it.")
            dontDoRow("Track tasks, weather, news, web searches",
                      "Outside my range.")
            dontDoRow("Send anything anywhere except your own M365",
                      "Privacy is foundational.")
        }
        .padding(.top, 8)
    }

    private func example(_ label: String, _ phrases: String...) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(phrases, id: \.self) { p in
                Text("\u{201C}\(p)\u{201D}")
                    .font(.callout)
                    .foregroundStyle(Brand.textMuted)
            }
        }
    }

    private func laterRow(_ label: String, _ phrases: String...) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(phrases.map { "\u{201C}\($0)\u{201D}" }.joined(separator: "  "))
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
        }
    }

    private func dontDoRow(_ label: String, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(Brand.textMuted)
        }
    }
}
