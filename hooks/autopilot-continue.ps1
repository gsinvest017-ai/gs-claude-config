# Stop hook for the /autopilot skill (Windows / pwsh).
#
# Forces a Claude Code session to keep working instead of ending its turn,
# until either a completion sentinel appears or an iteration ceiling is hit.
# This is the "hard" enforcement layer that /safe-yolo's prompt rules cannot
# guarantee: even if the model decides it is done, this hook blocks the stop
# and feeds back the next-step instruction.
#
# Mechanism (see https://code.claude.com/docs/en/hooks.md, Stop hook):
#   Emitting {"decision":"block","reason":"..."} on stdout prevents the turn
#   from ending; `reason` is fed back to the model as its next instruction.
#
# Control state lives under ~/.claude/.autopilot/ :
#   state.json  — { session_id, iterations, max_iterations, started, task }
#   done        — completion sentinel; the model touches it when truly finished
#
# Safety valves (defense in depth):
#   1. stop_hook_active == true        -> exit 0 (respect Claude Code's built-in
#                                         consecutive-block cap; never fight it)
#   2. no state.json                   -> exit 0 (autopilot OFF is the default)
#   3. state.session_id != this session -> exit 0 (a stale flag from another
#                                         session can never hijack this one)
#   4. done sentinel present           -> clear state, exit 0
#   5. iterations >= max_iterations    -> clear state, exit 0 (forced stop)
#   otherwise                          -> iterations++, emit block + reason
#
# Always exits 0. A crash here must never wedge the session, so every failure
# path falls through to a normal stop.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- read + parse stdin payload -------------------------------------------
$stdin = [Console]::In.ReadToEnd()
$payload = $null
if (-not [string]::IsNullOrWhiteSpace($stdin)) {
    $payload = $stdin | ConvertFrom-Json
}

# Valve 1: already looping under Claude Code's own machinery — stand down.
if ($payload -and $payload.stop_hook_active -eq $true) { exit 0 }

$sessionId = if ($payload) { [string]$payload.session_id } else { "" }

# --- locate control state --------------------------------------------------
$autopilotDir = Join-Path $env:USERPROFILE '.claude\.autopilot'
$statePath    = Join-Path $autopilotDir 'state.json'
$donePath     = Join-Path $autopilotDir 'done'

# Valve 2: no flag file -> autopilot is off -> allow normal stop.
if (-not (Test-Path $statePath)) { exit 0 }

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if (-not $state) { exit 0 }

# First-touch session binding: the skill writes session_id:"" because it
# cannot read the session id itself; the hook locks it in on first sight.
if ([string]::IsNullOrEmpty([string]$state.session_id)) {
    $state.session_id = $sessionId
    ($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8
}

# Valve 3: flag belongs to a different session -> do not block this one.
if ([string]$state.session_id -ne $sessionId) { exit 0 }

# Valve 4: completion sentinel -> finish and clean up.
if (Test-Path $donePath) {
    Remove-Item -LiteralPath $donePath  -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    exit 0
}

# Valve 5: iteration ceiling -> forced stop, clear state.
$iterations = [int]$state.iterations
$maxIter    = [int]$state.max_iterations
if ($maxIter -le 0) { $maxIter = 50 }
if ($iterations -ge $maxIter) {
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    # stderr is surfaced to the user as a note; not fed back as an instruction.
    [Console]::Error.WriteLine("[autopilot] 已達續跑上限 $maxIter 次，自動停止。如需續跑請重新 /autopilot on。")
    exit 0
}

# --- continue: bump counter, block the stop, instruct next step ------------
$state.iterations = $iterations + 1
($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8

$reason = @"
[autopilot 進行中 — 第 $($state.iterations)/$maxIter 次續跑]
尚未偵測到完成訊號，繼續推進任務的下一步，不要停下來。
規則：
- 遇到分歧自行採用最合理的預設值繼續，把假設記進進度檔；不要反問方向。
- 禁止使用 AskUserQuestion，禁止用「要 A 還是 B？」結束回合。
- 沿用 /safe-yolo 紀律：milestone 式推進、每完成一個就 commit（繁中主體）、更新 docs/progress-*.md。
- 只有在同一錯誤連續 3 次仍無解、或操作不可逆且影響超出 working directory 時才停下回報。
- 當任務「真的完成且測試/驗證通過」時，執行：  New-Item -ItemType File "$donePath" -Force   然後才結束回合。
"@

$out = @{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
[Console]::Out.Write($out)
exit 0
