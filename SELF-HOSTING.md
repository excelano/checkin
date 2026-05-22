# CheckIn: Self-Hosting Guide

CheckIn is built so you can run it independently of Excelano if you choose. Clone the source, change the redirect URI scheme and bundle ID to your own, sign with your own Apple Developer team, and install the build you produced yourself. This puts every piece of infrastructure in your own hands: your own bundle ID, your own redirect URI scheme, your own Apple Developer team, your own Azure App Registration. The trade-off is that you maintain it yourself, including future updates.

You will need a Mac with Xcode 15 or later, an Apple Developer account (the free tier suffices for personal device installs lasting up to seven days; a paid tier is required for TestFlight and longer-lived signing), an Azure tenant where you can create an App Registration, and comfort with Xcode signing and command-line git.

## Step 1: Clone and choose your identifiers

1. Fork [excelano/checkin](https://github.com/excelano/checkin) on GitHub, or just clone it directly.
2. Decide on your **bundle ID** (for example, `com.example.checkin`). It must be unique to your Apple Developer team.
3. Decide on your **redirect URI scheme**. The MSAL convention is `msauth.<bundle-id>`, so a bundle ID of `com.example.checkin` gives a redirect URI scheme of `msauth.com.example.checkin` and a full redirect URI of `msauth.com.example.checkin://auth`.

## Step 2: Update the source

1. Open `CheckIn/Info.plist`. Replace the `CFBundleURLSchemes` entry from `msauth.com.excelano.checkin` to your scheme.
2. Open `CheckIn/Utilities/Constants.swift`. Set `clientID` to your Azure client ID (you create this in step 4). Update `redirectURI` from `msauth.com.excelano.checkin://auth` to `msauth.<your-bundle-id>://auth`. Update `authority` if you are running single-tenant.
3. A grep for `com.excelano.checkin` across the repo finds every reference, including `PRODUCT_BUNDLE_IDENTIFIER` entries inside `CheckIn.xcodeproj/project.pbxproj`. Update each to match your chosen value (a sed pass works for the `.pbxproj`: `sed -i '' 's/com\.excelano\.checkin/your.bundle.id/g' CheckIn.xcodeproj/project.pbxproj`).

## Step 3: Configure the Xcode project

1. Open the project: `open CheckIn.xcodeproj`.
2. In **Signing & Capabilities**, set **Team** to your Apple Developer team.
3. Verify the deployment target is iOS 17 (the committed project sets it on the target; the project-level default may differ).
4. MSAL is wired in as a Swift Package Manager dependency at `https://github.com/AzureAD/microsoft-authentication-library-for-objc`. Xcode resolves it on first open.

## Step 4: Create the Azure App Registration

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Navigate to **Microsoft Entra ID** > **App registrations** > **New registration**.
3. Name the registration whatever you like (for example, "CheckIn personal").
4. Under **Supported account types**, choose multi-tenant if you plan to sign in with multiple M365 accounts; otherwise single-tenant.
5. Under **Redirect URI**, choose **Public client/native (mobile & desktop)** and enter your custom redirect URI (`msauth.<your-bundle-id>://auth`).
6. Click **Register**.
7. In the registration's sidebar, open **API permissions** > **Add a permission** > **Microsoft Graph** > **Delegated permissions**. Add `User.Read`, `Mail.ReadWrite`, and `Calendars.Read`. If you want Teams chat support, also add `Chat.ReadWrite`.
8. Click **Add permissions**. If your tenant requires admin consent for any permission (typically `Chat.ReadWrite`), grant it via **Grant admin consent for [tenant]**, or have an administrator do so. Without consent, MSAL returns AADSTS65001 on sign-in for the affected scopes.
9. Open **Authentication** in the registration's sidebar. Under **Advanced settings**, set **Allow public client flows** to **Yes**. Save.
10. The **Application (client) ID** is shown on the registration's **Overview** page. Copy it into `Constants.swift` from step 2.

## Step 5: Build and install

1. Connect your iPhone to your Mac and select it as the run destination in Xcode.
2. Build and run. Xcode signs the binary with your team's certificate and installs it on your device.
3. The first launch prompts for M365 sign-in. The sign-in flow uses your Azure App Registration.

For longer-lived installs, distribute via TestFlight (paid Developer account required). Publishing your fork to the App Store under your own developer account is permitted by the MIT license but is your responsibility, including reviewing the App Privacy declaration against your build's actual behavior.

## Verifying your build

After install, confirm the app behaves as expected. Sign in with an M365 account from your tenant; the OAuth dialog should display your Azure App Registration's name, not Excelano's. Pull the summary; calendar, mail, and (if enabled) Teams should populate.

## Common errors

**AADSTS50011: redirect URI mismatch.** Your `Info.plist` URL scheme, `Constants.redirectURI`, and the Azure App Registration redirect URI must agree exactly, including the `://auth` suffix.

**AADSTS65001: admin consent required.** A scope your registration requests needs admin consent. Either drop the scope (for example, disable Teams in your build) or have a tenant admin grant consent.

**AADSTS500113: no reply address registered.** The Azure App Registration has no redirect URI configured. Add one under **Authentication**.

**`MSALErrorBrokerKeyValidation` on sign-in.** MSAL cannot reach the keychain group expected by Microsoft Authenticator. This typically means the app is not signed with a paid Apple Developer team (free signing has limitations around shared keychain groups). Switch to a paid team or disable broker auth in your `MSALPublicClientApplicationConfig`.

## What changes in upstream affect you

If Excelano changes the redirect URI scheme, the bundle ID, or the URL scheme structure, your fork is unaffected: you have your own. If Excelano changes the Microsoft Graph API surface in use, or adds new scopes, those are code changes you can pick up via `git pull` and rebuild. The upstream commit history is the canonical record.

## License

CheckIn is MIT-licensed. You may fork, modify, redistribute, and publish your own version under the terms of the MIT license. You are responsible for any tradenames, trademarks, or branding under your control; the CheckIn name and any associated marks are not granted by the license and should be replaced in any publicly distributed fork.
