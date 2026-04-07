#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WorkTimer"
BUILD_CONFIGURATION="release"
OPEN_AFTER_INSTALL=1

for arg in "$@"; do
  case "$arg" in
    debug|release)
      BUILD_CONFIGURATION="$arg"
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=0
      ;;
    *)
      echo "Usage: ./scripts/install-app.sh [debug|release] [--no-open]" >&2
      exit 1
      ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Xcode 16 or the matching Command Line Tools first." >&2
  exit 1
fi

ROOT_BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/${BUILD_CONFIGURATION}"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
EXECUTABLE_PATH="$ROOT_BUILD_DIR/${APP_NAME}"

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"

mkdir -p "$HOME/Applications"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -d "$ROOT_DIR/AppBundle/Resources" ]; then
  cp -R "$ROOT_DIR/AppBundle/Resources/." "$APP_DIR/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  sleep 0.2
fi

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
  open -na "$APP_DIR"
fi

cat <<EOF
Installed ${APP_DIR}

What to expect:
- WorkTimer launches as a menu bar app and should appear at the top-right of the screen.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Timer and pay tracking work immediately.
- Typing stats and mouse travel need Accessibility and Input Monitoring.

If you use Ice or another menu bar organizer, the item may start in the hidden section first.

Helpful commands:
- Open permissions panes: ./scripts/open-permissions.sh
- Reset permissions cleanly: ./scripts/reset-permissions.sh
- Relaunch app: ./scripts/open-app.sh
EOF
