# CheckIn: Features

What a user can do, mapped to the entry point in the UI.

| Function | Triggered by |
|---|---|
| Sign in with Microsoft 365 | "Sign In with Microsoft" button on launch when signed out |
| Sign out | Settings sheet → Sign Out (with confirm dialog; the section is hidden when not signed in) |
| Refresh inbox (meeting, chats, emails) | Pull-to-refresh on the list or empty-day state |
| See next meeting in the next 24 hours | Top of the list when one exists; cancelled events and events you've declined are skipped |
| Join that meeting in Teams | Tap the meeting card (falls back to Outlook Calendar if no Teams join URL) |
| Open Outlook Calendar | Tap a non-Teams meeting card |
| RSVP to a meeting (Accept / Maybe / Decline) | Three buttons under the meeting info, visible when you haven't responded; optimistic update, POSTs to Graph with sendResponse=true |
| See your current RSVP state on a responded meeting | Pill ("Accepted", "Tentative", "Declined") under the meeting info, in place of the buttons |
| Auto-mark matching invite emails read after RSVP | After a successful RSVP, unread emails whose subject matches the meeting subject (or "Updated: ..." / "Cancelled: ...") are marked read |
| See up to 20 newest unread emails | Email section |
| See the count of additional unread beyond the 20 shown | "N more unread" footer line under the email section, when total unread > 20 |
| Read each email's sender, subject, and preview | Each row shows sender + relative time, subject, and Graph's bodyPreview (up to 2 lines) |
| See a flag indicator on flagged emails | Orange flag icon next to the sender name |
| Reply to an email in Outlook | Tap an email row (opens Outlook compose with `Re: <subject>` to the sender) |
| Mark an email read | Swipe right-to-left on the row (optimistic, reverts on failure) |
| Flag / unflag an email | Swipe left-to-right on the row (optimistic, reverts on failure) |
| See pending Teams chats from the last 24 hours where someone else sent the last message | Chats section, above emails |
| See the sender plus other thread participants | "with A, B, C" line below the sender name; wraps to 2 lines, collapses to "with A, B +N" for big groups |
| Open a chat in Teams | Tap a chat row (falls back to the Teams app if no chat URL) |
| Override the Azure App Registration with your own | Settings → "Custom Azure registration" → enter Application (client) ID and/or Directory (tenant) ID → "Save and sign in" (signs out, rebuilds MSAL, sends you to Sign In) |
| Revert to Excelano's default registration | Settings → "Reset to defaults" |
| Open the Settings sheet | Top-right gear button, visible on both the summary screen and the sign-in screen (so a stuck custom registration can be undone before sign-in) |

## Not yet supported

- Delete an email
- Reply to a chat from inside the app (the tap hands off to Teams)
- Open the specific calendar event for non-Teams meetings (only the calendar at large)
