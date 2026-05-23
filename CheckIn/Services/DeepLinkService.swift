// DeepLinkService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// URL builders for the only companion app CheckIn defers to: Teams,
/// for meeting joins and per-chat opens. `LSApplicationQueriesSchemes`
/// in `Info.plist` declares `msteams`, so `UIApplication.canOpenURL(_:)`
/// answers truthfully when the app is installed. Graph-returned URLs
/// (`chat.webUrl`, `onlineMeeting.joinUrl`) flow through `passthrough`
/// rather than being reconstructed.
///
/// Outlook is intentionally not a companion: iOS Outlook exposes no
/// per-message-id deep-link, so any "Open in Outlook" handoff lands on a
/// generic inbox or calendar view that the user could have reached from
/// their home screen. Mail is handled in-app via preview + Reply.
enum DeepLinkService {

    static var teams: URL? {
        URL(string: "msteams://")
    }

    static func passthrough(_ urlString: String) -> URL? {
        URL(string: urlString)
    }
}
