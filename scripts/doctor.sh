#!/bin/zsh
set -euo pipefail

APP_CANDIDATES=(
  "${WORKTIMER_INSTALL_DIR:-$HOME/Applications}/WorkTimer.app"
  "$HOME/Applications/WorkTimer.app"
  "/Applications/WorkTimer.app"
)

APP_DIR=""
for candidate in "${APP_CANDIDATES[@]}"; do
  if [[ -d "$candidate" ]]; then
    APP_DIR="$candidate"
    break
  fi
done

if [[ -z "$APP_DIR" ]]; then
  echo "WorkTimer.app not found in ~/Applications or /Applications"
  exit 1
fi

echo "App:"
echo "- path: $APP_DIR"

echo
echo "Code signing:"
codesign -dv --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/- /'

echo
echo "Gatekeeper:"
if spctl --assess --type execute --verbose=4 "$APP_DIR" >/tmp/worktimer-spctl.txt 2>&1; then
  sed 's/^/- /' /tmp/worktimer-spctl.txt
else
  sed 's/^/- /' /tmp/worktimer-spctl.txt
fi

echo
echo "Helpful next steps:"
echo "- Open app: ./scripts/open-app.sh"
echo "- Open permissions: ./scripts/open-permissions.sh"
echo "- Reset permissions: ./scripts/reset-permissions.sh"
