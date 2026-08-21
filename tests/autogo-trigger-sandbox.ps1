# ~/.claude/tests/autogo-trigger-sandbox.ps1
#
# Sandbox test for autogo auto-trigger policy rules.
# Validates 5 example prompts against ~/.claude/autogo-trigger-policy.json.
# Does NOT call autogo dashboard or modify any autogo repo files.
#
# Modes:
#   UNIT (default)   — in-process evaluation, mirrors hook logic, no dashboard needed
#   INTEGRATION      — invokes actual autogo-auto-trigger.ps1 hook via stdin pipe
#
# Usage:
#   pwsh ~\.claude\tests\autogo-trigger-sandbox.ps1
#   pwsh ~\.claude\tests\autogo-trigger-sandbox.ps1 -Verbose
#   pwsh ~\.claude\tests\autogo-trigger-sandbox.ps1 -Integration   # needs autogo dashboard running

param(
    [switch]$Integration,
    [switch]$Verbose
)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ─────────────────────────────────────────────────────────────────────────────
# Test cases — 5 example prompts with expected rule/action
# NOTE: TC2 contains English "error" which also matches pytest-debug-short
#       (priority 10 > debug-question priority 8). This surfaces a policy
#       conflict: the sandbox will FAIL this case by design.
# ─────────────────────────────────────────────────────────────────────────────
$TEST_CASES = @(
    @{
        Id=1; Desc="pytest short debug"
        Prompt="pytest 跑出 AssertionError，怎麼修？"
        ExpRule="pytest-debug-short"; ExpAction="inject"
    }
    @{
        Id=2; Desc="debug question  ← contains 'error', may conflict with pytest-debug-short"
        Prompt="這個 error 為什麼會出現？"
        ExpRule="debug-question"; ExpAction="suggest"
    }
    @{
        Id=3; Desc="visual state query"
        Prompt="畫面上顯示什麼錯誤？"
        ExpRule="visual-state-query"; ExpAction="inject"
    }
    @{
        Id=4; Desc="long output suppress"
        Prompt="pytest --parametrize 跑完了"
        ExpRule="long-output-suppress"; ExpAction="skip"
    }
    @{
        Id=5; Desc="general conversation (no rule expected)"
        Prompt="今天天氣怎麼樣？"
        ExpRule=""; ExpAction="skip"
    }
)

# ─────────────────────────────────────────────────────────────────────────────
# Load policy
# ─────────────────────────────────────────────────────────────────────────────
$policyFile = Join-Path $env:USERPROFILE ".claude\autogo-trigger-policy.json"
if (-not (Test-Path $policyFile)) {
    Write-Host "ERROR: policy file not found: $policyFile" -ForegroundColor Red
    exit 1
}
$policy = Get-Content $policyFile -Raw | ConvertFrom-Json

# ─────────────────────────────────────────────────────────────────────────────
# Rule evaluator — exact mirror of autogo-auto-trigger.ps1 evaluation logic.
# Mock: $HasWatcher=$true (assume at least one watcher active).
# Mock: $TopOcrRaw="" (blank top OCR — only affects top_ocr_contains_any rules).
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-EvaluateRules {
    param(
        [string]$Prompt,
        [bool]$HasWatcher = $true,
        [string]$TopOcrRaw = "",
        [object]$Policy
    )
    $pl = $Prompt.ToLower(); $tl = $TopOcrRaw.ToLower()
    $bestAction = $Policy.default_action
    $bestPri = -1; $bestId = ""; $bestConf = 0.0
    $trace = [System.Collections.Generic.List[string]]::new()

    foreach ($rule in ($Policy.rules | Where-Object { $_.enabled })) {

        # Skip rules: special early-break path
        if ($rule.action -eq "skip") {
            $kw = $rule.match.keywords_any
            if ($kw) {
                $hit = @($kw | Where-Object { $pl -match [regex]::Escape($_) })
                if ($hit.Count -gt 0) {
                    $trace.Add("SKIP-BREAK  rule=$($rule.id)  kw=[$($hit -join ', ')]")
                    $bestAction = "skip"; $bestId = $rule.id; $bestConf = $rule.confidence
                    break
                }
            }
            $trace.Add("SKIP-NOMATCH  rule=$($rule.id)")
            continue
        }

        # require_watcher guard
        if ($rule.require_watcher -and -not $HasWatcher) {
            $trace.Add("SKIP-NO-WATCHER  rule=$($rule.id)")
            continue
        }

        # keyword match
        $kwHit = @()
        if ($rule.match.keywords_any) {
            $kwHit = @($rule.match.keywords_any | Where-Object { $pl -match [regex]::Escape($_) })
        }
        $ocrHit = $false
        if ($rule.match.top_ocr_contains_any) {
            $ocrHit = (@($rule.match.top_ocr_contains_any | Where-Object { $tl -match [regex]::Escape($_) }).Count -gt 0)
        }
        if (-not ($kwHit.Count -gt 0 -or $ocrHit)) {
            $trace.Add("MISS  rule=$($rule.id)")
            continue
        }

        # exclude check
        if ($rule.exclude -and $rule.exclude.keywords_any) {
            $excHit = @($rule.exclude.keywords_any | Where-Object { $pl -match [regex]::Escape($_) })
            if ($excHit.Count -gt 0) {
                $trace.Add("EXCLUDED  rule=$($rule.id)  by=[$($excHit -join ', ')]")
                continue
            }
        }

        $trace.Add("MATCH  rule=$($rule.id)  pri=$($rule.priority)  action=$($rule.action)  kw=[$($kwHit -join ', ')]")
        if ($rule.priority -gt $bestPri) {
            $bestPri = $rule.priority; $bestAction = $rule.action
            $bestId = $rule.id; $bestConf = $rule.confidence
        }
    }
    return @{ Action=$bestAction; RuleId=$bestId; Confidence=$bestConf; Trace=$trace }
}

