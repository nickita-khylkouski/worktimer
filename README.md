<p align="center">
  <img src="AppBundle/Resources/AppIcon.png" alt="WorkTimer icon" width="120" height="120">
</p>

<h1 align="center">WorkTimer</h1>

<p align="center">
  Small macOS menu bar work tracker with live pay, typing stats, mouse travel, AI usage, disk counters, and Wispr Flow stats.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/app-menu%20bar%20%2B%20Dock-white" alt="Menu bar and Dock">
  <img src="https://img.shields.io/badge/storage-local%20SQLite-blue" alt="Local SQLite">
</p>

## Overview

WorkTimer is a menu bar app that starts counting immediately, stays small, and keeps the important controls one click away.

It can show any of these in the top bar:

| Mode | What it shows |
| --- | --- |
| `Timer` | Live work timer |
| `Money` | Live earnings |
| `Type Time` | Active typing time |
| `CPM` / `WPM` | Typing speed |
| `Chars` | Character count |
| `Mouse` | Estimated cursor travel |
| `AI Total` / `AI /s` / `AI Today` | Local AI usage |
| `Disk Read` / `Disk Write` / `SSD Wear` | SSD stats |
| `Icon` | Compact icon mode |

## Features

| Area | Included |
| --- | --- |
| Time tracking | Pause, resume, reset, daily rollover, history |
| Money | Hourly pay input and live earnings |
| Typing | Time, chars, CPM, WPM |
| Mouse | Estimated on-screen travel distance |
| AI | Local Codex + Claude totals and token-rate graph |
| Wispr Flow | Words today, clips today, dictation time |
| Disk | Read, write, wear, SMART-style counters |

Local state is stored in:

`~/Library/Application Support/WorkTimer/worktimer.sqlite`

## Install

### Downloaded app

1. Download `WorkTimer.app` or `WorkTimer-macOS.zip`
2. Move `WorkTimer.app` into `/Applications` or `~/Applications`
3. Open it
4. The setup panel should guide the rest

If the menu bar item looks missing, check Ice, Bartender, or the hidden menu bar section first.

### Build from source

```bash
swift test
./scripts/install-app.sh
```

That installs to:

`~/Applications/WorkTimer.app`

## First Launch

Timer and pay tracking work immediately.

Typing and mouse stats need macOS privacy approval:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`

Rules that matter:

- move the app into `Applications` before granting permissions
- if permissions were granted after launch, reopen the app once
- launch-at-login may need approval in `Login Items`

Useful scripts:

```bash
./scripts/open-permissions.sh
./scripts/reset-permissions.sh
./scripts/open-app.sh
./scripts/doctor.sh
```

## Controls

| Action | Result |
| --- | --- |
| Left click | Pause or resume |
| Double left click | Open panel |
| Right click | Open panel |
| `Esc` | Hide panel |

Inside the panel you can:

- reset the timer
- edit today’s time
- change hourly pay
- switch top-bar display modes
- inspect history and logs
- hover the `AI /s` graph for exact sample values

## AI Usage

WorkTimer reads local Codex and Claude usage from local logs and snapshots when available.

When `AI /s` is selected, the panel shows a 30-minute sparkline. Hovering the graph shows the exact rate and the sample time for that point.

## Wispr Flow

If Wispr Flow is installed locally, WorkTimer reads:

- words today
- clips today
- dictation time today

The monitor auto-detects the standard local Wispr Flow database and falls back cleanly if it is missing.

## Packaging

Create a sendable build:

```bash
./scripts/package-app.sh
```

That creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

If you have Developer ID + notarization configured:

```bash
./scripts/package-app.sh --notarize --profile=Personal
```

## Notes

- macOS 14+ recommended
- mouse travel is an estimate of cursor movement across the display surface, not literal hand movement
- AI usage depends on local logs existing on that machine
- updating the app should preserve the current day timer and history
