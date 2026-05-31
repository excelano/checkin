# CheckIn: Features

What a user can do, mapped to the entry point in the UI.

## App lifecycle & global

| Function | Triggered by |
|---|---|
| Sign in with Microsoft 365 | "Sign In with Microsoft" button on launch when signed out |
| Sign out | Settings sheet → Sign Out (with confirm dialog; the section is hidden when not signed in) |
| Refresh inbox (meeting, chats, emails) | Pull-to-refresh on the summary list. Also auto-refreshes when the app returns to the foreground (skipped if a refresh finished within the last 30 seconds). |
| Background refresh while the app is closed | iOS `BGAppRefreshTask` scheduled every time the app goes to the background, with a 15-min minimum interval. Actual cadence is at the OS's discretion (typically 15-60 min during active hours, less when quiet). Disabled by iOS if you force-quit from the app switcher until the next launch. |
| App-icon badge showing pending items | iOS app-icon badge updated to `unread emails + pending chats` after every refresh and after every local mark-read. Meetings are intentionally excluded — they're scheduled, not items to triage. Requests notification permission (`.badge` only) on first use; silently no-ops if denied. |
| See when a refresh failed | Orange warning banner ("Couldn't reach Microsoft — pull to retry") appears between the top bar and the content when any Graph call in the last refresh hit an error. Cleared automatically by the next successful refresh. Detailed errors still go to `os.Logger` for diagnostics. |

## Meetings

