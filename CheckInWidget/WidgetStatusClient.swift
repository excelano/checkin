// WidgetStatusClient.swift
// CheckInWidget
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import MSAL
import WidgetKit
import CheckInKit

/// Performs status changes from inside the widget extension. On iOS 18+ an
/// interactive-widget intent runs in the extension, not the app, so the
/// extension must talk to Graph itself. It acquires a token silently from
/// the shared MSAL keychain cache and issues the same presence / Out-of-Office
/// calls the app's `GraphClient` makes, then patches the App Group snapshot so
/// the widget reflects the change. Tokens never leave the device.
///
/// Endpoint shapes deliberately mirror `GraphClient`'s presence / auto-reply
/// methods; if those change, mirror the change here. (A shared request layer
/// is the eventual DRY home, deferred to avoid destabilizing the shipped
/// app-side client.)
final class WidgetStatusClient: Sendable {
    static let shared = WidgetStatusClient()

    private let graphBaseURL = "https://graph.microsoft.com/v1.0"
    private let defaultClientID = "0ce3820d-db53-4b2e-9621-6c4ccc086d5a"
    private let defaultAuthority = "https://login.microsoftonline.com/organizations"
    private let scopes = [
        "User.Read", "Mail.ReadWrite", "Mail.Send",
        "Calendars.ReadWrite", "MailboxSettings.ReadWrite",
        "Chat.ReadWrite", "Presence.ReadWrite",
    ]
    private let defaultOutOfOfficeMessage =
        "I'm currently out of the office and will respond when I return."

    // MARK: - Public actions

    /// Set the user's preferred presence (or clear to auto for `.unknown`),
    /// keeping CheckIn's presence session alive so Graph honors the override.
    /// Mirrors `Inbox.setPresence`, including turning Out of Office off when a
    /// presence is explicitly chosen.
    ///
    /// The snapshot is written once, after the Graph call succeeds. WidgetKit
    /// re-renders only after `perform()` returns and ignores a mid-call
    /// reload, so an upfront optimistic patch never paints early, and the
    /// toggle's instant flip is WidgetKit-driven and needs no snapshot help.
    /// On failure the prior snapshot is left untouched and a reload lets the
    /// toggle settle back to it.
    func applyPresence(_ presence: Presence) async throws {
        let wasOutOfOffice = currentSnapshot()?.isOutOfOffice == true
        do {
            let token = try await acquireToken()

            // Best-effort session heartbeat (Available); failure here
            // shouldn't block the preferred-presence set.
            try? await postSessionPresence(token: token, sessionId: effectiveConfig().clientID)

            if presence == .unknown {
                try await emptyPost(token: token, path: "/me/presence/clearUserPreferredPresence")
            } else {
                try await postPreferredPresence(token: token, presence: presence)
            }

            // Choosing a presence also clears Out of Office, matching the picker.
            if wasOutOfOffice {
                try? await setAutomaticReplies(token: token, on: false)
            }
            patchSnapshot(presence: presence, isOutOfOffice: false)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }

    /// Turn Outlook automatic replies on or off. Mirrors
    /// `GraphClient.enableAutomaticReplies` / `disableAutomaticReplies`.
    /// Snapshot written once on success, left untouched on failure.
    func applyOutOfOffice(_ on: Bool) async throws {
        do {
            let token = try await acquireToken()
            try await setAutomaticReplies(token: token, on: on)
            let presence = currentSnapshot()?.presence ?? .unknown
            patchSnapshot(presence: presence, isOutOfOffice: on)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
    }

    // MARK: - Token

    private func effectiveConfig() -> (clientID: String, authority: String) {
        let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier)
        let clientID = defaults?.string(forKey: CheckInSnapshot.effectiveClientIDKey) ?? defaultClientID
        let authority = defaults?.string(forKey: CheckInSnapshot.effectiveAuthorityKey) ?? defaultAuthority
        return (clientID, authority)
    }

    private func acquireToken() async throws -> String {
        let config = effectiveConfig()
        guard let authorityURL = URL(string: config.authority) else {
            throw WidgetStatusError.notConfigured
        }
        let authority = try MSALAADAuthority(url: authorityURL)
        // redirectUri nil → MSAL derives the extension's own default,
        // msauth.com.excelano.checkin.CheckInWidget://auth. MSAL locks that
        // msauth.<bundle_id> format to the running bundle, so the extension
        // can't reuse the app's URI; its own must be registered in Entra or
        // silent token refresh fails (AADSTS50011). Pin the shared cache group.
        let msalConfig = MSALPublicClientApplicationConfig(
            clientId: config.clientID,
            redirectUri: nil,
            authority: authority
        )
        msalConfig.cacheConfig.keychainSharingGroup = "com.microsoft.adalcache"
        let app = try MSALPublicClientApplication(configuration: msalConfig)
        guard let account = try app.allAccounts().first else {
            throw WidgetStatusError.notAuthenticated
        }
        let params = MSALSilentTokenParameters(scopes: scopes, account: account)
        return try await app.acquireTokenSilent(with: params).accessToken
    }

    // MARK: - Graph calls

    private func postSessionPresence(token: String, sessionId: String) async throws {
        let body = SessionPresenceBody(
            sessionId: sessionId,
            availability: "Available",
            activity: "Available",
            expirationDuration: "PT1H"
        )
        try await send(token: token, method: "POST", path: "/me/presence/setPresence", body: body)
    }

    private func postPreferredPresence(token: String, presence: Presence) async throws {
        guard let availability = presence.graphAvailability,
              let activity = presence.graphActivity else { return }
        let body = PreferredPresenceBody(
            availability: availability,
            activity: activity,
            expirationDuration: "P1D"
        )
        try await send(token: token, method: "POST", path: "/me/presence/setUserPreferredPresence", body: body)
    }

    private func setAutomaticReplies(token: String, on: Bool) async throws {
        if on {
            let current: AutomaticRepliesResponse = try await get(
                token: token, path: "/me/mailboxSettings/automaticRepliesSetting"
            )
            let internalMsg = current.internalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultOutOfOfficeMessage
            let externalMsg = current.externalReplyMessage.flatMap { $0.isEmpty ? nil : $0 } ?? defaultOutOfOfficeMessage
            let body = MailboxSettingsFull(
                automaticRepliesSetting: AutomaticRepliesFull(
                    status: "alwaysEnabled",
                    externalAudience: current.externalAudience ?? "all",
                    internalReplyMessage: internalMsg,
                    externalReplyMessage: externalMsg
                )
            )
            try await send(token: token, method: "PATCH", path: "/me/mailboxSettings", body: body)
        } else {
            let body = MailboxSettingsStatusOnly(
                automaticRepliesSetting: AutomaticRepliesStatusOnly(status: "disabled")
            )
            try await send(token: token, method: "PATCH", path: "/me/mailboxSettings", body: body)
        }
    }

    // MARK: - HTTP

    private func send(token: String, method: String, path: String, body: some Encodable) async throws {
        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data, method: method, path: path)
    }

