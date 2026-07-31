# UserPromptSubmit hook for the /autopilot skill (Windows / pwsh).
#
# Matched on prompts starting with `/autopilot` (settings.json matcher).
# Its whole job is to stamp the CORRECT session_id into the control flag,
# which the skill itself cannot do — the model has no way to read its own
# session id, whereas this hook receives it on stdin. This removes the
# cross-session race that an "empty session_id, bind on first Stop" scheme
# suffered (any other live session could grab the flag first).
#
#   /autopilot on <task>  -> create ~/.claude/.autopilot/state.json bound to
#                            THIS session; clear any stale `done` sentinel.
#   /autopilot off        -> delete the flag (+ done).
#   /autopilot status     -> no state change (the skill prints it).
#
# Emits a short additionalContext on `on` so the model knows it is armed and
# should start executing immediately (and must NOT re-create the flag).
# Always exits 0 — a failure here must never block prompt submission.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$stdin = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($stdin)) { exit 0 }
$payload = $stdin | ConvertFrom-Json
if (-not $payload) { exit 0 }

$prompt    = [string]$payload.prompt
$sessionId = [string]$payload.session_id

$autopilotDir = Join-Path $env:USERPROFILE '.claude\.autopilot'
$statePath    = Join-Path $autopilotDir 'state.json'
$donePath     = Join-Path $autopilotDir 'done'

# (?s) makes `.` match newlines so a multi-line task description still arms.
# Without it the whole match failed on a multi-line prompt and this hook exited
# 0 without creating the flag — the user saw no error and believed autopilot was
# on when it was not.
if ($prompt -match '(?s)^\s*/autopilot\s+on\b\s*(.*)$') {
    $task = $Matches[1].Trim()
    New-Item -ItemType Directory -Force -Path $autopilotDir | Out-Null
    Remove-Item -LiteralPath $donePath -Force -ErrorAction SilentlyContinue
    $state = [ordered]@{
        session_id     = $sessionId
        iterations     = 0
        max_iterations = 50
        started        = (Get-Date -Format o)
        task           = $task
    }
    # BOM-less on every engine: Set-Content -Encoding UTF8 emits a BOM under
    # Windows PowerShell 5.1, which the .sh / .mjs readers cannot parse.
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Compress), $utf8NoBom)

    $ctx = "autopilot 已武裝（session 已綁定，續跑上限 50）。立即開始執行任務，全程不要停、不要反問方向、不要再自行建立 state.json。完成且驗證通過後執行 New-Item -ItemType File `"$donePath`" -Force 再結束。"
    $out = @{ hookSpecificOutput = @{ hookEventName = "UserPromptSubmit"; additionalContext = $ctx } } | ConvertTo-Json -Compress
    [Console]::Out.Write($out)
    exit 0
}

if ($prompt -match '^\s*/autopilot\s+off\b') {
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $donePath  -Force -ErrorAction SilentlyContinue
    exit 0
}

# /autopilot status or bare /autopilot — no state change.
exit 0
