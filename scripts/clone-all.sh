#!/usr/bin/env bash
# clone-all.sh — batch-clone the repos listed in scripts/repos.txt
#
# Designed for the "fresh machine" step after `chezmoi apply` finishes:
# chezmoi handles ~/.claude config, this script pulls down the actual
# project repos that live alongside it.
#
# Behavior
#   - One repo per line in scripts/repos.txt
#       <git-url>                  → clones to $HOME/<basename>
#       <git-url>  <dest-path>     → clones to <dest-path> (~ expanded)
#   - Lines starting with # and blank lines are ignored.
#   - Idempotent: skips any dest that already exists.
#   - Continues on per-repo failure; prints a summary at the end.
#   - DRY_RUN=1 prints the resolved actions without cloning.
#
# Usage
#   cp scripts/repos.txt.example scripts/repos.txt
#   $EDITOR scripts/repos.txt
#   scripts/clone-all.sh
#   # or:
#   DRY_RUN=1 scripts/clone-all.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="${SCRIPT_DIR}/repos.txt"

if [[ ! -f "$REPOS_FILE" ]]; then
  cat >&2 <<EOF
clone-all.sh: no repo list found at $REPOS_FILE

Bootstrap a list with:
  cp "$SCRIPT_DIR/repos.txt.example" "$REPOS_FILE"
  \$EDITOR "$REPOS_FILE"
EOF
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "clone-all.sh: git is not installed. Install it first (apt install git / brew install git)." >&2
  exit 1
fi

cloned=()
skipped=()
failed=()

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line%%#*}"
  line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue

  url="$(echo "$line" | awk '{print $1}')"
  dest="$(echo "$line" | awk '{print $2}')"

  if [[ -z "$dest" ]]; then
    base="$(basename "$url")"
    base="${base%.git}"
    dest="$HOME/$base"
  else
    dest="${dest/#\~/$HOME}"
  fi

  if [[ -e "$dest" ]]; then
    echo "[skip] $dest already exists"
    skipped+=("$dest")
    continue
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] git clone $url $dest"
    cloned+=("$dest")
    continue
  fi

  echo "[clone] $url -> $dest"
  parent="$(dirname "$dest")"
  mkdir -p "$parent"
  if git clone "$url" "$dest"; then
    cloned+=("$dest")
  else
    echo "  ! failed: $url" >&2
    failed+=("$url")
  fi
done < "$REPOS_FILE"

echo
echo "─── clone-all.sh summary ───"
echo "  cloned : ${#cloned[@]}"
echo "  skipped: ${#skipped[@]}"
echo "  failed : ${#failed[@]}"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo
  echo "Failed:"
  for f in "${failed[@]}"; do echo "  - $f"; done
  exit 1
fi
