// TeamsHandoff.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import UIKit

/// Open a chat in Teams via its Graph-supplied `webUrl`, falling back to a
/// generic Teams launch when the URL is missing or the open fails. Shared
/// by the summary row's context menu and the chat preview sheet's
/// "Earlier messages are in Teams" handoff so the deep-link-and-fallback
/// logic lives in one place.
///
/// Caveat: `webUrl` is an https universal link, so it lands in the Teams
/// app only when Teams is installed and claims it; otherwise iOS opens it
/// in Safari (Teams web) silently. Either way it reaches the correct chat.
@MainActor
func openChatInTeams(webUrl: String?) {
    if let urlString = webUrl, let url = DeepLinkService.passthrough(urlString) {
        UIApplication.shared.open(url) { opened in
            if !opened, let teams = DeepLinkService.teams {
                UIApplication.shared.open(teams)
            }
        }
        return
    }
    if let teams = DeepLinkService.teams {
        UIApplication.shared.open(teams)
    }
}
