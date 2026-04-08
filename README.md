# WorkTimer

Minimal macOS menu bar time tracker with live pay, typing stats, mouse travel, AI usage, disk counters, and Wispr Flow stats.

## What It Is

WorkTimer lives in the menu bar, starts counting immediately, and gives you a small control panel instead of a full main window.

It can show any of these in the top bar:

- timer
- money
- typing time
- CPM
- WPM
- character count
- mouse travel
- AI total
- AI tokens per second
- AI today
- disk read
- disk write
- SSD wear
- icon only

## What It Tracks

- work time with pause, resume, reset, and daily rollover
- hourly pay with live earnings
- typing time, chars, CPM, and WPM
- estimated on-screen mouse travel
- local Codex and Claude usage
- SSD read/write counters and wear
- Wispr Flow words, clips, and dictation time

Most local state is stored in:

`~/Library/Application Support/WorkTimer/worktimer.sqlite`

## Install

### Fastest path

1. Download `WorkTimer.app` or `WorkTimer-macOS.zip`
2. Drag `WorkTimer.app` into `/Applications` or `~/Applications`
3. Open it
4. The setup panel should appear on first launch

If the menu bar item seems missing, check the hidden section in Ice, Bartender, or other menu bar organizers first.

### Build from source

```bash
swift test
./scripts/install-app.sh
```

That installs the app to:

`~/Applications/WorkTimer.app`

## First Launch Setup

Timer and pay tracking work right away.

Typing and mouse stats need macOS privacy approval:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`

Important:

- move `WorkTimer.app` into `Applications` before granting permissions
- if privacy permissions were granted after launch, reopen the app once
- the app also registers for launch at login, and macOS may ask you to approve that in `Login Items`

Open both permission panes directly:

```bash
./scripts/open-permissions.sh
```

If permissions get stuck:

```bash
./scripts/reset-permissions.sh
./scripts/open-permissions.sh
```

Inspect the installed app’s signing and trust state:

```bash
./scripts/doctor.sh
```

## Controls

- left click: pause or resume
- double left click: open the panel
- right click: open the panel
- `Esc`: hide the panel

Inside the panel you can:

- reset the timer
- edit today’s worked time
- change the hourly rate
- switch what the top bar shows
- inspect daily history and action logs

## AI Usage

WorkTimer reads local Codex and Claude usage from local logs and snapshots when available.

If `AI /s` is selected, the panel shows a 30-minute sparkline. Hovering the graph shows the exact rate at that sample plus the sample time.

## Wispr Flow

If Wispr Flow is installed locally, WorkTimer reads:

- words today
- clips today
- dictation time today

It auto-detects the standard local Wispr Flow database and falls back cleanly if it is unavailable.

## Packaging

Create a sendable build:

```bash
./scripts/package-app.sh
```

That creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

If you have Developer ID + notarization set up:

```bash
./scripts/package-app.sh --notarize --profile=Personal
```

## Notes

- macOS 14+ recommended
- the app is designed to be small and persistent, not a full desktop timer app
- mouse travel is an estimate of cursor movement across the display surface, not literal hand movement
- AI usage depends on local tool logs existing on that machine
- updating the app should preserve the current day timer and history
