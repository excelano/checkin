# CheckIn: Privacy Statement

CheckIn is an iOS app that reads from and writes to your Microsoft 365 account on your behalf. This document is the canonical statement of what CheckIn does and does not do with your data. The companion repository is open source so that every claim here is independently verifiable.

## What stays on your device

When you ask for your summary, CheckIn fetches calendar events, unread emails, and Teams chats from the Microsoft Graph API using your account's own credentials. The fetched data is held in memory long enough to render the summary on screen. When you swipe to mark read or flag, CheckIn also holds the target message ID in memory long enough to issue the write. Nothing is persisted to disk, including caches. Closing or backgrounding the app discards the data.

## What leaves your device

**Microsoft Graph API calls.** When you ask for your summary, CheckIn issues HTTPS requests to your Microsoft 365 service. These calls go to `graph.microsoft.com` (and regional equivalents) and `login.microsoftonline.com`. They carry your access token, which Microsoft uses to identify you, and they return the calendar, mail, and chat data your account has access to. When you swipe to mark read or flag, CheckIn issues the corresponding write to the same destinations. This is the same traffic that any Microsoft Graph client makes; CheckIn does not add headers, identifiers, or analytics to it.

**Nothing else.** CheckIn makes no other network requests. No analytics, no crash reporting, no telemetry, no usage logging that leaves the device, no third-party SDKs that would. The Xcode project deliberately imports nothing of the sort, which is the point: this is enforced by the absence of code, not by a policy that depends on the developer behaving well.

## Writes

CheckIn can mark email as read and toggle the follow-up flag on email. Both happen by swipe gesture in the inbox list. The optimistic update is reverted if the Graph call fails.

The Microsoft 365 scopes CheckIn requests reflect what it does: `Mail.ReadWrite` for the email mutations, `Chat.ReadWrite` for Teams reads, and `Calendars.Read` because no calendar mutations are planned.

## What CheckIn does not collect

CheckIn does not collect Microsoft 365 content, query history, usage events, screen views, button taps, feature counts, crash reports, performance metrics, diagnostic logs, device identifiers, advertising identifiers, installation identifiers, or anything else. When CheckIn ships to the App Store, its App Privacy declaration will be "Data Not Collected." This document and the open-source repository are the substance behind that label.

## One thing outside the app's control

Apple aggregates anonymous crash logs at the iOS level from devices that have **Share With App Developers** turned on, and surfaces those aggregates to developers in App Store Connect. CheckIn neither collects this data nor processes it; the repository contains no code that touches it. But Apple may still surface aggregate, anonymized crash signatures to the developer account regardless of what the app itself does. If you do not want any of your device's anonymous crash data shared with any developer, including this one, the iOS-level control lives at **Settings > Privacy & Security > Analytics & Improvements > Share With App Developers**. Turning it off applies to all apps on your phone.

## How to verify the claims yourself

The full source is at [github.com/excelano/checkin](https://github.com/excelano/checkin). To check the claims here independently:

1. Search the project for `URLSession`. Every network call should target `graph.microsoft.com`, `login.microsoftonline.com`, or one of their regional equivalents.
2. Search for analytics and crash-reporter SDK names: Firebase, Sentry, Crashlytics, Mixpanel, Amplitude, Segment, GoogleAnalytics. None should appear.
3. Search for `print(` and `os_log(` and confirm there are no statements that emit user content.

If you would rather not depend on Excelano's published Azure App Registration at all, see `SELF-HOSTING.md`.

## Updates to this document

This document changes as the design changes. The change history is the git log of `PRIVACY.md`. Substantive changes to the privacy posture (a new data flow, a new dependency that touches data) require a corresponding update here in the same commit.