# ─────────────────────────────────────────────────────────────────────────────
# Integration: invoke actual hook via stdin pipe (requires autogo dashboard)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-ActualHook {
    param([string]$Prompt)
    $hookPath = Join-Path $env:USERPROFILE ".claude\hooks\autogo-auto-trigger.ps1"
    if (-not (Test-Path $hookPath)) { return @{ Error="Hook not found: $hookPath" } }
    $escaped = $Prompt -replace '\\', '\\\\' -replace '"', '\"'
    $stdinJson = '{"prompt":"' + $escaped + '","session_id":"sandbox-test"}'
    try {
        $out = ($stdinJson | pwsh -NoProfile -NonInteractive -File $hookPath 2>$null | Out-String)
        $act = ""; $rid = ""; $conf = ""
        foreach ($line in ($out -split "`n")) {
            if ($line -match '^action:\s*(\S+)')      { $act  = $matches[1].Trim() }
            if ($line -match '^triggered_by:\s*(\S+)') { $rid  = $matches[1].Trim() }
            if ($line -match '^confidence:\s*(\S+)')   { $conf = $matches[1].Trim() }
        }
        return @{
            Action=(if ($act) { $act } else { "skip" })
            RuleId=$rid; Confidence=$conf; RawOutput=$out.Trim()
        }
    } catch {
        return @{ Error=$_.Exception.Message }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Run test cases
# ─────────────────────────────────────────────────────────────────────────────
$passed = 0; $failed = 0; $flagged = 0
$sep = ("─" * 68)

Write-Host ""
Write-Host $sep -ForegroundColor DarkGray
Write-Host " autogo auto-trigger sandbox" -ForegroundColor White -NoNewline
Write-Host "  [$(if ($Integration) { 'INTEGRATION' } else { 'UNIT' })]" -ForegroundColor Yellow
Write-Host " policy: $(Split-Path $policyFile -Leaf)   experiment: $($policy.active_experiment)" -ForegroundColor DarkGray
Write-Host $sep -ForegroundColor DarkGray

foreach ($tc in $TEST_CASES) {
    Write-Host ""
    Write-Host "TC$($tc.Id)  $($tc.Desc)" -ForegroundColor Cyan
    Write-Host "  prompt  : `"$($tc.Prompt)`""
    Write-Host "  expected: action=$($tc.ExpAction)  rule=$(if ($tc.ExpRule) { $tc.ExpRule } else { '(none)' })" -ForegroundColor DarkGray

    if ($Integration) {
        $r = Invoke-ActualHook -Prompt $tc.Prompt
        if ($r.Error) {
            Write-Host "  ERROR: $($r.Error)" -ForegroundColor Red
            $failed++; continue
        }
    } else {
        $r = Invoke-EvaluateRules -Prompt $tc.Prompt -HasWatcher $true -Policy $policy
    }

    $actAction = $r.Action
    $actRule   = if ($r.RuleId) { $r.RuleId } else { "(none)" }

    $actionOk = $actAction -eq $tc.ExpAction
    $ruleOk   = ($tc.ExpRule -eq "") -or ($r.RuleId -eq $tc.ExpRule)
    $pass     = $actionOk -and $ruleOk
    $flag     = $actionOk -and (-not $ruleOk) -and ($tc.ExpRule -ne "")

    $status = if ($pass) { "[PASS]" } elseif ($flag) { "[FLAG]" } else { "[FAIL]" }
    $color  = if ($pass) { "Green" } elseif ($flag) { "Yellow" } else { "Red" }

    Write-Host "  actual  : action=$actAction  rule=$actRule" -ForegroundColor White
    Write-Host "  $status" -ForegroundColor $color

    if ($flag) {
        Write-Host "  ↳ action correct but different rule fired — check keyword overlap between rules" -ForegroundColor Yellow
    }
    if (-not $pass -and -not $flag) {
        Write-Host "  ↳ mismatch — expected $($tc.ExpAction)/$($tc.ExpRule), got $actAction/$actRule" -ForegroundColor Red
    }

    if ($Verbose -and $r.Trace) {
        Write-Host "  rule trace:" -ForegroundColor DarkGray
        foreach ($t in $r.Trace) { Write-Host "    · $t" -ForegroundColor DarkGray }
    }
    if ($Integration -and $Verbose -and $r.RawOutput) {
        Write-Host "  --- raw hook output ---" -ForegroundColor DarkGray
        $r.RawOutput -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }

    if ($pass) { $passed++ } elseif ($flag) { $flagged++ } else { $failed++ }
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host $sep -ForegroundColor DarkGray
$totalColor = if ($failed -gt 0) { "Red" } elseif ($flagged -gt 0) { "Yellow" } else { "Green" }
Write-Host " PASS=$passed  FLAG=$flagged  FAIL=$failed  (total: $($TEST_CASES.Count))" -ForegroundColor $totalColor

if ($flagged -gt 0) {
    Write-Host " FLAG = action matched expectation but a different rule fired (policy overlap)" -ForegroundColor Yellow
}
if ($failed -gt 0) {
    Write-Host " FAIL = action or rule did not match expectation" -ForegroundColor Red
}
Write-Host $sep -ForegroundColor DarkGray
Write-Host ""
Write-Host "Tips:" -ForegroundColor DarkGray
Write-Host "  -Verbose       show per-rule evaluation trace" -ForegroundColor DarkGray
Write-Host "  -Integration   invoke actual hook (requires autogo dashboard running)" -ForegroundColor DarkGray
Write-Host "  Edit policy:   $policyFile" -ForegroundColor DarkGray
Write-Host ""
