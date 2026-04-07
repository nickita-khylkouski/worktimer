#!/bin/zsh
set -euo pipefail

BUNDLE_ID="com.nickita.worktimer"

tccutil reset Accessibility "$BUNDLE_ID"
tccutil reset ListenEvent "$BUNDLE_ID"

cat <<EOF
Reset WorkTimer privacy permissions for:
- Accessibility
- Input Monitoring

Next step:
./scripts/open-permissions.sh
EOF
