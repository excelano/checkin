---
name: run-checkin
description: Build, install, launch, and stream debug output for the CheckIn iOS app on David's paired iPhone 15.
---

# Running CheckIn on the device

This is the verified flow for building CheckIn, installing it on David's
paired iPhone 15, launching it, and capturing debug output. Use this
instead of rediscovering — the device identifiers, log-capture gotchas,
and buffering pitfalls are baked in.

## Devices

Two different identifiers exist for the same phone. They are NOT
interchangeable.

| Use with | Identifier | Source |
|---|---|---|
| `xcodebuild -destination` | `00008120-001019EA18834032` (hardware UDID) | `xcodebuild -showdestinations` |
| `xcrun devicectl device ...` | `8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC` (devicectl id) | `xcrun devicectl list devices` |

If you get `Unable to find a device matching the provided destination
specifier`, you've used the devicectl id where xcodebuild expected the
hardware UDID.

## Build

```bash
xcodebuild -project /Users/anderix/checkin/CheckIn.xcodeproj \
  -scheme CheckIn -configuration Debug \
  -destination "platform=iOS,id=00008120-001019EA18834032" \
  -allowProvisioningUpdates build
```

`-allowProvisioningUpdates` lets Xcode refresh the provisioning profile
if needed. Without it you'll hit signing errors after profile renewals.

## Install

```bash
xcrun devicectl device install app \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
  ~/Library/Developer/Xcode/DerivedData/CheckIn-*/Build/Products/Debug-iphoneos/CheckIn.app
```

## Launch

Plain launch (no log capture, returns immediately):

```bash
xcrun devicectl device process launch \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
  com.excelano.checkin
```

Launch with stdout/stderr attached (devicectl waits for the app to
terminate):

```bash
xcrun devicectl device process launch \
  --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
  --console com.excelano.checkin
```

## Capturing debug output

**`os.Logger` does NOT flow through `--console`.** os.Logger writes to
the device's unified system log, which is a separate channel from
stdout/stderr. `--console` captures only the standard streams.

Two paths to capture os.Logger output:

1. Xcode > Window > Devices and Simulators > select device > Open Console.
   Filters on the unified log from the device. Reliable, but interactive.
2. For automated capture from a script, switch to `print()` temporarily.
   `print()` writes to stdout, which `--console` captures.

For ad-hoc diagnostics from a script, the `print()` path is much
faster than wiring up the unified log:

```swift
#if DEBUG
print("CHECKIN-DEBUG body bytes: \(rawBytes)")
#endif
```

Prefix with a unique token like `CHECKIN-DEBUG` so you can grep
cleanly out of the full console stream.

### Pre-wired hooks

Existing `#if DEBUG` print hooks already in the codebase, ready to
use without modifying code:

| Location | What it prints |
|---|---|
| `CheckIn/Views/MessagePreviewSheet.swift` → `loadBodyIfNeeded()` | Raw email body bytes with line breaks tokenized as `[CRLF]`, `[LF]`, `[CR]` |

Add more here as they get added. Removing them is cheap; re-adding
under deadline pressure is not.

## Streaming captured logs

When piping the `--console` output through `grep`, **always use
`grep --line-buffered`**. Without it, the pipe buffers and the file
fills only when many KB accumulate — which means short bursts of
debug output never appear.

Wrong (silent):

```bash
xcrun devicectl device process launch --console ... | grep "CHECKIN-DEBUG"
```

Right:

```bash
xcrun devicectl device process launch --console ... > /tmp/checkin.out 2>&1 &
tail -f /tmp/checkin.out | grep --line-buffered "CHECKIN-DEBUG"
```

The two-step approach (let the launcher write everything to a file,
then `tail -f | grep --line-buffered` on the file) avoids the inline
pipe buffering entirely.

## Verifying device readiness

Before any of the above, confirm the phone is paired and reachable:

```bash
xcrun devicectl list devices
```

If the phone shows as `unavailable`, prompt David to wake it and
unlock. devicectl needs the device unlocked to install apps.

## End-to-end one-liner

For the common "build, install, launch, get out" pattern:

```bash
xcodebuild -project /Users/anderix/checkin/CheckIn.xcodeproj \
  -scheme CheckIn -configuration Debug \
  -destination "platform=iOS,id=00008120-001019EA18834032" \
  -allowProvisioningUpdates build 2>&1 | tail -3 \
&& xcrun devicectl device install app \
     --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
     ~/Library/Developer/Xcode/DerivedData/CheckIn-*/Build/Products/Debug-iphoneos/CheckIn.app 2>&1 | tail -3 \
&& xcrun devicectl device process launch \
     --device 8BE2DDC5-4B5A-5ECF-BD04-3549096ADABC \
     com.excelano.checkin 2>&1 | tail -2
```

About 30 seconds end-to-end on a warm DerivedData cache.

## Test target

`CheckInWidgetExtension` and `CheckInTests` are separate targets/schemes.
For widget-only changes, use `-scheme CheckInWidgetExtension`. For unit
tests, `xcodebuild test` against the `CheckInTests` scheme.
