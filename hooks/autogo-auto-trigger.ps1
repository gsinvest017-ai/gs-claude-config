# autogo-auto-trigger.ps1 — UserPromptSubmit hook（matcher: 所有 prompt）
#
# 自動評估是否應注入 autogo screen context，無需使用者輸入 /autogo。
# 決策依據來自 ~/.claude/autogo-trigger-policy.json（可替換、可擴充）。
#
# 輸出 [autogo-suggest] 塊，由 SKILL.md 決定最終處理方式：
#   inject  → 帶入 top_ocr 摘要（相當於輕量 /autogo）
#   suggest → 顯示「需要螢幕 context 嗎？」提示
#   skip    → 靜默，不輸出任何內容
#
# Matched by settings.json matcher "^(?!/autogo)" — 排除 /autogo 開頭的 prompt
# 避免與 autogo-prefetch.ps1 重複觸發。
#
# Always exits 0.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── 1. 讀 prompt ──────────────────────────────────────────────────────────────
$stdin = [Console]::In.ReadToEnd()
$prompt = ""
$pm = [regex]::Match($stdin, '"prompt"\s*:\s*"((?:[^"\\]|\\.)*)"')
if ($pm.Success) {
    $prompt = $pm.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' -replace '\\n', "`n"
}
if (-not $prompt) { exit 0 }

# ── 2. 載入觸發政策 ───────────────────────────────────────────────────────────
$policyFile = Join-Path $env:USERPROFILE ".claude\autogo-trigger-policy.json"
if (-not (Test-Path $policyFile)) { exit 0 }

$policy = $null
try { $policy = Get-Content $policyFile -Raw | ConvertFrom-Json } catch { exit 0 }
if (-not $policy) { exit 0 }

# ── 3. 取得目前 watcher 狀態（輕量，不帶 --format=full）──────────────────────
$py = 'C:\Users\User\autogo\.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { exit 0 }

$contextJson = $null
try {
    $ctxRaw = & $py -m autogo_dash.context_cli --format=full 2>$null | Out-String
    # 快速取出 text_blocks_total（簡單 regex，不 parse 完整 JSON）
    $tbMatch = [regex]::Match($ctxRaw, '"text_blocks"\s*:\s*(\d+)')
    $hasWatcher = $ctxRaw -match '"window_id"'
    $topOcrRaw = ""
    $tocrMatch = [regex]::Match($ctxRaw, '\|\s*\d+\s*\|[^|]+\|[^|]+\|[^|]+\|\s*([^|]+)\|')
    if ($tocrMatch.Success) { $topOcrRaw = $tocrMatch.Groups[1].Value.Trim() }
} catch { exit 0 }

if (-not $hasWatcher) { exit 0 }  # 無 watcher，無需觸發

# ── 4. 評估規則 ───────────────────────────────────────────────────────────────
$promptLower = $prompt.ToLower()
$topOcrLower = $topOcrRaw.ToLower()

$bestAction = $policy.default_action
$bestPriority = -1
$bestRuleId = ""
$bestConfidence = 0.0

foreach ($rule in ($policy.rules | Where-Object { $_.enabled })) {
    # skip rule：最高優先，立即 break
    if ($rule.action -eq "skip") {
        $keyAny = $rule.match.keywords_any
        if ($keyAny) {
            $matched = $keyAny | Where-Object { $promptLower -match [regex]::Escape($_) }
            if ($matched) {
                $bestAction = "skip"
                $bestRuleId = $rule.id
                break
            }
        }
        continue
    }

    # require_watcher check
    if ($rule.require_watcher -and -not $hasWatcher) { continue }

    # keyword match
    $keywordMatched = $false
    if ($rule.match.keywords_any) {
        $keywordMatched = ($rule.match.keywords_any | Where-Object { $promptLower -match [regex]::Escape($_) }).Count -gt 0
    }

    # top_ocr match
    $topOcrMatched = $false
    if ($rule.match.top_ocr_contains_any) {
        $topOcrMatched = ($rule.match.top_ocr_contains_any | Where-Object { $topOcrLower -match [regex]::Escape($_) }).Count -gt 0
    }

    if (-not ($keywordMatched -or $topOcrMatched)) { continue }

    # exclude check
    if ($rule.exclude -and $rule.exclude.keywords_any) {
        $excluded = ($rule.exclude.keywords_any | Where-Object { $promptLower -match [regex]::Escape($_) }).Count -gt 0
        if ($excluded) { continue }
    }

    if ($rule.priority -gt $bestPriority) {
        $bestPriority = $rule.priority
        $bestAction = $rule.action
        $bestRuleId = $rule.id
        $bestConfidence = $rule.confidence
    }
}

# skip → 靜默退出
if ($bestAction -eq "skip" -or $bestAction -eq "") { exit 0 }

# ── 5. 拉輕量 context（Top OCR 用於摘要）────────────────────────────────────
$ctxArgs = @("--format=full")
if ($policy.context_cli_args) {
    foreach ($a in $policy.context_cli_args) { $ctxArgs += $a }
}
$ctxOutput = (& $py -m autogo_dash.context_cli @ctxArgs 2>$null | Out-String)
$ctxSummary = ($ctxOutput | & $py -m autogo_dash.context_summary --input=full | Out-String)

# 取 Top OCR from [autogo-response] table
$currentTopOcr = ""
foreach ($line in ($ctxSummary -split "`n")) {
    if ($line -match '^\|\s*\d+\s*\|') {
        if ($line -match '\|\s*([^|]+?)\s*\|\s*$') { $currentTopOcr = $matches[1].Trim() }
        break
    }
}

# ── 6. 輸出 [autogo-suggest] 塊 ──────────────────────────────────────────────
$confFmt = [math]::Round($bestConfidence, 2)
Write-Output "[autogo-suggest]"
Write-Output "action: $bestAction"
Write-Output "triggered_by: $bestRuleId"
Write-Output "confidence: $confFmt"
Write-Output "experiment: $($policy.active_experiment)"
if ($currentTopOcr) { Write-Output "top_ocr: $currentTopOcr" }
Write-Output "[/autogo-suggest]"

exit 0
