#!/usr/bin/env bash
# ============================================================================
# gs-claude-toolkit — consumer installer (macOS / Linux / WSL)
# ============================================================================
# One-click install of the skills / commands / agents / autopilot hooks into
# ~/.claude/ for *anyone* (not the author's cross-machine sync — that's the
# separate install.sh, which symlinks the author's personal CLAUDE.md etc.).
#
# Remote one-liner:
#   curl -fsSL https://raw.githubusercontent.com/GSINVEST/gs-claude-config/main/install-toolkit.sh | bash
#
# From a local clone:
#   ./install-toolkit.sh [flags]
#
# Defaults to COPY mode (no symlinks, no Windows Dev Mode needed). Existing
# same-named items in ~/.claude/{commands,skills,agents} are backed up first;
# your settings.json is merged in-place (never clobbered) and your own
# CLAUDE.md is never touched.
#
# Flags:
#   --link            symlink instead of copy (for contributors editing in place)
#   --no-hooks        skip the autopilot hooks + settings.json merge
#   --dir <path>      install from this local checkout instead of cloning
#   --repo-url <url>  override the clone URL (default: the GitHub repo below)
#   --branch <name>   branch to clone (default: main)
#   -h | --help       show this help
# ============================================================================

set -euo pipefail

REPO_URL="${GS_REPO_URL:-https://github.com/GSINVEST/gs-claude-config.git}"
BRANCH="${GS_BRANCH:-main}"
CLAUDE_DIR="$HOME/.claude"
MODE="copy"
DO_HOOKS=1
REPO_DIR=""
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CLAUDE_DIR/backups/toolkit-$TS"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --link) MODE="link"; shift ;;
        --no-hooks) DO_HOOKS=0; shift ;;
        --dir) REPO_DIR="$2"; shift 2 ;;
        --repo-url) REPO_URL="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        -h|--help) sed -n '2,40p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
    esac
done

# --- locate the repo: local checkout or clone -------------------------------
is_checkout() { [[ -d "$1/skills" && -f "$1/.claude-plugin/plugin.json" ]]; }

if [[ -z "$REPO_DIR" ]]; then
    self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && -f "$self" ]]; then
        cand="$(cd "$(dirname "$self")" && pwd)"
        is_checkout "$cand" && REPO_DIR="$cand"
    fi
fi

if [[ -z "$REPO_DIR" ]]; then
    CACHE="${GS_CACHE:-$HOME/.cache/gs-claude-toolkit}"
    if is_checkout "$CACHE"; then
        echo "==> Updating cached checkout at $CACHE"
        git -C "$CACHE" fetch --depth 1 origin "$BRANCH" -q && git -C "$CACHE" reset --hard "origin/$BRANCH" -q || true
    else
        echo "==> Cloning $REPO_URL ($BRANCH) -> $CACHE"
        rm -rf "$CACHE"
        mkdir -p "$(dirname "$CACHE")"
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$CACHE" -q
    fi
    REPO_DIR="$CACHE"
fi

is_checkout "$REPO_DIR" || { echo "error: $REPO_DIR is not a gs-claude-config checkout" >&2; exit 1; }
if ! command -v node >/dev/null 2>&1; then
    echo "error: 'node' not found. Claude Code bundles Node; ensure it's on PATH (the autopilot hook needs it)." >&2
    exit 1
fi

echo "==> Installing from $REPO_DIR  (mode: $MODE)"
mkdir -p "$CLAUDE_DIR"

# --- place one item, backing up any pre-existing target --------------------
place() {
    local src="$1" dstdir="$2"
    local name dst
    name="$(basename "$src")"
    dst="$dstdir/$name"
    mkdir -p "$dstdir"
    if [[ -e "$dst" || -L "$dst" ]]; then
        mkdir -p "$BACKUP_DIR/$(basename "$dstdir")"
        mv "$dst" "$BACKUP_DIR/$(basename "$dstdir")/"
    fi
    if [[ "$MODE" == "link" ]]; then
        ln -s "$src" "$dst"
    else
        cp -a "$src" "$dst"
    fi
}

install_group() {
    local group="$1"           # commands | skills | agents
    [[ -d "$REPO_DIR/$group" ]] || return 0
    local n=0
    for item in "$REPO_DIR/$group"/*; do
        [[ -e "$item" ]] || continue
        place "$item" "$CLAUDE_DIR/$group"
        n=$((n + 1))
    done
    echo "  $group: $n item(s)"
}

install_group commands
install_group skills
install_group agents

# --- hooks + settings -------------------------------------------------------
if [[ "$DO_HOOKS" -eq 1 ]]; then
    echo "==> Autopilot hook + settings.json"
    mkdir -p "$CLAUDE_DIR/hooks"
    cp -f "$REPO_DIR/plugins/gs-autopilot/hooks/autopilot.mjs" "$CLAUDE_DIR/hooks/autopilot.mjs"
    HOOK_CMD="node \"$CLAUDE_DIR/hooks/autopilot.mjs\""
    if [[ -e "$CLAUDE_DIR/settings.json" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/settings.json.bak"
    fi
    node "$REPO_DIR/scripts/merge-settings.mjs" "$CLAUDE_DIR/settings.json" "$HOOK_CMD" 60
else
    echo "==> Skipping hooks (--no-hooks)"
fi

echo
if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backed up pre-existing items -> $BACKUP_DIR"
fi
echo "Done. Restart Claude Code, then verify:"
echo "  ls ~/.claude/skills | head        # your new skills"
echo "  /autopilot status                 # hooks wired"
echo
echo "Uninstall anytime:  $REPO_DIR/uninstall-toolkit.sh"
