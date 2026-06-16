#!/usr/bin/env bash
# UserPromptSubmit hook for the /autopilot skill (Linux / WSL / macOS).
#
# POSIX-shell counterpart of autopilot-arm.ps1. Stamps the CORRECT session_id
# (from stdin) into the control flag — the model cannot read its own session
# id, so the skill must not create the flag itself. Requires `jq`.
#
#   /autopilot on <task>  -> create flag bound to THIS session, clear done
#   /autopilot off        -> delete flag (+ done)
#   /autopilot status     -> no state change
#
# Always exits 0 — never block prompt submission.

set -uo pipefail

AUTOPILOT_DIR="$HOME/.claude/.autopilot"
STATE_PATH="$AUTOPILOT_DIR/state.json"
DONE_PATH="$AUTOPILOT_DIR/done"

stdin="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

prompt="$(printf '%s' "$stdin" | jq -r '.prompt // ""')"
session_id="$(printf '%s' "$stdin" | jq -r '.session_id // ""')"

if [[ "$prompt" =~ ^[[:space:]]*/autopilot[[:space:]]+on([[:space:]]+(.*))?$ ]]; then
    task="${BASH_REMATCH[2]}"
    mkdir -p "$AUTOPILOT_DIR"
    rm -f "$DONE_PATH"
    jq -nc --arg s "$session_id" --arg t "$task" \
        '{session_id:$s, iterations:0, max_iterations:50, task:$t}' > "$STATE_PATH"

    ctx="autopilot 已武裝（session 已綁定，續跑上限 50）。立即開始執行任務，全程不要停、不要反問方向、不要再自行建立 state.json。完成且驗證通過後執行 touch \"$DONE_PATH\" 再結束。"
    jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'
    exit 0
fi

if [[ "$prompt" =~ ^[[:space:]]*/autopilot[[:space:]]+off\b ]]; then
    rm -f "$STATE_PATH" "$DONE_PATH"
    exit 0
fi

exit 0
