# CLAUDE.md

Guidance for Claude (or any AI assistant) working in this repository. Human contributors are welcome to read it too; it doubles as a fast orientation document.

---

## What CheckIn is

A voice-first iOS app that gives a hands-free daily check-in for Microsoft 365: next meeting, unread emails, pending Teams chats. It does **not** display email bodies, does **not** implement reply, and does **not** duplicate Outlook or Teams. Tapping any item deep-links to the right Microsoft app. The app talks directly to Microsoft Graph; there is no backend.

## Where to start reading

The repo carries a deliberate set of design and reference documents. Read them in this order on your first pass:

1. `README.md` — short project description and build instructions.
2. `DESIGN.md` — the spec. 33 numbered decisions (D1, D2, …) that are the source of truth for behavior. When code or another doc cites `D27`, look it up here.
3. `STATES.md` — the hierarchical state machine that drives the entire app. Every voice or touch action transitions through it.
4. `GUIDE.md` — architecture and Swift bridge for a senior engineer new to Swift and iOS. The four layers, a complete voice-turn end-to-end, Swift idioms compared to Java/Go/Rust, and project conventions.
5. `SWIFT-MODERN.md` — companion to `GUIDE.md` covering Swift features added after Swift 3.
6. `PLAN.md` — phase sequence and per-phase scope.
7. `PERSONA.md` — every spoken phrase the app produces is reviewed against this. If you change response text, read it first.
8. `CAPABILITIES.md` — empirical scan of the Apple APIs in scope.
9. `PRIVACY.md` and `SELF-HOSTING.md` — the privacy posture and the two paths for running on your own Azure App Registration.
10. `PHASE3-NOTES.md` and `PHASE4-FOLLOWUPS.md` — implementation notes from completed phases. The followups doc is the Phase 5 punch list.

## Project guardrails

These cross-cut every change. Hold them lightly only when you have a clear D-decision overriding them.

- **No email bodies, no reply UI in-app.** Tapping deep-links to Outlook or Teams. (D-decisions in `DESIGN.md`.)
- **Voice-first with a touch equivalent.** Per D22, every voice capability has a touch path. Do not ship voice-only conveniences without the matching touch surface.
- **On-device speech recognition only.** No off-device recognition; no analytics; no off-device logging of any kind.
- **Every spoken phrase reviewed against `PERSONA.md`.** Anti-repeat, register, and persona-tuned phrasing are not optional.
- **D25 / D26 sovereignty.** Users can override the Azure App Registration at runtime (D25) or build their own end-to-end (D26). `SELF-HOSTING.md` is canonical.
- **Numbered decisions are the spec.** When changing behavior, update the decision; when adding a new pattern, add a new decision. The number is stable across edits to surrounding text.

## Project conventions

Every Swift source file begins with this header:

```swift
// FileName.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
```

The author owns the work; AI assistance is acknowledged in-file. Commits end with:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

The phase sequence in `PLAN.md` is authoritative. Tests live next to the code they test; integration concerns (auth, Graph, on-device speech) verify against real services rather than mocks where practical.

## Platform note

Building, running, and on-device testing require macOS with Xcode 15 or later and an Apple Developer account. The Swift sources are toolchain-portable, but the project (Info.plist, entitlements, signing, MSAL keychain access) is not exercisable without a Mac. CI for build verification on macOS is in scope for a future phase but not yet wired.

## What not to do

- Do not introduce a backend, analytics SDK, off-device logger, or any network destination other than Microsoft Graph and Microsoft identity endpoints.
- Do not add email-body rendering or reply UI to the app. The architecture deep-links instead, by design.
- Do not invent new spoken-phrase variants outside `ResponseTemplateRegistry`. Templates and registry edits are the only path.
- Do not bypass the state machine. Side-effecty work (audio session, recognizer start/stop, Graph fetches) is triggered by state transitions, not directly from views.