    private func emptyPost(token: String, path: String) async throws {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data, method: "POST", path: path)
    }

    private func get<T: Decodable>(token: String, path: String) async throws -> T {
        var request = URLRequest(url: try url(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data, method: "GET", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: graphBaseURL + path) else {
            throw WidgetStatusError.notConfigured
        }
        return url
    }

    private func check(_ response: URLResponse, data: Data, method: String, path: String) throws {
        guard let http = response as? HTTPURLResponse else { throw WidgetStatusError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw WidgetStatusError.graph(status: http.statusCode, path: path)
        }
    }

    // MARK: - Snapshot

    private func currentSnapshot() -> CheckInSnapshot? {
        guard let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier),
              let data = defaults.data(forKey: CheckInSnapshot.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CheckInSnapshot.self, from: data)
    }

    private func patchSnapshot(presence: Presence, isOutOfOffice: Bool) {
        guard let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier),
              let existing = currentSnapshot(),
              let data = try? JSONEncoder().encode(
                  existing.settingStatus(presence: presence, isOutOfOffice: isOutOfOffice)
              ) else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        defaults.set(data, forKey: CheckInSnapshot.userDefaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum WidgetStatusError: Error {
    case notConfigured
    case notAuthenticated
    case invalidResponse
    case graph(status: Int, path: String)
}

// MARK: - Graph request/response bodies (mirror GraphClient)

private struct SessionPresenceBody: Encodable {
    let sessionId: String
    let availability: String
    let activity: String
    let expirationDuration: String
}

private struct PreferredPresenceBody: Encodable {
    let availability: String
    let activity: String
    let expirationDuration: String
}

private struct AutomaticRepliesResponse: Decodable {
    let status: String?
    let externalAudience: String?
    let internalReplyMessage: String?
    let externalReplyMessage: String?
}

private struct MailboxSettingsFull: Encodable {
    let automaticRepliesSetting: AutomaticRepliesFull
}

private struct AutomaticRepliesFull: Encodable {
    let status: String
    let externalAudience: String
    let internalReplyMessage: String
    let externalReplyMessage: String
}

private struct MailboxSettingsStatusOnly: Encodable {
    let automaticRepliesSetting: AutomaticRepliesStatusOnly
}

private struct AutomaticRepliesStatusOnly: Encodable {
    let status: String
}
