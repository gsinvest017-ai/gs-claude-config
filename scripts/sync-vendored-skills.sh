#!/usr/bin/env bash
# Refresh the vendored copies of the skills that live in the sibling repo
# `quant-research-skill`.
#
# Why this exists: `skills/quant-researcher` and `skills/review-strategy` used
# to be symlinks into ../../quant-research-skill. Symlinks dangle when the repo
# is `git clone`d as a Claude Code plugin, so those two skills are now VENDORED
# (real copies committed here) instead. The sibling repo remains the source of
# truth — edit skills there, then run this script to pull the changes back in
# and commit the refreshed copies.
#
# Usage:  scripts/sync-vendored-skills.sh [path-to-quant-research-skill]
#         (defaults to $HOME/quant-research-skill)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="${1:-$HOME/quant-research-skill}"

VENDORED=(quant-researcher review-strategy)

if [[ ! -d "$SRC_ROOT/skills" ]]; then
    echo "error: sibling repo not found at $SRC_ROOT (no skills/ dir)." >&2
    echo "       clone it first:  git clone https://github.com/gsinvest017-ai/quant-research-skill.git \"$SRC_ROOT\"" >&2
    exit 1
fi

for s in "${VENDORED[@]}"; do
    src="$SRC_ROOT/skills/$s"
    dst="$REPO_DIR/skills/$s"
    if [[ ! -d "$src" ]]; then
        echo "warn: $src missing — skipped" >&2
        continue
    fi
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
    echo "synced skills/$s  <-  $src"
done

echo
echo "Done. Review + commit:  git -C \"$REPO_DIR\" add skills/ && git -C \"$REPO_DIR\" commit"
