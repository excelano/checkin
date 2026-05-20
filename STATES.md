# CheckIn: Application States

The state machine is hierarchical. Top-level states are `signedOut`, `onboarding`, and `active`. The `active` state contains the operational substates the user spends nearly all their time in.

Each state below specifies visible UI, voice action, touch actions, and transitions out. Decision references in parentheses point back to `DESIGN.md`.

## `signedOut`

The user has no MSAL token.

**Visible UI.** A welcome card with a "Sign in" button.
**Voice action.** Inactive.
**Touch actions.** Sign in starts the MSAL browser flow.
**Transitions.** On successful sign-in, advances to `onboarding` if `hasCompletedOnboarding` is false, otherwise to `active.idle` (tap-to-talk) or `active.listening` (conversation mode).

## `onboarding`

The first-run flow per D31 is active. Substates: `welcome`, `permissions`, `mode`, `firstQuery`.

**Visible UI.** The onboarding sequence; the main screen is hidden behind it.
**Voice action.** Inactive in `welcome` and `permissions`. The system speaks one short persona greeting after `permissions` completes. The system speaks a varied invitation in `firstQuery`.
**Touch actions.** Sequential through the four steps with skip option per step.
**Transitions.** On `firstQuery` completion or skip, advances to `active.idle` or `active.listening` per the chosen mode.

## `active`

The signed-in, post-onboarding state. Contains the substates below.

### `active.idle`

Tap-to-talk rest state.

**Visible UI.** The summary plus a tappable mic button.
**Voice action.** Inactive.
**Touch actions.** Tap mic enters `active.listening`. Tap a summary row deep-links to Outlook or Teams per D27 (transient, returns to `active.idle`). Tap "?" enters `active.helpDisplayed`. Tap settings enters `active.settingsDisplayed`.
**Dialog context.** Empty or stale.

### `active.listening`

Mic is hot and VAD is active.

**Visible UI.** The summary plus a listening indicator (waveform or pulsing mic) per D2 and D13.
**Audio.** The listening earcon plays on entry per D13.
**Voice action.** Capture user speech until VAD detects end of utterance, or a cancel, timeout, or barge-in fires.
**Touch actions.** Tap mic cancels listening and returns to rest. Tap a summary row deep-links (cancels listening). Tap "?" or settings enters the displayed state (cancels listening).
**Transitions.** On end-of-utterance, advances to `active.processing`. On silence timeout, returns to rest. On cancel, returns to rest.

### `active.processing`

Transcript is finalized; the system is classifying intent, matching entities, and fetching from Graph.

**Visible UI.** The summary plus a thinking indicator.
**Audio.** The thinking earcon plays on entry per D21. Substates produce additional audio at latency thresholds.
**Substates.** `thinking` (under 1.5 seconds, silent except for the earcon); `speakingPlaceholder` (1.5 to 5 seconds, plays a short reassurance from the latency pool); `speakingEscalation` (over 5 seconds, plays a longer status update).
**Transitions.** On response ready, advances to `active.speaking` with the response. On error, advances to `active.speaking` with the matching error response. On out-of-scope or in-scope-unsupported classification, advances to `active.speaking` with the appropriate D18 or D19 response.

### `active.speaking`

TTS is playing the response.

**Visible UI.** The summary plus on-screen captioning of the spoken text per D22.
**Audio.** TTS via `AVSpeechSynthesizer` with delegate callbacks tracking position for D8 barge-in.
**Touch actions.** Tap mic triggers barge-in (TTS stops at word boundary, advances to `active.listening`). Tap stop ends TTS silently and returns to rest. Tap a summary row deep-links.
**Transitions.** On TTS completion in tap-to-talk, advances to `active.idle`. In conversation mode, advances to `active.listening`. Some response types (disambiguation prompts, confirmation prompts) advance to `active.disambiguating` or `active.confirming` after TTS completes.

### `active.disambiguating`

The system has presented an enumerated list of candidates per D7 and is waiting for selection.

**Visible UI.** The candidates numbered and named, a listening indicator, and the original utterance shown so the user knows what is being disambiguated.
**Voice action.** Listen for ordinal selection ("the first", "number two"), content selection ("Tony Smith"), date or subject reference, or cancel.
**Touch actions.** Tap a candidate selects it. Tap cancel exits to rest.
**Dialog context.** Carries the candidate list and the suspended intent.
**Transitions.** On selection, advances to `active.processing` with the chosen candidate substituted for the ambiguous reference. On cancel or timeout, returns to rest with the suspended intent discarded.

### `active.confirming`

The system is awaiting a yes or no for a destructive or modifying action per D28.

**Visible UI.** The action and its parameters spelled out, a listening indicator, and a confirmation earcon distinct from listening.
**Voice action.** Listen for yes, no, or related variants.
**Touch actions.** Tap "yes" or "no". Tap cancel exits to rest.
**Dialog context.** Carries the pending action.
**Transitions.** Yes advances to `active.processing` (executes the action). No returns to rest with the action discarded. Timeout (around eight seconds) returns to rest with no action taken.

### `active.helpDisplayed`

Help sheet is overlaid on the main screen per D30.

**Visible UI.** The help sheet with three collapsible sections, with the initially-open section shaped by recent context.
**Voice action.** Speak the short help variant on entry. Listen for "tell me more" to expand to the long variant. Listen for dismiss intents.
**Touch actions.** Dismiss returns to rest. Section taps expand or collapse content.
**Transitions.** On dismiss, returns to the prior rest state (idle in tap-to-talk, listening in conversation mode).

### `active.settingsDisplayed`

Settings sheet is overlaid on the main screen.

**Visible UI.** Sections for Voice (D5), Listening Mode (D17), Voice Recognition Tuning (D10), and Advanced (D25).
**Voice action.** Inactive (Settings is touch-only).
**Touch actions.** Standard settings interactions; sign-out is here.
**Transitions.** On dismiss, returns to the prior rest state.

## Universal behaviors

Help is reachable from any `active` substate via the help intent or the visible "?" button. The exit-phrase intent ("done", "thanks", "exit") in conversation mode transitions to `active.idle` regardless of substate. Sign-out from Settings transitions to `signedOut`. Backgrounding the app preserves state in memory while explicit close clears it (per D23).

## Audio session per state

Silent-respect is the policy: when the user has the hardware silent switch on, the app stays silent (like Mail or Calendar, not Music). Recording-capable categories bypass silent by iOS design, so the session toggles per phase.

- `.playAndRecord` with `.spokenAudio` mode in `listening`, `disambiguating`, and `confirming` (mic is hot for recognition or selection).
- `.soloAmbient` in `speaking` so TTS honors silent.
- `.processing` is a brief transition and inherits whichever category preceded it.
- Session is deactivated in `idle`, `helpDisplayed`, and `settingsDisplayed`.

The `AVSpeechSynthesizer` instance is recreated per utterance so a category transition can't wedge an in-flight synth (Apple's documented gotcha when the session changes mid-utterance). Earcons play through the same per-phase session so they too respect silent.

## Earcons

Earcons are tied to entry transitions. A listening earcon plays on `active.listening` entry, a thinking earcon plays on `active.processing` entry, and a confirmation earcon plays on `active.confirming` entry.
