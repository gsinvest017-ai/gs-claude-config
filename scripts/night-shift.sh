#!/usr/bin/env bash
# night-shift.sh — run /safe-yolo against one repo, unattended.
#
# Usage:
#   night-shift.sh <repo-path> [prompt-source-file]
#
# - Refuses to run if the repo isn't a clean git checkout
# - Creates a fresh branch claude/nightly-YYYY-MM-DD (suffixed with -HHMMSS if it exists)
# - Builds a /safe-yolo prompt from prompt-source-file (or auto-discovered docs)
# - Pipes that prompt to `claude -p --dangerously-skip-permissions`
# - Writes everything to ~/.claude/night-shift-logs/<repo-basename>-YYYY-MM-DD-HHMMSS.log
#
# Env vars:
#   DRY_RUN=1                       print the prompt + the claude command, do NOT call claude
#   CLAUDE_BIN=/path/to/claude      override claude binary discovery
#   NIGHT_SHIFT_PER_REPO_TIMEOUT=…  passed to `timeout` for the claude call (default 2h)
#   NIGHT_SHIFT_MODEL=opus|sonnet   override --model

set -euo pipefail

REPO="${1:?usage: night-shift.sh <repo-path> [prompt-source-file]}"
PROMPT_FILE_OVERRIDE="${2:-}"

LOG_DIR="$HOME/.claude/night-shift-logs"
mkdir -p "$LOG_DIR"

repo_name="$(basename "$REPO")"
stamp_date="$(date +%Y-%m-%d)"
stamp_full="$(date +%Y-%m-%d-%H%M%S)"
LOG_FILE="$LOG_DIR/${repo_name}-${stamp_full}.log"

# All further output (stdout + stderr) tee'd into the log.
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf '[night-shift %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "FATAL: $*"; exit 1; }

log "repo=$REPO  log=$LOG_FILE  dry_run=${DRY_RUN:-0}"

[[ -d "$REPO" ]] || fail "repo path does not exist: $REPO"
cd "$REPO"

[[ -d .git ]] || fail "not a git repo: $REPO"

# Refuse to act on a dirty tree — we will not stash someone's work.
if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "working tree dirty; refusing to run. commit/stash first or remove from targets.conf for tonight."
fi

# Untracked files we tolerate (they don't get carried into the new branch).
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    fail "tracked changes present; refusing to run."
fi

# Branch name: claude/nightly-YYYY-MM-DD, suffixed with -HHMMSS if today's already exists.
branch="claude/nightly-${stamp_date}"
if git rev-parse --verify --quiet "$branch" >/dev/null; then
    branch="claude/nightly-${stamp_full}"
fi
log "creating branch $branch from $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
git checkout -b "$branch"

# ---------------------------------------------------------------------------
# Build prompt source: explicit file > auto-discovered docs
# ---------------------------------------------------------------------------
prompt_sources=()
if [[ -n "$PROMPT_FILE_OVERRIDE" ]]; then
    if [[ -f "$PROMPT_FILE_OVERRIDE" ]]; then
        prompt_sources+=("$PROMPT_FILE_OVERRIDE")
    else
        log "WARN: prompt-source-file '$PROMPT_FILE_OVERRIDE' not found; falling back to auto-discovery"
    fi
fi

