#!/usr/bin/env bash
# Install gs-claude-config into ~/.claude/ via symlinks.
#
# Idempotent. If ~/.claude/{commands,skills,CLAUDE.md} already exist as
# regular files/dirs (not symlinks), they get moved to ~/.claude/backups/
# with a timestamp suffix before the symlink is created.
#
# settings.json is *not* symlinked. It gets rendered from
# settings.template.json (with __HOME__ → $HOME) only if no settings.json
# is present yet — existing settings are never overwritten.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_DIR="$CLAUDE_DIR/backups/install-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CLAUDE_DIR"

# Some skills are relative symlinks pointing to a sibling repo at
# $HOME/quant-research-skill. Clone it on a fresh machine so the symlinks
# resolve. Edit QRS_REMOTE if you fork it.
QRS_REMOTE="https://github.com/gsinvest017-ai/quant-research-skill.git"
QRS_DIR="$HOME/quant-research-skill"
if [[ ! -d "$QRS_DIR" ]]; then
    echo "==> Cloning sibling repo quant-research-skill (skills/ symlinks depend on it)"
    git clone "$QRS_REMOTE" "$QRS_DIR"
fi

backup_if_exists() {
    local target="$1"
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -e "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/"
        echo "  backed up existing $(basename "$target") → $BACKUP_DIR/"
    fi
}

link() {
    local src="$1" dst="$2"
    backup_if_exists "$dst"
    ln -s "$src" "$dst"
    echo "  linked $(basename "$dst") → $src"
}

echo "==> Linking commands/, skills/, CLAUDE.md into $CLAUDE_DIR"
link "$REPO_DIR/commands"  "$CLAUDE_DIR/commands"
link "$REPO_DIR/skills"    "$CLAUDE_DIR/skills"
link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

echo "==> settings.json"
if [[ -e "$CLAUDE_DIR/settings.json" ]]; then
    echo "  exists already — left untouched. Diff against settings.template.json manually if you want to merge new keys."
else
    sed "s|__HOME__|$HOME|g" "$REPO_DIR/settings.template.json" > "$CLAUDE_DIR/settings.json"
    echo "  rendered settings.template.json → $CLAUDE_DIR/settings.json"
fi

echo
echo "Done. Verify with:  ls -la ~/.claude/ | grep -E 'commands|skills|CLAUDE'"
echo
echo "Optional — enable the 00:00–06:00 unattended /safe-yolo cron job:"
echo "  cp $REPO_DIR/scripts/targets.conf.example $REPO_DIR/scripts/targets.conf"
echo "  \$EDITOR $REPO_DIR/scripts/targets.conf      # one repo path per line"
echo "  $REPO_DIR/scripts/install-cron.sh"
echo "See README.md → 'Night Shift' for details, env vars, and disable instructions."
