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

## Quick Start For Someone Downloading The App

If you are just receiving `WorkTimer.app` or `WorkTimer-macOS.zip`, do this:

1. Unzip it
2. Drag `WorkTimer.app` into `/Applications` or `~/Applications`
3. Open it
4. The setup panel should open automatically on first launch
5. If you want typing and mouse stats, press the in-app `Grant Access` button and enable WorkTimer in:
   - `System Settings > Privacy & Security > Accessibility`
   - `System Settings > Privacy & Security > Input Monitoring`

If the menu bar item is missing, check the hidden section in Ice/Bartender first.

## Requirements

- macOS 14 or newer
- Xcode 16 or current Swift 6 toolchain

## Developer Install

```bash
cd apps/worktimer
./scripts/install-app.sh
```

That builds a release app, installs it to `~/Applications/WorkTimer.app`, and opens it.

If you want a different install location, set:

```bash
WORKTIMER_INSTALL_DIR=/Applications ./scripts/install-app.sh
```

The installer will use your personal `Developer ID Application` certificate if one is available in Keychain. Otherwise it falls back to ad hoc signing for local use.

## Setup For Full Stats

Timer and pay tracking work right away.

AI usage is optional and only appears when WorkTimer can find local Codex/Claude logs or compatible usage snapshot files.

Wispr Flow stats are optional and only appear when Wispr Flow is installed locally.

Typing and mouse stats need macOS privacy approval:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`
- move `WorkTimer.app` into `/Applications` or `~/Applications` before granting permissions
- WorkTimer retries automatically after both switches are on, but if stats still look stuck, reopen `WorkTimer` once

You can jump straight there with:

```bash
cd apps/worktimer
./scripts/open-permissions.sh
```

If permissions get stuck and you want to re-grant them cleanly:

```bash
cd apps/worktimer
./scripts/reset-permissions.sh
./scripts/open-permissions.sh
```

To inspect the installed app’s trust state and path:

```bash
cd apps/worktimer
./scripts/doctor.sh
```

## Launch Again Later

```bash
cd apps/worktimer
./scripts/open-app.sh
```

or:

```bash
open -na ~/Applications/WorkTimer.app
```

## Make A Sendable Build

```bash
cd apps/worktimer
./scripts/package-app.sh
```

That creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

That is the preferred non-developer onboarding path for another person.

To build a notarized zip with your personal ASC auth profile:

```bash
cd apps/worktimer
./scripts/package-app.sh --notarize --profile=Personal
```

## First-Run Behavior

- The app should appear in the top-right menu bar area.
- The app should also appear in the Dock while it is running.
- On first launch, the setup panel should open automatically.
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
cd apps/worktimer
swift run WorkTimer
```

Run tests:

```bash
cd apps/worktimer
swift test
```

## Notes

- WorkTimer data now lives in `~/Library/Application Support/WorkTimer/worktimer.sqlite`.
- Older `typing.sqlite` installs are migrated automatically the first time the new build launches.
- Updating or reinstalling the app should preserve the current day timer and history.
- Mouse distance is an estimate of cursor travel on the display surface, based on display size reported by macOS.
- Wispr Flow stats are detected automatically from the local `flow.sqlite` database when Wispr Flow is installed.