if [[ ${#prompt_sources[@]} -eq 0 ]]; then
    # Auto-discover. Stop at 8 files to keep the prompt manageable.
    while IFS= read -r f; do
        prompt_sources+=("$f")
        [[ ${#prompt_sources[@]} -ge 8 ]] && break
    done < <(
        {
            ls -1 TODO.md 2>/dev/null || true
            ls -1 docs/TODO.md docs/todo.md 2>/dev/null || true
            ls -1 docs/refactor*.md docs/REFACTOR*.md 2>/dev/null || true
            ls -1 docs/issue*.md docs/ISSUE*.md 2>/dev/null || true
            ls -1 docs/progress-*.md 2>/dev/null || true
        } | awk '!seen[$0]++'
    )
fi

if [[ ${#prompt_sources[@]} -eq 0 ]]; then
    log "no prompt sources found; trying gh issue list as last resort"
    issues_dump=""
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        issues_dump="$(gh issue list --limit 20 --state open 2>/dev/null || true)"
    fi
    if [[ -z "$issues_dump" ]]; then
        log "no tasks found anywhere; aborting night shift for this repo"
        # Drop the empty branch so we don't leave litter.
        git checkout - >/dev/null 2>&1 || true
        git branch -D "$branch" >/dev/null 2>&1 || true
        exit 0
    fi
fi

# Assemble the prompt (we feed it via stdin to avoid shell quoting issues).
prompt_tmp="$(mktemp -t night-shift-prompt.XXXXXX)"
trap 'rm -f "$prompt_tmp"' EXIT

{
    cat <<EOF
/safe-yolo 你正在執行夜間無人值守任務。

【執行環境】
- 目前 working directory：$REPO
- 目前 git 分支：$branch（cron 已為你建好）
- 時間預算：cron 會在 06:00 強制終止；請盡量在這之前推進到能穩定 commit 的狀態
- 規範：只在當前分支工作。不要 git push、不要開 PR、不要送訊息到外部服務、不要修改 working directory 以外的檔案

【你的任務】
請閱讀下方「任務來源」段落，挑出最高優先且最具體可執行的 1 個 milestone，立即按 /safe-yolo skill 的規則執行：
- 每完成一個 milestone 立刻 commit（commit message 以 \`Mn:\` 開頭）
- 進度寫入 docs/progress-<task-slug>.md（若該檔已存在則 append）
- 若 3 次嘗試仍無法解決同一錯誤，commit 目前可工作狀態並結束

如果讀完所有來源仍找不到任何具體可執行的任務，請直接結束並在 log 留下「no actionable task found」訊息。

────────── 任務來源 ──────────
EOF

    if [[ ${#prompt_sources[@]} -gt 0 ]]; then
        for f in "${prompt_sources[@]}"; do
            printf '\n### %s\n\n' "$f"
            # Cap each file at 400 lines so total prompt stays bounded.
            head -n 400 "$f"
        done
    fi

    if [[ -n "${issues_dump:-}" ]]; then
        printf '\n### Open GitHub issues (gh issue list)\n\n```\n%s\n```\n' "$issues_dump"
    fi

    printf '\n────────── 任務來源結束 ──────────\n'
} > "$prompt_tmp"

log "prompt assembled ($(wc -l <"$prompt_tmp") lines, $(wc -c <"$prompt_tmp") bytes), sources=${#prompt_sources[@]}"
log "---- PROMPT HEAD ----"
head -n 30 "$prompt_tmp"
log "---- /PROMPT HEAD ----"

# ---------------------------------------------------------------------------
# Invoke claude
# ---------------------------------------------------------------------------
CLAUDE_BIN_RESOLVED="${CLAUDE_BIN:-$(command -v claude || true)}"
[[ -x "$CLAUDE_BIN_RESOLVED" ]] || fail "cannot find claude binary (looked in PATH and \$CLAUDE_BIN)"

per_repo_timeout="${NIGHT_SHIFT_PER_REPO_TIMEOUT:-2h}"
model="${NIGHT_SHIFT_MODEL:-opus}"

claude_cmd=(
    timeout --signal=TERM --kill-after=30s "$per_repo_timeout"
    "$CLAUDE_BIN_RESOLVED"
    -p
    --dangerously-skip-permissions
    --permission-mode bypassPermissions
    --add-dir "$REPO"
    --model "$model"
    --output-format text
)

log "claude command: ${claude_cmd[*]}"

if [[ "${DRY_RUN:-0}" = "1" ]]; then
    log "DRY_RUN=1 — skipping claude invocation, leaving branch $branch in place"
    exit 0
fi

set +e
"${claude_cmd[@]}" < "$prompt_tmp"
claude_rc=$?
set -e
log "claude exit code: $claude_rc"

# Best-effort: if the branch has no new commits, drop it so we don't pollute the repo.
new_commits="$(git rev-list --count "${branch}" ^"$(git merge-base "$branch" HEAD@{1} 2>/dev/null || echo HEAD)" 2>/dev/null || echo 0)"
if [[ "$new_commits" = "0" ]]; then
    log "no new commits on $branch; switching back and deleting empty branch"
    git checkout - >/dev/null 2>&1 || true
    git branch -D "$branch" >/dev/null 2>&1 || true
fi

log "done. log file: $LOG_FILE"
exit "$claude_rc"
