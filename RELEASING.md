# Releasing CheckIn to the App Store

The verified end-to-end flow for cutting a CheckIn release: bump the version,
archive, upload, fill in App Store Connect, and submit. This is the store
counterpart to the `run-checkin` skill, which covers dev installs on a device.
The gotchas below were each paid for once during the 1.0 and 1.1 cycles; the
point of this doc is to not pay for them again.

## Versioning is one edit

Marketing version and build number live in a single source of truth,
`Config/Version.xcconfig`. Every target inherits `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` from the project-level base configuration, so a release
bump is a two-line edit in that file and nothing else. Do not re-declare either
key in any target's build settings: a target-level value shadows the xcconfig and
the surfaces silently drift apart.

Build numbers are global and monotonic across the whole app record, independent of
the marketing version. 1.0.x ran through build 3, 1.1 was build 4, 1.1.1 was
build 5, so the next upload is build 6 regardless of whether it's a patch or a
feature release. App Store Connect rejects a build number it has already seen.

A historical trap, now fixed and worth remembering: `CheckIn/Info.plist` once
hardcoded the version as literals, which override the build settings, so the first
1.1 archive stamped the already-shipped 1.0.2 number. The plist now references
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` like the widget and watch
plists always did. If an archive ever ships with the wrong version, suspect a
literal somewhere beating the build setting.

## Archive and upload (Xcode, on the Mac)

1. Set the run destination to **Any iOS Device (arm64)**. Archive is greyed out
   while a simulator or a specific device is selected.
2. **Product → Archive.** This builds the release configuration and opens the
   Organizer when it finishes. The watch app and both widget extensions are
   embedded in the archive automatically; you do not archive them separately.
3. In the Organizer, select the new archive, then **Distribute App → App Store
   Connect → Upload**, taking the defaults on signing (it uses the team
   distribution cert).
4. Ignore the `MSAL.framework` dSYM "Upload Symbols Failed" warning. MSAL is a
   third-party binary with no symbols to symbolicate; it is harmless and not a
   blocker.
5. After "Upload Successful," give App Store Connect roughly ten to fifteen
   minutes to finish processing before the build becomes attachable.

## App Store Connect (web)

Create the version page first if it doesn't exist ("+ Version or Platform" on the
app's page), so the processed build has somewhere to attach. Then attach the new
build in the Build section, paste the "What's New" copy, confirm the release
option (Automatic releases the moment it's approved; Manual waits for you to click
Release), and Submit for Review.

Metadata that must be right on a feature release, learned from 1.1:

- **App Privacy** stays "Data Not Collected." CheckIn adds no data egress between
  releases; the only cross-device traffic is non-credential status over
  WatchConnectivity. Revisit this only if a release genuinely changes what leaves
  the device.
- **App Review** needs Sign-In Required on, with the standing demo M365 account
  and reviewer notes, because the app is unusable without a Microsoft sign-in.
- **Screenshots** have strict sizes. iPhone 6.9" is 1320×2868 and iPad 13" is
  2064×2752. The Apple Watch set must use an accepted size (422×514, 410×502,
  416×496, 396×484, 368×448, or 312×390) and one set scales to all; App Store
  Connect rejects the 41mm 352×430 size outright.
- **iPad orientations:** because the app is universal (`TARGETED_DEVICE_FAMILY =
  "1,2"`), upload validation requires `UISupportedInterfaceOrientations~ipad` to
  list all four orientations for multitasking, even though the iPhone stays
  portrait-only. Missing this fails the upload.

The store listing text and reviewer notes are kept out of git in
`app-store-connect-metadata.md` (gitignored). Per-release paste sheets are staged
on the Desktop and discarded after use.

## Tag the release

After the build is uploaded and submitted, tag the exact commit it was built from,
annotated, matching the existing scheme `vMAJOR.MINOR.PATCH`:

```bash
git tag -a v1.1.1 -m "CheckIn 1.1.1 — <one-line scope> (build 5, submitted to App Store <date>)" <commit>
git push origin v1.1.1
```

## If a submission is rejected

A build can't be hot-swapped into an in-flight review. Fix the issue, bump to the
next build number (edit `Config/Version.xcconfig`), re-archive, re-upload, and
resubmit. The likeliest rejection causes for this app are the demo-account sign-in
path (MFA or Conditional Access blocking the reviewer) and, on universal builds,
an iPad-layout note.
