#!/bin/zsh
set -euo pipefail

open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'

cat <<'EOF'
Opened:
- Accessibility
- Input Monitoring

Enable WorkTimer in both panes. WorkTimer retries automatically, but if stats still do not start after a few seconds, relaunch:
./scripts/open-app.sh
EOF
