# CheckIn

A voice-first iOS app for hands-free Microsoft 365 status. Your next meeting, unread emails, pending Teams chats. Eyes-off. Local. Private.

CheckIn augments Outlook and Teams; it does not replace them. Tap any item to deep-link into the canonical app for the full content.

## What it does

You ask, CheckIn answers. The voice surface starts narrow on purpose: at-a-glance summary, sender or topic filter, refresh, repeat, stop, help, open by name. Anything richer (replying, marking read, joining meetings by voice) ships in later releases. The full scope is captured in `PLAN.md`.

The interaction model is multi-modal. Voice handles the hands-off path; touch and screen handle everything voice is bad at (browsing, comparison, precise editing). Either is enough on its own.

## How it works

CheckIn talks directly to your Microsoft 365 tenant via the Microsoft Graph API. There is no backend. There is no analytics. There is no logging that leaves the device, including to the developer.

Speech recognition runs on-device using `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. The microphone audio and the resulting transcripts never leave the phone. M365 data is fetched on demand, surfaced to the screen and to text-to-speech, and is not persisted to disk.

`PRIVACY.md` is the canonical statement. `SELF-HOSTING.md` walks through the fork-and-rebuild path with your own Azure App Registration if you want full custody.

## Status

Early. The design audit is complete (see `DESIGN.md`, 33 numbered decisions). The architecture build (`StateMachine`, `DialogContext`, intent classifier, response template registry, deep-link service, audio session, earcons) is the next piece of work. See `PLAN.md` for the Day 1 build sequence.

The keeper code in this repo (MSAL auth wrapper, Microsoft Graph data layer, models, brand, utilities) carries over from an earlier iteration of the project that lives at the archived [excelano/checkin-voice](https://github.com/excelano/checkin-voice) repo. The voice prototype that preceded the iOS app lives at the archived [excelano/checkin-web-prototype](https://github.com/excelano/checkin-web-prototype) repo.

## Repo layout

```
DESIGN.md          33 design decisions; the source of truth
PERSONA.md         voice persona reference for TTS strings
STATES.md          application state machine
PLAN.md            scope and sequencing
CAPABILITIES.md    Apple voice/audio API capability scan
PHASE3-NOTES.md    patterns extracted from the archived web prototype
PRIVACY.md         privacy statement
SELF-HOSTING.md    self-hosting walkthrough

CheckIn.xcodeproj/ Xcode project (committed; bundle ID, deployment target, MSAL package reference all wired)
CheckIn/
    CheckInApp.swift
    Info.plist
    Assets.xcassets/
    Models/        plain Codable structs for Graph responses
    Services/      MSAL auth, Graph client
    Utilities/     brand, time formatting, constants, HTML stripping
    Views/         ContentView placeholder (Phase 4 fleshes this out)
```

## Getting set up (macOS)

```bash
git clone https://github.com/excelano/checkin.git
cd checkin
open CheckIn.xcodeproj
```

Xcode resolves the MSAL Swift Package on first open (takes a moment). For simulator builds no signing is needed; for device builds, set your Apple Developer team in **Signing & Capabilities**. Build with `Cmd+B`, run with `Cmd+R`. The placeholder `ContentView` shows a sign-in button; signing in completes the MSAL OAuth flow against my Excelano Azure App Registration and lands on a "Signed in" placeholder.

Minimum deployment is iOS 17. Xcode 16 or later is required (the project uses synchronized root groups).

If you want to use your own Azure App Registration instead of mine, see `SELF-HOSTING.md`.

## License

MIT. See `LICENSE`.
