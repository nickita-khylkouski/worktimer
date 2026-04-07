# WorkTimer

Small macOS menu bar timer for tracking work time from the top-right of the screen.

## What It Does

- Starts counting up as soon as the app launches.
- Lives in the macOS menu bar.
- Also appears in the Dock while running.
- Tries to register itself to launch at login.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Resets automatically each day and keeps a daily log.
- Can show timer, money, typing stats, mouse distance, or an icon in the menu bar.
- Saves the current day session locally, so relaunching the app does not wipe the timer.
- Tracks typing time, chars, CPM, WPM, and estimated on-screen mouse travel.

## Requirements

- macOS 14 or newer
- Xcode 16 or current Swift 6 toolchain

## Install

```bash
cd apps/typekeep
./scripts/install-app.sh
```

That builds a release app, installs it to `~/Applications/WorkTimer.app`, and opens it.

The installer will use your personal `Developer ID Application` certificate if one is available in Keychain. Otherwise it falls back to ad hoc signing for local use.

## Setup For Full Stats

Timer and pay tracking work right away.

Typing and mouse stats need macOS privacy approval:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`
- move `WorkTimer.app` into `Applications` before granting permissions
- after turning on both switches, quit and reopen `WorkTimer` once

You can jump straight there with:

```bash
cd apps/typekeep
./scripts/open-permissions.sh
```

If permissions get stuck and you want to re-grant them cleanly:

```bash
cd apps/typekeep
./scripts/reset-permissions.sh
./scripts/open-permissions.sh
```

## Launch Again Later

```bash
cd apps/typekeep
./scripts/open-app.sh
```

or:

```bash
open -na ~/Applications/WorkTimer.app
```

## Make A Sendable Build

```bash
cd apps/typekeep
./scripts/package-app.sh
```

That creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

To build a notarized zip with your personal ASC auth profile:

```bash
cd apps/typekeep
./scripts/package-app.sh --notarize --profile=Personal
```

## First-Run Behavior

- The app should appear in the top-right menu bar area.
- The app should also appear in the Dock while it is running.
- The app also attempts to turn on launch-at-login automatically.
- If macOS asks for approval, check `System Settings > General > Login Items`.
- If you want typing stats or mouse travel, approve `WorkTimer` in both `Accessibility` and `Input Monitoring`.
- If you use Ice, Bartender, or another menu bar organizer, it may appear in the hidden section first.
- The default panel is simple black/white, with:
  - current timer
  - small reset button
  - hourly pay input
  - top-bar mode switch
  - typing stats
  - mouse travel stats
  - daily history
  - action log

## Development

Run directly from SwiftPM:

```bash
cd apps/typekeep
swift run WorkTimer
```

Run tests:

```bash
cd apps/typekeep
swift test
```

## Notes

- WorkTimer data now lives in `~/Library/Application Support/WorkTimer/worktimer.sqlite`.
- Older `typing.sqlite` installs are migrated automatically the first time the new build launches.
- Updating or reinstalling the app should preserve the current day timer and history.
- Mouse distance is an estimate of cursor travel on the display surface, based on display size reported by macOS.
