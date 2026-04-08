#!/bin/zsh
set -euo pipefail

APP_DIRS=(
  "$HOME/Applications/WorkTimer.app"
  "/Applications/WorkTimer.app"
)

for APP_DIR in "${APP_DIRS[@]}"; do
  if [[ -d "$APP_DIR" ]]; then
    open -na "$APP_DIR"
    exit 0
  fi
done

echo "WorkTimer.app was not found in ~/Applications or /Applications." >&2
echo "Install it first or move the app into an Applications folder." >&2
exit 1
