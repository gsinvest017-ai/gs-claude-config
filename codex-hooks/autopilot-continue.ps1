# Stop hook for the /autopilot skill (Codex CLI / Windows / pwsh).
#
# Blocks a Codex turn end while ~/.codex/.autopilot/state.json exists for the
# current session. The model clears the loop by creating the done sentinel.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$stdin = [Console]::In.ReadToEnd()
$payload = $null
if (-not [string]::IsNullOrWhiteSpace($stdin)) {
    $payload = $stdin | ConvertFrom-Json
}

if ($payload -and $payload.stop_hook_active -eq $true) { exit 0 }

$sessionId = if ($payload) { [string]$payload.session_id } else { "" }

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$autopilotDir = Join-Path $codexHome '.autopilot'
$statePath    = Join-Path $autopilotDir 'state.json'
$donePath     = Join-Path $autopilotDir 'done'

if (-not (Test-Path $statePath)) { exit 0 }

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if (-not $state) { exit 0 }

if ([string]$state.session_id -ne $sessionId) { exit 0 }

if (Test-Path $donePath) {
    Remove-Item -LiteralPath $donePath  -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    exit 0
}

$iterations = [int]$state.iterations
$maxIter    = [int]$state.max_iterations
if ($maxIter -le 0) { $maxIter = 50 }
if ($iterations -ge $maxIter) {
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    [Console]::Error.WriteLine("[autopilot] 已達續跑上限 $maxIter 次，自動停止。如需續跑請重新 /autopilot on。")
    exit 0
}

$state.iterations = $iterations + 1
($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8

$reason = @"
[autopilot 進行中 - 第 $($state.iterations)/$maxIter 次續跑]
尚未偵測到完成訊號，繼續推進任務的下一步，不要停下來。
規則：
- 遇到分歧自行採用最合理的預設值繼續，把假設記進進度檔；不要反問方向。
- 禁止用「要 A 還是 B？」結束回合。
- 沿用 /safe-yolo 紀律：milestone 式推進、每完成一個就 commit（繁中主體）、更新 docs/progress-*.md。
- 只有在同一錯誤連續 3 次仍無解、或操作不可逆且影響超出 working directory 時才停下回報。
- 當任務真的完成且測試/驗證通過時，執行：New-Item -ItemType File "$donePath" -Force，然後才結束回合。
"@

$out = @{ decision = "block"; reason = $reason } | ConvertTo-Json -Compress
[Console]::Out.Write($out)
exit 0
