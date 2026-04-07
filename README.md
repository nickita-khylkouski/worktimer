# WorkTimer

<p align="center">
  <img src="AppBundle/Resources/AppIcon.png" alt="WorkTimer icon" width="128" height="128">
</p>

<p align="center">
  A macOS menu bar work timer with pay tracking, typing stats, mouse travel, daily history, and a small control panel.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/App-Menu%20Bar%20%2B%20Dock-white" alt="Menu Bar and Dock">
</p>

## Why It Exists

WorkTimer is for keeping one lightweight timer visible all day without opening a full time-tracking app.

It can show:

- elapsed work time
- live earnings
- typing time
- CPM
- WPM
- total chars
- mouse travel

## Features

- Lives in the macOS menu bar and also appears in the Dock while running.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Resets automatically each day and keeps a daily log.
- Tracks hourly pay and live earnings.
- Tracks typing time, chars, CPM, and WPM.
- Tracks estimated on-screen mouse travel.
- Saves session state and history in a local SQLite database.
- Tries to enable launch at login automatically.

## Install

### Option 1: Build locally

```bash
git clone https://github.com/nickita-khylkouski/worktimer.git
cd worktimer
./scripts/install-app.sh
```

This installs:

- `~/Applications/WorkTimer.app`

### Option 2: Share a packaged app

```bash
./scripts/package-app.sh
```

This creates:

- `dist/WorkTimer-macOS.zip`
- `dist/README-SEND-TO-FRIENDS.txt`

## First Run

1. Move `WorkTimer.app` into `Applications`.
2. Open `WorkTimer.app`.
3. If you want typing stats or mouse stats, enable `WorkTimer` in:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`

4. Reopen `WorkTimer` once after enabling both switches.

Helper command:

```bash
./scripts/open-permissions.sh
```

If privacy permissions get stuck:

```bash
./scripts/reset-permissions.sh
./scripts/open-permissions.sh
```

## Data

WorkTimer stores its local data here:

- `~/Library/Application Support/WorkTimer/worktimer.sqlite`

That includes:

- current session state
- daily history
- settings
- typing sessions

Mouse distance is stored as estimated screen-surface travel based on display size reported by macOS.

## Controls

- `Click`: pause or resume
- `Double-click`: open panel
- `Right-click`: open panel

From the panel you can:

- change the top bar mode
- set hourly pay
- edit today’s worked time
- reset the timer
- review daily history
- review pause, resume, and reset log entries

## Development

Run the app directly:

```bash
swift run WorkTimer
```

Run tests:

```bash
swift test
```

## Distribution Notes

- Local installs are signed with Developer ID when the maintainer certificate is available.
- Public installs may still show Gatekeeper friction until the packaged build is notarized and stapled.
- If a friend reports that keyboard tracking does not work, the first thing to check is whether the app is in `Applications` and enabled in both privacy panes above.
