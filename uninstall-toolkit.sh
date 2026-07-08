#!/usr/bin/env bash
# gs-claude-toolkit — uninstaller (macOS / Linux / WSL).
# Removes the commands/skills/agents this toolkit installed into ~/.claude/,
# the autopilot.mjs hook, and the autopilot entries in settings.json. It only
# removes items whose names match this repo's own — your other ~/.claude
# content and your backups/ are left untouched.
#
#   ./uninstall-toolkit.sh [--dir <checkout>] [--keep-hooks]

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
REPO_DIR=""
KEEP_HOOKS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) REPO_DIR="$2"; shift 2 ;;
        --keep-hooks) KEEP_HOOKS=1; shift ;;
        -h|--help) echo "usage: uninstall-toolkit.sh [--dir <checkout>] [--keep-hooks]"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

is_checkout() { [[ -d "$1/skills" && -f "$1/.claude-plugin/plugin.json" ]]; }
if [[ -z "$REPO_DIR" ]]; then
    self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && -f "$self" ]]; then
        cand="$(cd "$(dirname "$self")" && pwd)"
        is_checkout "$cand" && REPO_DIR="$cand"
    fi
fi
[[ -n "$REPO_DIR" ]] && is_checkout "$REPO_DIR" || { echo "error: run from a checkout or pass --dir <checkout>" >&2; exit 1; }

for group in commands skills agents; do
    [[ -d "$REPO_DIR/$group" ]] || continue
    n=0
    for item in "$REPO_DIR/$group"/*; do
        [[ -e "$item" ]] || continue
        dst="$CLAUDE_DIR/$group/$(basename "$item")"
        if [[ -e "$dst" || -L "$dst" ]]; then rm -rf "$dst"; n=$((n + 1)); fi
    done
    echo "  removed $n item(s) from $group"
done

if [[ "$KEEP_HOOKS" -eq 0 ]]; then
    rm -f "$CLAUDE_DIR/hooks/autopilot.mjs"
    if [[ -e "$CLAUDE_DIR/settings.json" ]] && command -v node >/dev/null 2>&1; then
        node "$REPO_DIR/scripts/merge-settings.mjs" "$CLAUDE_DIR/settings.json" --remove
    fi
fi

echo
echo "Done. Backups (if any) remain under $CLAUDE_DIR/backups/ — restore by hand if needed."
