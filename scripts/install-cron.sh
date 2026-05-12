#!/usr/bin/env bash
# install-cron.sh — register night-shift-runner.sh as a user cron job that
# fires at 00:00 every day and is hard-killed at 06:00.
#
# Idempotent: re-running replaces any existing night-shift entry; other crontab
# lines are preserved.
#
# Customization:
#   NIGHT_SHIFT_START_HOUR   default 0  (cron minute=0, this hour)
#   NIGHT_SHIFT_WINDOW_HOURS default 6  (passed to runner; also used for timeout)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_DIR/scripts/night-shift-runner.sh"
TARGETS="$REPO_DIR/scripts/targets.conf"
MARKER="# >>> gs-claude-config night-shift <<<"
MARKER_END="# <<< gs-claude-config night-shift >>>"

start_hour="${NIGHT_SHIFT_START_HOUR:-0}"
window_hours="${NIGHT_SHIFT_WINDOW_HOURS:-6}"

if [[ ! -x "$RUNNER" ]]; then
    echo "FATAL: $RUNNER not found or not executable" >&2
    exit 1
fi

if [[ ! -f "$TARGETS" ]]; then
    echo "WARN: $TARGETS does not exist yet."
    echo "      The cron job will be installed but will exit immediately each night"
    echo "      until you create it:  cp $(basename "$TARGETS").example $(basename "$TARGETS")"
fi

# Determine PATH that cron should use. /usr/bin:/bin is the minimum; we add
# $HOME/.local/bin (where npm-global claude lives) and any nvm shim if found.
cron_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
if command -v nvm >/dev/null 2>&1 || [[ -d "$HOME/.nvm" ]]; then
    # crude — if user uses nvm, prepend the default node bin
    nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -d "$nvm_dir/versions/node" ]]; then
        latest_node="$(ls -1 "$nvm_dir/versions/node" | sort -V | tail -n1)"
        [[ -n "$latest_node" ]] && cron_path="$nvm_dir/versions/node/$latest_node/bin:$cron_path"
    fi
fi

# Build the crontab block we want to install.
new_block=$(cat <<EOF
$MARKER
# Runs /safe-yolo across every repo in $TARGETS during the
# unattended window. Hard-killed after ${window_hours}h.
# Disable: scripts/uninstall-cron.sh   |   Edit targets: \$EDITOR $TARGETS
PATH=$cron_path
SHELL=/bin/bash
0 $start_hour * * * NIGHT_SHIFT_WINDOW_HOURS=$window_hours timeout --signal=TERM --kill-after=120s ${window_hours}h $RUNNER
$MARKER_END
EOF
)

# Splice the new block into the current crontab (replacing any prior block).
existing="$(crontab -l 2>/dev/null || true)"
filtered="$(printf '%s\n' "$existing" | awk -v m="$MARKER" -v me="$MARKER_END" '
    BEGIN { skipping = 0 }
    $0 == m   { skipping = 1; next }
    $0 == me  { skipping = 0; next }
    !skipping { print }
')"

new_crontab="$(printf '%s\n%s\n' "$filtered" "$new_block")"

echo "==> Installing crontab entry:"
echo
printf '%s\n' "$new_block" | sed 's/^/    /'
echo

printf '%s\n' "$new_crontab" | crontab -

echo "==> Done. Verify with:  crontab -l"
echo "==> Targets file:        $TARGETS"
echo "==> Per-night log dir:   $HOME/.claude/night-shift-logs/"
echo "==> Uninstall:           $REPO_DIR/scripts/uninstall-cron.sh"
