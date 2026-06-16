#!/usr/bin/env bash
# Stop hook for the /autopilot skill (Linux / WSL / macOS).
#
# POSIX-shell counterpart of autopilot-continue.ps1. See that file's header
# for the full mechanism and safety-valve rationale. Requires `jq`.
#
# Forces the session to keep working (emits {"decision":"block","reason":...})
# until a completion sentinel appears or the iteration ceiling is hit.
#
# Always exits 0 — a failure here must never wedge the session.

set -uo pipefail

AUTOPILOT_DIR="$HOME/.claude/.autopilot"
STATE_PATH="$AUTOPILOT_DIR/state.json"
DONE_PATH="$AUTOPILOT_DIR/done"

stdin="$(cat)"

# jq missing -> cannot evaluate state safely -> allow normal stop.
command -v jq >/dev/null 2>&1 || exit 0

# Valve 1: already looping under Claude Code's own machinery.
if [[ "$(printf '%s' "$stdin" | jq -r '.stop_hook_active // false')" == "true" ]]; then
    exit 0
fi

session_id="$(printf '%s' "$stdin" | jq -r '.session_id // ""')"

# Valve 2: no flag file -> autopilot off.
[[ -f "$STATE_PATH" ]] || exit 0

state="$(cat "$STATE_PATH" 2>/dev/null)" || exit 0
[[ -n "$state" ]] || exit 0

# First-touch session binding (skill writes session_id:"").
state_sid="$(printf '%s' "$state" | jq -r '.session_id // ""')"
if [[ -z "$state_sid" ]]; then
    state="$(printf '%s' "$state" | jq --arg s "$session_id" '.session_id=$s')"
    printf '%s' "$state" > "$STATE_PATH"
    state_sid="$session_id"
fi

# Valve 3: flag belongs to a different session.
[[ "$state_sid" == "$session_id" ]] || exit 0

# Valve 4: completion sentinel.
if [[ -f "$DONE_PATH" ]]; then
    rm -f "$DONE_PATH" "$STATE_PATH"
    exit 0
fi

# Valve 5: iteration ceiling.
iterations="$(printf '%s' "$state" | jq -r '.iterations // 0')"
max_iter="$(printf '%s' "$state" | jq -r '.max_iterations // 50')"
[[ "$max_iter" -gt 0 ]] 2>/dev/null || max_iter=50
if (( iterations >= max_iter )); then
    rm -f "$STATE_PATH"
    echo "[autopilot] 已達續跑上限 ${max_iter} 次，自動停止。如需續跑請重新 /autopilot on。" >&2
    exit 0
fi

# Continue: bump counter, block the stop, instruct next step.
next=$(( iterations + 1 ))
printf '%s' "$state" | jq --argjson n "$next" '.iterations=$n' > "$STATE_PATH"

reason="[autopilot 進行中 — 第 ${next}/${max_iter} 次續跑]
尚未偵測到完成訊號，繼續推進任務的下一步，不要停下來。
規則：
- 遇到分歧自行採用最合理的預設值繼續，把假設記進進度檔；不要反問方向。
- 禁止使用 AskUserQuestion，禁止用「要 A 還是 B？」結束回合。
- 沿用 /safe-yolo 紀律：milestone 式推進、每完成一個就 commit（繁中主體）、更新 docs/progress-*.md。
- 只有在同一錯誤連續 3 次仍無解、或操作不可逆且影響超出 working directory 時才停下回報。
- 當任務「真的完成且測試/驗證通過」時，執行：  touch \"$DONE_PATH\"   然後才結束回合。"

jq -nc --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
