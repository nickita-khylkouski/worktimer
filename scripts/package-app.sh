#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WorkTimer"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"
NOTES_PATH="$DIST_DIR/README-SEND-TO-FRIENDS.txt"

"$ROOT_DIR/scripts/install-app.sh" release --no-open

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$NOTES_PATH"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cat > "$NOTES_PATH" <<'EOF'
WorkTimer for macOS

Requirements:
- macOS 14 or newer

Install:
1. Unzip WorkTimer-macOS.zip
2. Drag WorkTimer.app into Applications
3. Open WorkTimer.app

How it works:
- The app appears in the top-right menu bar.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Timer and pay tracking work immediately.
- Typing stats and mouse travel need Accessibility and Input Monitoring.

If they see a macOS warning because the app is unsigned:
1. Move WorkTimer.app into Applications first
2. Control-click the app
3. Choose Open
4. Choose Open again in the confirmation dialog

If they use Ice/Bartender:
- The menu bar item may start in the hidden section first

Launch at login:
- WorkTimer tries to enable launch-at-login automatically
- If macOS asks for approval, check System Settings > General > Login Items

Permissions for typing and mouse stats:
- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Input Monitoring
- Turn on WorkTimer in both places
EOF

echo "Created $ZIP_PATH"
echo "Created $NOTES_PATH"
