#!/usr/bin/env bash
# uninstall-cron.sh — remove the night-shift crontab block (idempotent).

set -euo pipefail

MARKER="# >>> gs-claude-config night-shift <<<"
MARKER_END="# <<< gs-claude-config night-shift >>>"

existing="$(crontab -l 2>/dev/null || true)"
if [[ -z "$existing" ]]; then
    echo "No user crontab present; nothing to do."
    exit 0
fi

if ! printf '%s\n' "$existing" | grep -qF "$MARKER"; then
    echo "No night-shift block found in crontab; nothing to do."
    exit 0
fi

filtered="$(printf '%s\n' "$existing" | awk -v m="$MARKER" -v me="$MARKER_END" '
    BEGIN { skipping = 0 }
    $0 == m   { skipping = 1; next }
    $0 == me  { skipping = 0; next }
    !skipping { print }
')"

printf '%s\n' "$filtered" | crontab -
echo "Removed night-shift cron block. Verify with:  crontab -l"
