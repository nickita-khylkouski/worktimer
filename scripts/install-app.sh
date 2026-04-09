#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WorkTimer"
BUILD_CONFIGURATION="release"
OPEN_AFTER_INSTALL=1
APP_PARENT_DIR="${WORKTIMER_INSTALL_DIR:-$HOME/Applications}"

resolve_signing_identity() {
  if [[ -n "${WORKTIMER_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$WORKTIMER_SIGN_IDENTITY"
    return 0
  fi

  local personal_identity
  personal_identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application: Nickita Khy \\(HSRWKMA3SL\\)/ { print $2; exit }')"
  if [[ -n "$personal_identity" ]]; then
    printf '%s\n' "$personal_identity"
    return 0
  fi

  local any_developer_id
  any_developer_id="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application:/ { print $2; exit }')"
  if [[ -n "$any_developer_id" ]]; then
    printf '%s\n' "$any_developer_id"
  fi
}

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

APP_DIR="$APP_PARENT_DIR/${APP_NAME}.app"

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/${APP_NAME}"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Built executable was not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

mkdir -p "$APP_PARENT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -d "$ROOT_DIR/AppBundle/Resources" ]; then
  cp -R "$ROOT_DIR/AppBundle/Resources/." "$APP_DIR/Contents/Resources/"
fi

SIGNING_IDENTITY="$(resolve_signing_identity || true)"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
  SIGNING_SUMMARY="Developer ID signed with: $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP_DIR"
  SIGNING_SUMMARY="Ad hoc signed (no Developer ID identity found)"
fi

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
- WorkTimer now also appears in the Dock while running.
- The setup panel should open automatically on first launch.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Timer and pay tracking work immediately.
- Typing stats and mouse travel need Accessibility and Input Monitoring.

Signing:
- ${SIGNING_SUMMARY}

If you use Ice or another menu bar organizer, the item may start in the hidden section first.

Helpful commands:
- Open permissions panes: ./scripts/open-permissions.sh
- Reset permissions cleanly: ./scripts/reset-permissions.sh
- Relaunch app: ./scripts/open-app.sh
- Inspect trust + install state: ./scripts/doctor.sh
EOF
