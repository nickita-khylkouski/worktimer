#!/bin/zsh
set -euo pipefail

APP_DIR="$HOME/Applications/WorkTimer.app"

if [[ ! -d "$APP_DIR" ]]; then
  echo "WorkTimer.app is not installed yet. Run ./scripts/install-app.sh first." >&2
  exit 1
fi

open -na "$APP_DIR"
