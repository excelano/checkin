// NotificationCenterDelegate.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import UIKit
import UserNotifications

/// Routes meeting-notification taps to the Teams join URL when there
/// is one. Calendar-only meetings (no join URL) just bring CheckIn to
/// the foreground — there's no per-meeting deep-link to hand off to.
/// Also lets alerts surface as banners while the app is foregrounded.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let joinUrl = response.notification.request.content.userInfo["joinUrl"] as? String
        Task { @MainActor in
            await openMeeting(joinUrlString: joinUrl)
            completionHandler()
        }
    }

    @MainActor
    private func openMeeting(joinUrlString: String?) async {
        guard let urlString = joinUrlString,
              let url = DeepLinkService.passthrough(urlString),
              UIApplication.shared.canOpenURL(url) else { return }
        _ = await UIApplication.shared.open(url)
    }
}
