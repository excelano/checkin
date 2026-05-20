# CheckIn: Plan

Updated 2026-05-20.

## Status

Phases 1-4 and sub-phases 5.0 through 5.3e are committed (current `main` at `e36bcaa`). The voice loop, intent routing, disambiguation, Graph fetch, deep-link routing, and dialog-stack cleanup all work on device. Remaining work to TestFlight is consolidated into six phases below.

The earlier per-slice plan (5.3f through 5.5) is superseded by this document.

## Goal

Ship a complete-feeling, voice-first M365 status panel. Read-and-navigate scope: anything that modifies M365 data routes the user to Outlook or Teams.

Mutations (mark-as-read, flag, soft-delete, bulk operations) defer to v2. Splitting on the read/write line, not D29's single/bulk line, because mutation features share the confirmation infrastructure (D28) and ship more coherently together once v1 is in real use.

## Phases

Each phase is one commit (or a small set of related commits) with on-device verification before moving on. No mid-phase scope expansion — anything that surfaces goes to `~/notes/BACKLOG.md` and is addressed after the current phase.

### Phase A — Audio architecture

Replace the ad-hoc audio session lifecycle with a deliberate design.

- New `AudioSessionController` owns category transitions and serializes them with TTS state.
- `AVSpeechSynthesizer` becomes a per-utterance instance (synth recreation pattern). A category swap can't wedge an in-flight synth.
- Earcons routed through the controller so silent-respect applies to them (closes the F15 carry-forward).
- D8 and D33 in `DESIGN.md` updated to reflect silent-respect-throughout policy. `STATES.md` audio session section updated.

Closes the F2 interrupt cliff, the F15 earcons-silent gap, and the drift between spec and code.

### Phase B — Entity matcher rework

`NLTaggerEntityMatcher.matchAgainstKnown` reworked to longest-canonical-substring matching against the lowercased utterance. The current single-token check over-fires on "Microsoft" by surfacing every Microsoft-prefix candidate. Plus ordinal+sender composition for `.open` so "open the latest email from Tony" picks the right message.

Closes F10 (over-fire) and F11 (compositional `.open`).

### Phase C — New read/navigate intents

Three additions to round out the read-and-navigate surface.

- **Reply by voice.** New intent, anchors, template. Deep-links to Outlook in reply mode; composition happens in Outlook.
- **Join meeting.** Add `joinUrl: String?` to the `Meeting` model. Extend Graph `$select` to fetch `onlineMeeting.joinUrl`. Route through `DeepLinkService.passthrough` when present, otherwise fall through to Outlook calendar. F6 falls out.
- **Time queries.** "When's my next meeting", "how long until my next meeting", relative phrasing per D29. New intent class + templates.

Also lands the F12 immediate-render disambig panel binding (already in the working tree) and F7 chat anchor coverage.

### Phase D — Conversation mode

- Auto-finalization wire: `SFSpeechRecognizer`'s natural `isFinal` drives `.listening → .processing → .speaking` so hands-free turn-taking works without a mic tap. (Was 5.4a.)
- Voice-disambig auto-listen: gate entry to `.disambiguating` on `preferredRestState == .listening` so `handleDisambiguationUtterance` goes live in conversation mode. (Was 5.4c.)
- Listening Mode toggle becomes functional.
- Voice barge-in dropped from v1 per the silent-switch policy decision. Touch barge-in (tap-mic-during-TTS) stays. D8 in `DESIGN.md` updated.

### Phase E — Accessibility and persona

- VoiceOver labels on every interactive element.
- Dynamic Type tested at the largest accessibility size.
- Reduced motion variants for `ListeningIndicator` and `ThinkingIndicator`.
- Persona drift sweep across `ResponseTemplateRegistry` against `PERSONA.md`.

### Phase F — Pre-TestFlight gate

- `Info.plist` permission strings reviewed.
- Privacy posture verification: no `URLSession` outside Microsoft Graph and Microsoft identity endpoints; no analytics SDKs anywhere in the dependency graph.
- App Store Connect "Data Not Collected" prep.
- Final smoke test on device.

## Out of scope for v1

- Mutations: mark-as-read, flag, soft-delete, bulk operations. Bundled in v2.
- Voice barge-in (auto-cut on detected user speech mid-TTS). Bundled in a future release after v1 production exposure.
- Custom Language Model (D10). The off-state path with `contextualStrings` plus the matcher rework is sufficient for v1; opt-in LM lands when there's a real recognition-precision gap to close.

## v2

Write-and-mutate features per D29:

- Mark single email as read (`PATCH /me/messages/{id}`) with persona ack.
- Flag single email (`PATCH /me/messages/{id}/flag`).
- Soft-delete single email with D28 confirmation.
- Bulk operations (`mark-all`, `flag-all`, `delete-all`) with count confirmation and the "except the latest" modifier.

Backlog at `~/notes/BACKLOG.md` accumulates v2 work and any deferred polish as it surfaces.

## Configuration

- Client ID for `excelano.onmicrosoft.com` tenant in `Constants.swift` (default; user can override per D25).
- Bundle ID: `com.excelano.checkin`.
- Redirect URI: `msauth.com.excelano.checkin://auth`.
- Brand colors: navy `#0D2D5B`, cyan `#00ADEE`.

## Reference

- `DESIGN.md` — 33 numbered decisions, the source of truth.
- `STATES.md` — state machine.
- `PERSONA.md` — voice persona.
- `PRIVACY.md` — privacy posture.
- `SELF-HOSTING.md` — D25 and D26 self-hosting walkthrough.
- `GUIDE.md` — architecture and Swift bridge for a Swift-newcomer reader.
- `SWIFT-MODERN.md` — Swift idioms post-2016.
- `CAPABILITIES.md` — Apple API capability scan.
- `~/notes/BACKLOG.md` — captured items deferred from current execution.
