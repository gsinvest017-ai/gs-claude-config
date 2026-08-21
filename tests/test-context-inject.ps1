$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$hook = "C:\Users\User\.claude\hooks\context-inject.ps1"

# 用臨時 GS_HARNESS_ROOT 隔離，不動真實的 state/
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ctxhook-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'state') -Force | Out-Null
$file = Join-Path $tmp 'state\context-agent.md'

function Invoke-Hook {
    $old = $env:GS_HARNESS_ROOT
    $env:GS_HARNESS_ROOT = $tmp
    try { $out = '' | pwsh -NoProfile -NonInteractive -File $hook 2>$null }
    finally { $env:GS_HARNESS_ROOT = $old }
    return ($out -join '')
}

$fail = 0
function Check([string]$name, [bool]$ok) {
    if ($ok) { Write-Host "  PASS  $name" }
    else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

Write-Host "=== cache 不存在時：安靜跳過，不可輸出任何東西 ===" -ForegroundColor Cyan
Check "無 cache → 無輸出" ([string]::IsNullOrWhiteSpace((Invoke-Hook)))

Write-Host "`n=== cache 是空檔：同樣安靜跳過（別注入空 context 假裝有東西）===" -ForegroundColor Cyan
Set-Content -LiteralPath $file -Value "" -Encoding UTF8
Check "空 cache → 無輸出" ([string]::IsNullOrWhiteSpace((Invoke-Hook)))

Write-Host "`n=== 正常 cache ===" -ForegroundColor Cyan
Set-Content -LiteralPath $file -Value "## workspace`n- root: X`n`n## learnings（2 條）`n- 某個坑" -Encoding UTF8
$out = Invoke-Hook
$json = $null
try { $json = $out | ConvertFrom-Json } catch {}
Check "輸出是合法 JSON" ($null -ne $json)
Check "hookEventName = SessionStart" ($json.hookSpecificOutput.hookEventName -eq 'SessionStart')
Check "內容含 cache 本文" ($json.hookSpecificOutput.additionalContext -match '某個坑')
Check "內容含後續指令指路" ($json.hookSpecificOutput.additionalContext -match 'harness context --mode agent --json')
Check "新鮮時不加過期警告" (-not ($json.hookSpecificOutput.additionalContext -match '沒更新'))

Write-Host "`n=== 過期 cache：照樣注入，但必須標出天數 ===" -ForegroundColor Cyan
(Get-Item -LiteralPath $file).LastWriteTime = (Get-Date).AddDays(-9)
$out = Invoke-Hook
$json = $out | ConvertFrom-Json
Check "過期仍然注入（舊 context 勝於沒有）" ($json.hookSpecificOutput.additionalContext -match '某個坑')
Check "標出過期警告" ($json.hookSpecificOutput.additionalContext -match '沒更新')
Check "告知重建方式" ($json.hookSpecificOutput.additionalContext -match 'harness context --refresh')

Write-Host "`n=== 效能：必須遠低於 SessionStart 的 ~1.5s 預算 ===" -ForegroundColor Cyan
(Get-Item -LiteralPath $file).LastWriteTime = (Get-Date)
$sw = [Diagnostics.Stopwatch]::StartNew()
Invoke-Hook | Out-Null
$sw.Stop()
Write-Host "  耗時 $($sw.ElapsedMilliseconds) ms"
Check "< 1200 ms" ($sw.ElapsedMilliseconds -lt 1200)

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Host ""
if ($fail -eq 0) { Write-Host "全部通過" -ForegroundColor Green } else { Write-Host "$fail 個失敗" -ForegroundColor Red }
exit $fail
