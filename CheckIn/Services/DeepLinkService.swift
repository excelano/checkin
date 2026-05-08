// DeepLinkService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// URL builders for the only two apps CheckIn defers to per D27: Outlook
/// for mail and calendar, Teams for chat and meetings.
///
/// Two patterns are at play. The first is constructed `ms-outlook://` and
/// `msteams://` URLs for actions the apps document (open inbox, open
/// Teams, compose a reply, start a chat). The second is passthrough of
/// URLs Microsoft Graph itself returns: a chat's `webUrl` and an event's
/// `onlineMeeting.joinUrl` are deep links Microsoft generates server-side
/// and we just open.
///
/// `LSApplicationQueriesSchemes` in `Info.plist` already declares
/// `ms-outlook` and `msteams`, so `UIApplication.canOpenURL(_:)` will
/// answer truthfully on a device with the apps installed.
enum DeepLinkService {

    // MARK: - Outlook

    /// Open Outlook. Lands on whatever screen the user was last on; in
    /// practice this is usually the inbox.
    static var outlook: URL? {
        URL(string: "ms-outlook://")
    }

    /// Open the Outlook inbox explicitly.
    static var outlookInbox: URL? {
        URL(string: "ms-outlook://emails")
    }

    /// Open a compose window in reply mode. Used by the Day 2 reply flow.
    /// Microsoft's documented compose parameters are `to`, `subject`, and
    /// `body`; supplying a `Re:` subject is the closest the documented
    /// scheme gets to "reply to message N", since iOS Outlook does not
    /// expose a documented per-message-id open.
    static func outlookReply(to recipient: String, subject: String, body: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "ms-outlook"
        components.host = "compose"
        var items = [
            URLQueryItem(name: "to", value: recipient),
            URLQueryItem(name: "subject", value: subject.hasPrefix("Re:") ? subject : "Re: \(subject)")
        ]
        if let body { items.append(URLQueryItem(name: "body", value: body)) }
        components.queryItems = items
        return components.url
    }

    /// Open the Outlook calendar.
    static var outlookCalendar: URL? {
        URL(string: "ms-outlook://events")
    }

    // MARK: - Teams

    /// Open Teams.
    static var teams: URL? {
        URL(string: "msteams://")
    }

    /// Open a one-to-one or group chat by participant emails.
    /// The documented format is `msteams:/l/chat/0/0?users=a@x,b@y`.
    static func teamsChat(withUsers users: [String], topic: String? = nil) -> URL? {
        guard !users.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "msteams"
        components.path = "/l/chat/0/0"
        var items = [URLQueryItem(name: "users", value: users.joined(separator: ","))]
        if let topic { items.append(URLQueryItem(name: "topicName", value: topic)) }
        components.queryItems = items
        return components.url
    }

    // MARK: - Graph passthrough

    /// Open a deep link that Graph itself produced. Chats expose a `webUrl`
    /// of the form `https://teams.microsoft.com/l/chat/...` which iOS
    /// routes to Teams when installed. Meetings expose
    /// `onlineMeeting.joinUrl` of the same form. Both are best opened
    /// verbatim rather than reconstructed.
    static func passthrough(_ urlString: String) -> URL? {
        URL(string: urlString)
    }
}
