#!/bin/zsh
set -euo pipefail

open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent'

cat <<'EOF'
Opened:
- Accessibility
- Input Monitoring

Enable WorkTimer in both panes, then relaunch if macOS does not resume capture automatically:
open -na ~/Applications/WorkTimer.app
EOF