| Function | Triggered by |
|---|---|
| See next meeting in the next 24 hours | Top of the list when one exists; cancelled events and events you've declined are skipped. The card is a three-row layout: calendar icon + time range ("9-9:30 PM"), then subject, then countdown ("in 12 min" / "soon" / "now") with the organizer alongside. The list re-renders every 30 seconds so back-to-back meetings transition without a manual refresh. |
| See the rest of today's meetings | "Later today" section between the next-meeting card and the Chats section, showing each remaining meeting as a compact row (calendar + time range + subject). Same cancelled/declined skip. Tap a row to join in Teams. Window ends at start of tomorrow local time. |
| Join a meeting in Teams | Tap the meeting card (for the next meeting) or a "Later today" row (uses Graph's `onlineMeeting.joinUrl`; rewritten to `msteams:/` so iOS routes directly to the Teams app) |
| Highlight when the next meeting is imminent or in progress | When the meeting starts within the next 3 minutes, the calendar icon and countdown both flip from cyan to orange and the countdown reads "soon". Once the meeting starts, the countdown reads "now" in orange. The same treatment applies to "Later today" rows the moment one of them enters the imminent or in-progress window. |
| See a conflict warning when a meeting overlaps another | Orange triangle on the meeting card, on "Later today" rows, AND on the matching invite email's subject line. Computed across the same 10-event window we fetch; back-to-back meetings (one ending exactly when the next starts) don't count. |
| Resolve a meeting conflict | Tap the orange triangle on any of: the meeting card, a "Later today" row, an invite-email row, or an invite preview sheet. Opens a conflict-resolution sheet that lists the overlapping meetings and lets you Accept / Maybe / Decline each. |
| RSVP to a meeting (Accept / Maybe / Decline) | Three buttons under the meeting info on the calendar card OR under the meeting info on an invite-email row OR in the preview sheet for an invite email — all three surfaces feed the same Graph endpoint and stay in sync. Optimistic update, POSTs to Graph with `sendResponse=true`. |
| See your current RSVP state | "Accepted" / "Tentative" / "Declined" pill in place of the RSVP buttons on whichever surface you're looking at (calendar card, invite-email row, invite preview sheet). |
| See when an invitation is no longer actionable | "Removed" pill on the invite-email row and preview sheet when the invitation references an event that no longer exists in the calendar — declined, deleted from the calendar, or cancelled by the organizer. Graph data can't distinguish those causes, so the label describes the observable rather than guessing. No RSVP buttons in this state. |
| Auto-mark matching invite emails read after RSVP | After a successful RSVP from any surface, unread emails whose subject matches the meeting subject (or "Updated: ..." / "Cancelled: ...", or organizer + meetingMessageType contains-match) are marked read. |
| See meeting metadata on an invitation email | Calendar icon + "Today at 3:00 PM" / "Tomorrow at 9:30 AM" / "May 26 at 2:00 PM" line on the invite-email row and preview sheet, plus the orange conflict triangle on the subject line when applicable. |

## Notifications

| Function | Triggered by |
|---|---|
| Get a notification 1 minute before each meeting | Settings sheet → "Meeting reminders" toggle. Local `UNUserNotification` scheduled per meeting on every refresh. Tap the notification to open the meeting in Teams. |

## Emails

| Function | Triggered by |
|---|---|
| See up to 20 newest unread emails (Inbox folder only) | Email section, sorted by received-time desc. Sent items, drafts, and other folders excluded — scoped to `/me/mailFolders/inbox/messages`. |
| See the count of additional unread beyond the 20 shown | "+ N more unread" inline in the Email section header, next to the count badge, when total unread > 20 |
| Lift the 20-email cap to see everything unread | Email section header → ⋯ menu → "Show all N" (only when there are emails beyond the cap). Persists across launches. Toggle back via "Show top 20". |
| See each email's sender, subject, and preview | Each row shows sender + relative time, subject, and Graph's `bodyPreview` (up to 4 lines) |
| See a flag indicator on flagged emails | Orange flag icon next to the sender name |
| Preview an email | Tap an email row. Opens a sheet with the full message body (plain text via `Prefer: outlook.body-content-type="text"`). Email auto-marks-as-read on open. Body is cleaned via the same stripper used for summary previews (salutations, signatures, quoted replies, etc.). |
| Mark an email read | Swipe right-to-left on the row, OR auto on preview-sheet open, OR long-press → "Mark read" (optimistic, reverts on failure) |
| Mark an email back to unread | Preview sheet → "Mark unread" button (re-inserts the row in received-time order; also rolls back the server's read state) |
| Reply to an email | Preview sheet → "Reply" (swaps in a composer with a TextEditor), OR long-press an email row → "Reply" (opens the preview sheet straight into the composer). Replies default to Reply-all; Graph degrades to reply-to-sender for single-recipient messages. Lands in the user's Outlook Sent Items folder. |
| Flag / unflag an email | Swipe left-to-right on the row, or long-press → "Flag" / "Unflag" (optimistic, reverts on failure) |
| Bulk mark visible emails as read | Email section header → ⋯ menu → "Mark read: N visible". Sends a Graph `$batch` POST (chunked at 20 ops per batch when N > 20); selectively reverts only operations that failed. Tops up from the server if "more unread" remains. |
| Bulk mark visible "Other inbox" emails as read | Same menu → "Mark read: N in Other inbox" (visible only when N > 0). Uses Microsoft's Focused/Other classification from Graph's `inferenceClassification` field. |
| Bulk mark visible meeting notices as read | Same menu → "Mark read: N meeting notice(s)" (visible only when N > 0). Covers `meetingCancelled`, `meetingAccepted`, `meetingTentativelyAccepted`, `meetingDeclined` from Graph's `meetingMessageType` field. Leaves actionable `meetingRequest` invites alone. |
| Bulk mark visible mailing-list emails as read | Same menu → "Mark read: N mailing list(s)" (visible only when N > 0). Detected by the presence of an RFC 2369 `List-Unsubscribe` header in `internetMessageHeaders`. |
| Bulk mark visible external-sender emails as read | Same menu → "Mark read: N external sender(s)" (visible only when N > 0). External = sender's domain doesn't match the signed-in user's mail domain. |
| Mark all visible from this sender as read | Long-press an email row → "Mark read: N from this sender" (visible only when N > 1; same SMTP address) |
| Mark all visible with this subject as read | Long-press an email row → "Mark read: N with this subject" (visible only when N > 1). Subjects normalized: Re:/Fwd:/Fw:/Aw:/Sv: prefixes stripped iteratively, case-insensitive. |
| Bulk flag all unflagged visible emails | Same menu → "Flag N" (visible only when there are unflagged emails). |
| Bulk unflag all flagged visible emails | Same menu → "Unflag N" (visible only when there are flagged emails). |
| Restore today's emails to unread | Same menu → "Mark unread: today's emails", OR (when the email list is empty) the inline "Mark unread: today's emails" button under the section header. Fetches Inbox messages received between local midnight and now that are currently read, batch-marks them unread, refreshes. Registers an undo. |
| Copy the sender's email address | Long-press an email row → "Copy sender address". Writes the SMTP address to the system pasteboard. |
| Undo a bulk action | Floating "Undo" banner at the bottom of the screen for 8 seconds after any bulk mark-read / flag / mark-today-unread. |

## Teams chats

| Function | Triggered by |
|---|---|
| See chats with unread activity in the last 24 hours | Chats section, above emails. "Unread" uses Graph's per-user `viewpoint.lastMessageReadDateTime`: a chat is unread when the last message's `createdDateTime` is newer than the user's last-read timestamp. Reading the chat in any Teams client drops it from CheckIn automatically; new messages in a previously-replied chat re-surface. |
| See the sender plus other thread participants | "with A, B, C" line below the sender name; wraps to 2 lines, collapses to "with A, B +N" for big groups |
| Preview a chat | Tap a chat row. Opens a sheet with the last message body (cleaned plain text). Auto-marks the chat as read on open (advances `viewpoint.lastMessageReadDateTime` via `markChatReadForUser`). |
| Mark a chat back to unread | Preview sheet → "Mark unread" button (re-inserts in sent-time order; rolls back the server's read state via `markChatUnreadForUser`) |
| Reply to a chat | Preview sheet → "Reply" (composer with TextEditor), OR long-press → "Reply" (opens the preview sheet straight into the composer). Posts a new message into the existing chat thread via `POST /me/chats/{chatId}/messages`. |
| Mark a chat as read | Swipe right-to-left on the row, or long-press → "Mark read" |
| Open a chat in Teams | Long-press a chat row → "Open in Teams" (uses Graph's `chat.webUrl`, which iOS routes to the Teams app via Universal Links) |
| Copy chat link | Long-press → "Copy chat link". Writes the Teams chat URL to the system pasteboard. |
| Restore today's chats to unread | Inline "Mark unread: today's chats" button under the Chats section header when the section is empty. Fetches today's read chats and batch-flips them via `markChatUnreadForUser`. Registers an undo. |

## Teams presence & status

| Function | Triggered by |
|---|---|
| Set Teams presence (Available, Busy, Do not disturb, Be right back, Away, Offline) | Top of the Chats section → presence menu. Calls Graph's `setUserPreferredPresence` (1-day expiration) plus a private session via `setPresence` (PT1H, refreshed on every CheckIn refresh) so the preferred state holds even when no other Microsoft client is running. |
| Set Out of Office | Same presence menu → "Out of office" (peer of the regular presences). Enables Microsoft 365 auto-replies with a default message; preserves any existing internal/external auto-reply text. The presence menu shows a distinct purple OOO icon when active. |
| Reset Teams presence to auto | Same presence menu → "Reset to auto". Clears the preferred-presence override, clears OOO if set, re-fetches the current auto-detected state. |
| Set / edit a custom Teams status message | Chats section header → "Set message…" (when no message is set) or the existing message text (when one is set) → opens a sheet with a multi-line TextField. Calls `setStatusMessage` on Graph. |

## Settings

| Function | Triggered by |
|---|---|
| Open the Settings sheet | Top-right gear button, visible on both the summary screen and the sign-in screen (so a stuck custom registration can be undone before sign-in) |
| Enable / disable meeting reminders | Settings → "Meeting reminders" toggle (see Notifications above) |
| Override the Azure App Registration with your own | Settings → "Custom Azure registration" → enter Application (client) ID and/or Directory (tenant) ID → "Save and sign in" (signs out, rebuilds MSAL, sends you to Sign In) |
| Revert to Excelano's default registration | Settings → "Reset to defaults" |

## Home screen widget

| Function | Triggered by |
|---|---|
| Glance at next meeting + unread counts from the home screen | Add the CheckIn widget (medium size). Three-row meeting layout (calendar + time range / subject / countdown + organizer), unread email count, pending chat count. Refreshed by the main app on every refresh via `WidgetCenter`. Pre-generated timeline entries at each upcoming meeting start so back-to-back transitions don't require an app refresh. |
| Join the next meeting directly from the widget | Tap the "Join meeting" pill on the widget (visible within five minutes of the meeting's start when a join URL exists). Rewrites to `msteams:/` so iOS routes to Teams. |
| Set Teams presence from the widget | Tap any of the six presence pills on the medium widget (Available, Busy, Do not disturb, Be right back, Away, Offline). Runs in the widget extension via a shared `StatusActions`; uses the device's cached MSAL token to PATCH Graph; reloads the widget and Control Center controls when it returns. Optimistic UI; falls back to opening the app if silent token refresh fails. |
| Toggle Out of Office from the widget | Tap the OOO pill on the medium widget. Same execution path as the presence pills; flips Outlook auto-replies and clears any presence override. |

## Control Center controls (iOS 18+)

| Function | Triggered by |
|---|---|
| Toggle Out of Office from Control Center | Add the "Out of Office" toggle to Control Center. Reflects the live OOO state from the shared snapshot, runs `SetOutOfOfficeIntent` in the widget extension, reloads both the controls and the widgets on completion. |
| Quick-set Teams presence from Control Center | Add any of the six presence controls (Available, Busy, Do Not Disturb, Be Right Back, Away, Offline). One-tap action; same execution path as the widget pills. |
| Clear a presence override from Control Center | Add the "Reset to auto" control. Clears the preferred-presence override and any OOO state, then refetches the auto-detected presence. |

## App Intents / Siri shortcuts

| Function | Triggered by |
|---|---|
| Set presence by voice or Shortcut | "Set status to Busy in CheckIn" (Siri) or `SetStatusIntent` in Shortcuts. Same six presences as the widget plus "Reset to auto". |
| Toggle Out of Office by voice or Shortcut | "Turn on Out of Office in CheckIn" or `SetOutOfOfficeIntent` in Shortcuts. |
| Read unread email or pending chat count by voice or Shortcut | "What's my email count in CheckIn" routes through `CheckInCountIntent`. Returns an integer plus a spoken phrase. |
| Read unread from a sender by voice or Shortcut | "Anything from <name> in CheckIn" routes through `UnreadFromSenderIntent`. Returns the count of unread messages from the matched sender. |

App-name token always comes last in the phrasing ("in CheckIn") so Siri doesn't collide with the system's "Check In" Messages feature.

## iPad layout

| Function | Triggered by |
|---|---|
| Use CheckIn natively on iPad | Launch on iPad. The app declares `TARGETED_DEVICE_FAMILY = "1,2"` and `SummaryView` branches on `horizontalSizeClass`: compact width (iPhone, slide-over, narrow split) keeps the existing single-column list; regular width (full-screen iPad and most split configurations) uses a `NavigationSplitView` with the section list as the sidebar and the selected email, chat, or meeting as a persistent detail pane. |
| Preview an email, chat, or meeting in the detail pane | Tap a row on iPad. The same content the iPhone shows in a sheet (`MessagePreviewSheet`, `MeetingCard`, `ConflictResolutionSheet`) renders in the right pane instead. Selection survives orientation changes. |

## Apple Watch companion

| Function | Triggered by |
|---|---|
| See your CheckIn status from the wrist | Open the CheckIn watch app. Glance shows the presence pill (OOO dominates when active), next meeting (calendar + time range / subject / countdown — same three-row pattern as the phone), the "Later today" list, and pinned email + chat count chips at the bottom. The phone pushes the snapshot to the watch over WatchConnectivity; the watch holds no token and makes no Graph call. |
| Add CheckIn to a watch face or the Smart Stack | Four widget families share the same pushed snapshot. Corner complication shows a presence-colored circle with a cutout glyph and a curved countdown to the next meeting. Smart Stack rectangular tile shows the three-row meeting pattern with the count chips alongside. Circular complication shows a presence-tinted ring with the unread email count centered. Inline complication shows "Status sync in 12m" or "Inbox: 7 unread" depending on what's next. |
| Set Teams presence from the watch | Glance → presence menu. Same six presences plus OOO and Reset to auto. Tap relays the action to the phone via `WCSession.sendMessage` (live, when the phone is reachable) with `transferUserInfo` fallback. The phone executes the Graph PATCH and pushes a fresh snapshot back. |
| Trigger a refresh from the watch | Glance → refresh button (gray circle in the pinned counts row). Asks the phone to refresh and pushes the updated snapshot back. Auto-refreshes when the glance opens if the snapshot is over 60 seconds old. Surfaces "Phone unreachable" inline when WatchConnectivity can't deliver the request. |

## Not yet supported

- Compose a brand-new email from scratch (only Reply-all from existing messages)
- Move emails between folders / archive
- View past meetings (the calendar view is "today only")
- Open the specific calendar event for non-Teams meetings (only the calendar at large, via Teams)
- Edit the auto-reply message body (only the on/off state — edit the message itself in Outlook on the web)
- Watch app working standalone on cellular (opt-in independent watch sign-in; deferred to a later release)
