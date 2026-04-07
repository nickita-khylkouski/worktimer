#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WorkTimer"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"
NOTES_PATH="$DIST_DIR/README-SEND-TO-FRIENDS.txt"
NOTARIZE=0
ASC_PROFILE="${ASC_PROFILE:-Personal}"
PACKAGE_TRUST_NOTE="This package is signed with Developer ID. If it was not notarized yet, macOS may still ask you to confirm opening it."

for arg in "$@"; do
  case "$arg" in
    --notarize)
      NOTARIZE=1
      ;;
    --profile=*)
      ASC_PROFILE="${arg#--profile=}"
      ;;
    *)
      echo "Usage: ./scripts/package-app.sh [--notarize] [--profile=Personal]" >&2
      exit 1
      ;;
  esac
done

"$ROOT_DIR/scripts/install-app.sh" release --no-open

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$NOTES_PATH"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  if ! command -v asc >/dev/null 2>&1; then
    echo "asc is required for notarization." >&2
    exit 1
  fi

  echo "Submitting $ZIP_PATH for notarization with profile $ASC_PROFILE"
  asc --profile "$ASC_PROFILE" notarization submit --file "$ZIP_PATH" --wait --output json
  xcrun stapler staple "$APP_DIR"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
  PACKAGE_TRUST_NOTE="This package was notarized and the app bundle was stapled after Apple accepted the submission."
fi

cat > "$NOTES_PATH" <<EOF
WorkTimer for macOS

Requirements:
- macOS 14 or newer

Install:
1. Unzip WorkTimer-macOS.zip
2. Drag WorkTimer.app into Applications
3. Open WorkTimer.app

How it works:
- The app appears in the top-right menu bar.
- The app also appears in the Dock while it is running.
- Single click pauses or resumes.
- Double click opens the panel.
- Right click opens the panel.
- Timer and pay tracking work immediately.
- Typing stats and mouse travel need Accessibility and Input Monitoring.

$PACKAGE_TRUST_NOTE

If macOS still asks for confirmation:
1. Move WorkTimer.app into Applications first
2. Control-click the app
3. Choose Open
4. Choose Open again in the confirmation dialog

If the package was notarized and stapled already:
- The first-run warning should be much smaller or absent
- Gatekeeper can still ask for confirmation if the file was changed after packaging

If they use Ice/Bartender:
- The menu bar item may start in the hidden section first

Launch at login:
- WorkTimer tries to enable launch-at-login automatically
- If macOS asks for approval, check System Settings > General > Login Items

Permissions for typing and mouse stats:
- Move WorkTimer.app into Applications before granting permissions
- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Input Monitoring
- Turn on WorkTimer in both places
- Quit and reopen WorkTimer once after enabling both switches
EOF

echo "Created $ZIP_PATH"
echo "Created $NOTES_PATH"
