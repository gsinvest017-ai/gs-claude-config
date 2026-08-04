# UserPromptSubmit hook for the /autopilot skill (Codex CLI / Windows / pwsh).
#
# This is the Codex counterpart of hooks/autopilot-arm.ps1. State is stored
# under ~/.codex/.autopilot so Claude Code and Codex sessions cannot affect one
# another.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$stdin = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($stdin)) { exit 0 }
$payload = $stdin | ConvertFrom-Json
if (-not $payload) { exit 0 }

$prompt    = [string]$payload.prompt
$sessionId = [string]$payload.session_id

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$autopilotDir = Join-Path $codexHome '.autopilot'
$statePath    = Join-Path $autopilotDir 'state.json'
$donePath     = Join-Path $autopilotDir 'done'

if ($prompt -match '^\s*/autopilot\s+on\b\s*(.*)$') {
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
    ($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8

    $ctx = "autopilot 已武裝（Codex session 已綁定，續跑上限 50）。立即開始執行任務，全程不要停、不要反問方向、不要再自行建立 state.json。完成且驗證通過後執行 New-Item -ItemType File `"$donePath`" -Force 再結束。"
    $out = @{ hookSpecificOutput = @{ hookEventName = "UserPromptSubmit"; additionalContext = $ctx } } | ConvertTo-Json -Compress
    [Console]::Out.Write($out)
    exit 0
}

if ($prompt -match '^\s*/autopilot\s+off\b') {
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $donePath  -Force -ErrorAction SilentlyContinue
    exit 0
}

exit 0
