#!/usr/bin/env bash
# night-shift-runner.sh — cron entry point. Iterates over scripts/targets.conf
# and calls night-shift.sh once per repo, sharing a global 6h budget that
# expires at 06:00 (the unattended window).
#
# Reads:
#   scripts/targets.conf — one repo path per line; lines may end with "|<prompt-file>"
#
# Env vars:
#   NIGHT_SHIFT_WINDOW_HOURS  total budget in hours (default 6)
#   DRY_RUN=1                 forwarded to night-shift.sh
#
# Exit code: 0 if all targets either completed or were skipped cleanly,
# non-zero if any per-repo run errored (other than budget exhaustion).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIGHT_SHIFT_SH="$REPO_DIR/scripts/night-shift.sh"
TARGETS_CONF="$REPO_DIR/scripts/targets.conf"

LOG_DIR="$HOME/.claude/night-shift-logs"
mkdir -p "$LOG_DIR"
RUNNER_LOG="$LOG_DIR/_runner-$(date +%Y-%m-%d-%H%M%S).log"

exec > >(tee -a "$RUNNER_LOG") 2>&1

log() { printf '[runner %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

log "starting; log=$RUNNER_LOG"

if [[ ! -f "$TARGETS_CONF" ]]; then
    log "no targets.conf at $TARGETS_CONF — nothing to do."
    log "(copy targets.conf.example to targets.conf and fill in repo paths)"
    exit 0
fi

[[ -x "$NIGHT_SHIFT_SH" ]] || { log "FATAL: $NIGHT_SHIFT_SH missing or not executable"; exit 1; }

window_hours="${NIGHT_SHIFT_WINDOW_HOURS:-6}"
deadline_epoch=$(( $(date +%s) + window_hours * 3600 ))
log "global window: ${window_hours}h, deadline=$(date -d "@$deadline_epoch" '+%Y-%m-%d %H:%M:%S')"

# Parse targets.conf into two parallel arrays.
declare -a t_paths t_prompts
while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%%#*}"                       # strip comments
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    line="${line%"${line##*[![:space:]]}"}"  # rtrim
    [[ -z "$line" ]] && continue
    if [[ "$line" == *"|"* ]]; then
        t_paths+=("${line%%|*}")
        t_prompts+=("${line#*|}")
    else
        t_paths+=("$line")
        t_prompts+=("")
    fi
done < "$TARGETS_CONF"

total=${#t_paths[@]}
log "loaded $total target(s) from $TARGETS_CONF"
if (( total == 0 )); then
    log "no targets after parsing; exiting clean"
    exit 0
fi

overall_rc=0
processed=0
skipped_budget=0

for i in "${!t_paths[@]}"; do
    path="${t_paths[$i]}"
    prompt="${t_prompts[$i]}"

    now_epoch=$(date +%s)
    remaining=$(( deadline_epoch - now_epoch ))
    if (( remaining < 120 )); then
        skipped_budget=$(( total - i ))
        log "budget exhausted (${remaining}s left). Skipping remaining $skipped_budget repo(s)."
        break
    fi

    # Resolve ~ if present.
    path="${path/#\~/$HOME}"

    log "──── target $((i+1))/$total : $path (budget left: ${remaining}s) ────"

    if [[ ! -d "$path" ]]; then
        log "skip: $path does not exist"
        continue
    fi

    # Cap per-repo budget so a single target can't eat everything.
    per_repo_cap=$(( remaining - 60 ))
    (( per_repo_cap > 7200 )) && per_repo_cap=7200   # hard cap at 2h/target
    (( per_repo_cap < 60 ))   && per_repo_cap=60

    set +e
    NIGHT_SHIFT_PER_REPO_TIMEOUT="${per_repo_cap}s" \
        "$NIGHT_SHIFT_SH" "$path" "$prompt"
    rc=$?
    set -e

    log "target $path → exit=$rc"
    processed=$(( processed + 1 ))
    if (( rc != 0 && rc != 124 )); then
        # 124 = GNU timeout fired; that's expected/normal at budget end
        overall_rc=$rc
    fi
done

log "summary: total=$total processed=$processed skipped_budget=$skipped_budget overall_rc=$overall_rc"
exit "$overall_rc"
