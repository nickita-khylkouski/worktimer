# WorkTimer

WorkTimer is a small macOS menu bar app for tracking work time, typing time, live pay, and simple daily history from the top-right of the screen.

## Features

- Count-up timer in the menu bar
- Single click to pause/resume
- Double click or right click to open the panel
- Daily auto-reset with history
- Optional live pay tracking
- Typing stats:
  - typing time
  - character count
  - CPM
  - WPM
- Menu bar display modes:
  - timer
  - money
  - typing time
  - CPM
  - WPM
  - character count
  - icon
- Launch at login

## Requirements

- macOS 14 or newer
- Xcode 16 or Swift 6 toolchain

## Install

```bash
./scripts/install-app.sh
```

This builds the app, installs `~/Applications/WorkTimer.app`, signs it ad hoc, and opens it.

## Use

- Look in the top-right macOS menu bar.
- Single click pauses or resumes the timer.
- Double click opens the panel.
- Right click opens the panel.

If you use Ice or Bartender, the item may start in the hidden section first.

## Launch Again Later

```bash
./scripts/open-app.sh
```

## Make A Shareable Zip

```bash
./scripts/package-app.sh
```

This creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

## Privacy / Permissions

Typing stats require:

- Accessibility
- Input Monitoring

If macOS asks for approval, check:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`
- `System Settings > General > Login Items`

## Development

Run:

```bash
swift run WorkTimer
```

Test:

```bash
swift test
```

## Local Data

- Session state: `~/Library/Application Support/WorkTimer/session.json`
- Typing stats DB: `~/Library/Application Support/WorkTimer/typing.sqlite`
