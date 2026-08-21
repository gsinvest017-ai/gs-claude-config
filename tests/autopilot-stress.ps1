# ~/.claude/tests/autopilot-stress.ps1
#
# Valve + stress harness for the /autopilot loop core.
#
# Spawns the REAL hook scripts as child processes and feeds them synthesized
# stdin payloads, exactly the way Claude Code does. Every case runs against a
# throwaway sandbox: USERPROFILE / HOME are pointed at a temp dir, so the live
# ~/.claude/.autopilot state of the session running this test is never touched.
#
# Three implementations of the same state machine exist in this repo; the
# harness runs the identical case list against each one to catch divergence:
#   ps1 — hooks/autopilot-continue.ps1  + hooks/autopilot-arm.ps1   (script install, Windows)
#   sh  — hooks/autopilot-continue.sh   + hooks/autopilot-arm.sh    (script install, WSL/macOS; needs jq)
#   mjs — plugins/gs-autopilot/hooks/autopilot.mjs                  (plugin install, both events)
#
# Usage:
#   pwsh ~\.claude\tests\autopilot-stress.ps1                 # all available impls, full 50-round run
#   pwsh ~\.claude\tests\autopilot-stress.ps1 -Quick          # 5-round ceiling run (fast)
#   pwsh ~\.claude\tests\autopilot-stress.ps1 -Impl ps1
#   pwsh ~\.claude\tests\autopilot-stress.ps1 -KeepSandbox    # leave temp dirs for inspection
#
# Exit code: 0 = all cases passed, 1 = at least one FAIL.
# Unavailable implementations are reported as SKIP with the reason — never
# silently dropped.

[CmdletBinding()]
param(
    [ValidateSet('ps1', 'mjs', 'sh', 'all')][string]$Impl = 'all',
    [int]$MaxRounds = 50,
    [switch]$Quick,
    [switch]$KeepSandbox
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$Utf8Bom   = New-Object System.Text.UTF8Encoding $true
if ($Quick) { $MaxRounds = 5 }

# ─────────────────────────────────────────────────────────────────────────────
# Implementation table
# ─────────────────────────────────────────────────────────────────────────────
$IMPLS = [ordered]@{
    ps1 = @{
        Label = 'ps1  (hooks/autopilot-*.ps1)'
        Stop  = Join-Path $RepoRoot 'hooks/autopilot-continue.ps1'
        Arm   = Join-Path $RepoRoot 'hooks/autopilot-arm.ps1'
        Exe   = 'pwsh'
        MkArgs = { param($f) @('-NoProfile', '-NonInteractive', '-File', $f) }
    }
    sh  = @{
        Label = 'sh   (hooks/autopilot-*.sh)'
        Stop  = Join-Path $RepoRoot 'hooks/autopilot-continue.sh'
        Arm   = Join-Path $RepoRoot 'hooks/autopilot-arm.sh'
        Exe   = 'bash'
        MkArgs = { param($f) @((ConvertTo-PosixPath $f)) }
    }
    mjs = @{
        Label = 'mjs  (plugins/gs-autopilot/hooks/autopilot.mjs)'
        Stop  = Join-Path $RepoRoot 'plugins/gs-autopilot/hooks/autopilot.mjs'
        Arm   = Join-Path $RepoRoot 'plugins/gs-autopilot/hooks/autopilot.mjs'
        Exe   = 'node'
        MkArgs = { param($f) @($f) }
    }
}

function ConvertTo-PosixPath([string]$p) {
    # C:\a\b -> /c/a/b  (Git Bash / WSL style; bash also accepts forward slashes)
    if ($p -match '^([A-Za-z]):[\\/](.*)$') {
        return '/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
    }
    return ($p -replace '\\', '/')
}

function Test-ImplAvailable([string]$name) {
    switch ($name) {
        'ps1' {
            if (Get-Command pwsh -ErrorAction SilentlyContinue) { return @{ Ok = $true } }
            return @{ Ok = $false; Why = 'pwsh 不在 PATH' }
        }
        'mjs' {
            if (Get-Command node -ErrorAction SilentlyContinue) { return @{ Ok = $true } }
            return @{ Ok = $false; Why = 'node 不在 PATH（plugin hook 需要 node）' }
        }
        'sh' {
            if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
                return @{ Ok = $false; Why = 'bash 不在 PATH' }
            }
            $probe = ''
            try { $probe = (& bash -lc 'command -v jq >/dev/null 2>&1 && echo yes' 2>$null | Out-String).Trim() } catch { }
            if ($probe -ne 'yes') {
                return @{ Ok = $false; Why = 'bash 有但缺 jq —— .sh hook 沒 jq 會直接 fail-open（exit 0），測不出狀態機' }
            }
            return @{ Ok = $true }
        }
    }
    return @{ Ok = $false; Why = "未知實作 $name" }
}

# ─────────────────────────────────────────────────────────────────────────────
# Sandbox + state helpers
# ─────────────────────────────────────────────────────────────────────────────
function New-Sandbox {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('autopilot-stress-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $dir  = Join-Path $root '.claude\.autopilot'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [pscustomobject]@{
        Root  = $root
        Dir   = $dir
        State = Join-Path $dir 'state.json'
        Done  = Join-Path $dir 'done'
    }
}

function Set-SandboxState {
    param($Sandbox, [hashtable]$Fields = @{}, [string[]]$Remove = @(), [switch]$Bom, [string]$Raw)
    if ($PSBoundParameters.ContainsKey('Raw')) {
        [System.IO.File]::WriteAllText($Sandbox.State, $Raw, $Utf8NoBom)
        return
    }
    $d = [ordered]@{
        session_id     = 'sess-A'
        iterations     = 0
        max_iterations = 50
        started        = '2026-07-31T00:00:00.0000000+08:00'
        task           = '壓測任務'
    }
    foreach ($k in $Fields.Keys) { $d[$k] = $Fields[$k] }
    foreach ($k in $Remove) { $d.Remove($k) }
    $json = ($d | ConvertTo-Json -Compress)
    $enc = if ($Bom) { $Utf8Bom } else { $Utf8NoBom }
    [System.IO.File]::WriteAllText($Sandbox.State, $json, $enc)
}

function Get-SandboxState($Sandbox) {
    if (-not (Test-Path -LiteralPath $Sandbox.State)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Sandbox.State)
    if (-not $raw.Trim()) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return 'INVALID' }
}

# ─────────────────────────────────────────────────────────────────────────────
# Hook invocation
# ─────────────────────────────────────────────────────────────────────────────
function Start-HookAsync {
    param([string]$ImplName, [ValidateSet('Stop', 'UserPromptSubmit')][string]$Event,
          [hashtable]$Payload = @{}, $Sandbox, [string]$RawStdin)

    $cfg    = $IMPLS[$ImplName]
    $script = if ($Event -eq 'Stop') { $cfg.Stop } else { $cfg.Arm }

    if ($PSBoundParameters.ContainsKey('RawStdin')) {
        $json = $RawStdin
    }
    else {
        $p = @{} + $Payload
        if (-not $p.ContainsKey('session_id')) { $p['session_id'] = 'sess-A' }
        $p['hook_event_name'] = $Event          # the mjs shim dispatches on this
        $json = ($p | ConvertTo-Json -Depth 6 -Compress)
    }

    $tmpIn  = [System.IO.Path]::GetTempFileName()
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpIn, $json, $Utf8NoBom)

    $proc = Start-Process -FilePath $cfg.Exe -ArgumentList (& $cfg.MkArgs $script) `
        -NoNewWindow -PassThru `
        -RedirectStandardInput $tmpIn -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    [pscustomobject]@{ Proc = $proc; In = $tmpIn; Out = $tmpOut; Err = $tmpErr }
}

function Wait-HookResult($handle) {
    $handle.Proc.WaitForExit()
    $stdout = [System.IO.File]::ReadAllText($handle.Out)
    $stderr = [System.IO.File]::ReadAllText($handle.Err)
    Remove-Item -LiteralPath $handle.In, $handle.Out, $handle.Err -Force -ErrorAction SilentlyContinue

    $decision = $null; $reason = $null; $ctx = $null
    if ($stdout.Trim()) {
        try {
            $o = $stdout | ConvertFrom-Json
            if ($o.PSObject.Properties.Name -contains 'decision') { $decision = [string]$o.decision }
            if ($o.PSObject.Properties.Name -contains 'reason') { $reason = [string]$o.reason }
            if ($o.PSObject.Properties.Name -contains 'hookSpecificOutput') { $ctx = [string]$o.hookSpecificOutput.additionalContext }
        }
        catch { }
    }
    [pscustomobject]@{
        ExitCode = $handle.Proc.ExitCode
        Stdout   = $stdout
        Stderr   = $stderr
        Decision = $decision
        Reason   = $reason
        Context  = $ctx
        Blocked  = ($decision -eq 'block')
    }
}

function Invoke-Hook {
    param([string]$ImplName, [ValidateSet('Stop', 'UserPromptSubmit')][string]$Event,
          [hashtable]$Payload = @{}, $Sandbox, [string]$RawStdin)

    $savedUp = $env:USERPROFILE
    $savedHome = $env:HOME
    try {
        # Isolation: ps1 reads $env:USERPROFILE, node's os.homedir() reads
        # USERPROFILE on Windows / HOME elsewhere, bash reads $HOME.
        $env:USERPROFILE = $Sandbox.Root
        $env:HOME = if ($ImplName -eq 'sh') { ConvertTo-PosixPath $Sandbox.Root } else { $Sandbox.Root }
        $h = if ($PSBoundParameters.ContainsKey('RawStdin')) {
            Start-HookAsync -ImplName $ImplName -Event $Event -Sandbox $Sandbox -RawStdin $RawStdin
        }
        else {
            Start-HookAsync -ImplName $ImplName -Event $Event -Payload $Payload -Sandbox $Sandbox
        }
        return (Wait-HookResult $h)
    }
    finally {
        $env:USERPROFILE = $savedUp
        if ($null -eq $savedHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHome }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Assertions + case runner
# ─────────────────────────────────────────────────────────────────────────────
$script:Results = New-Object System.Collections.Generic.List[object]

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Equal($Expected, $Actual, [string]$What) {
    if ("$Expected" -cne "$Actual") { throw "$What：預期 '<$Expected>'，實得 '<$Actual>'" }
}

function Invoke-Case {
    param([string]$ImplName, [string]$Id, [string]$Name, [scriptblock]$Body)
    $sb = New-Sandbox
    $note = ''
    try {
        $note = [string](& $Body $ImplName $sb)
        $script:Results.Add([pscustomobject]@{ Impl = $ImplName; Id = $Id; Name = $Name; Status = 'PASS'; Detail = $note })
        Write-Host ("  ✓ {0,-4} {1}{2}" -f $Id, $Name, ($(if ($note) { "  — $note" } else { '' }))) -ForegroundColor DarkGreen
    }
    catch {
        $script:Results.Add([pscustomobject]@{ Impl = $ImplName; Id = $Id; Name = $Name; Status = 'FAIL'; Detail = $_.Exception.Message })
        Write-Host ("  ✗ {0,-4} {1}" -f $Id, $Name) -ForegroundColor Red
        Write-Host ("        → {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
    finally {
        if (-not $KeepSandbox) { Remove-Item -LiteralPath $sb.Root -Recurse -Force -ErrorAction SilentlyContinue }
        else { Write-Host "        sandbox: $($sb.Root)" -ForegroundColor DarkGray }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Case list — identical for every implementation (parity by construction)
# ─────────────────────────────────────────────────────────────────────────────
$CASES = @(
    # ---- Stop hook: the five safety valves -------------------------------
    @{
        Id = 'V1'; Name = 'valve 1：stop_hook_active=true 一律讓步'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A'; stop_hook_active = $true } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '不該 block'
            Assert-Equal 0 (Get-SandboxState $sb).iterations 'iterations 不該被動'
            Assert-That (Test-Path -LiteralPath $sb.State) 'state.json 不該被刪'
        }
    }
    @{
        Id = 'V2'; Name = 'valve 2：無 state.json → 預設關閉，放行'
        Body = {
            param($impl, $sb)
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '沒有旗標時不該 block'
            Assert-Equal '' $r.Stdout.Trim() 'stdout 應為空'
        }
    }
    @{
        Id = 'V3'; Name = 'valve 3：別的 session 的旗標不得劫持本 session'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ session_id = 'sess-OTHER'; iterations = 3 }
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '外來旗標不該 block'
            Assert-Equal 3 (Get-SandboxState $sb).iterations '別人的計數不該被動'
        }
    }
    @{
        Id = 'V4'; Name = 'valve 4：done sentinel → 收尾並清掉兩個檔'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ iterations = 7 }
            New-Item -ItemType File -Path $sb.Done -Force | Out-Null
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '看到 done 不該 block'
            Assert-That (-not (Test-Path -LiteralPath $sb.Done)) 'done 應被刪除'
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) 'state.json 應被刪除'
        }
    }
    @{
        Id = 'V5'; Name = 'valve 5：iterations 達上限 → 強制停 + 清旗標 + stderr 提示'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ iterations = 50; max_iterations = 50 }
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '達上限不該再 block'
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) 'state.json 應被刪除'
            Assert-That ($r.Stderr -match '上限') "stderr 應提示上限，實得：'$($r.Stderr.Trim())'"
        }
    }
    @{
        Id = 'V6'; Name = '正常續跑：block + reason 帶第 n/max + 計數 +1'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-Equal 'block' $r.Decision 'decision'
            Assert-That ($r.Reason -match '第\s*1/50\s*次續跑') "reason 應含「第 1/50 次續跑」，實得：'$($r.Reason)'"
            Assert-That ($r.Reason -match 'AskUserQuestion') 'reason 應含禁止 AskUserQuestion 的指示'
            Assert-Equal 1 (Get-SandboxState $sb).iterations 'iterations 應為 1'
        }
    }
    @{
        Id = 'V7'; Name = 'max_iterations=0 → 退回預設 50，不得變成永不續跑'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ max_iterations = 0 }
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 'block' $r.Decision 'decision'
            Assert-That ($r.Reason -match '1/50') "reason 應以 50 為上限，實得：'$($r.Reason)'"
        }
    }
    @{
        Id = 'V8'; Name = '缺 iterations 欄位 → 視為 0'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb -Remove @('iterations')
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 'block' $r.Decision 'decision'
            Assert-That ($r.Reason -match '第\s*1/') "reason 應為第 1 次，實得：'$($r.Reason)'"
            Assert-Equal 1 (Get-SandboxState $sb).iterations 'iterations 應寫回 1'
        }
    }
    @{
        Id = 'V9'; Name = 'state.json 損毀 → fail-open（放行，不得 wedge session）'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb -Raw '{ "session_id": "sess-A", iterations: '
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '壞掉的旗標不該 block'
        }
    }
    @{
        Id = 'V10'; Name = 'state.json 為空檔 → fail-open'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb -Raw ''
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '空旗標不該 block'
        }
    }
    @{
        Id = 'V11'; Name = 'stdin 為空 → 不得 crash，且放行'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            $r = Invoke-Hook $impl Stop -Sandbox $sb -RawStdin ''
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not $r.Blocked) '無 payload 不該 block'
        }
    }
    @{
        Id = 'V12'; Name = 'state.json 帶 UTF-8 BOM → 仍須正常續跑（PS 5.1 寫出的旗標）'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb -Bom
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-Equal 'block' $r.Decision 'BOM 不該讓 autopilot 靜默失效（解析失敗會 fail-open）'
            Assert-Equal 1 (Get-SandboxState $sb).iterations '計數應照常 +1'
        }
    }
    @{
        Id = 'V13'; Name = '連續 5 輪計數單調遞增，每輪 reason 的 n 正確'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            for ($i = 1; $i -le 5; $i++) {
                $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
                Assert-Equal 'block' $r.Decision "第 $i 輪 decision"
                Assert-That ($r.Reason -match "第\s*$i/50") "第 $i 輪 reason 應含「第 $i/50」，實得：'$($r.Reason)'"
                Assert-Equal $i (Get-SandboxState $sb).iterations "第 $i 輪 iterations"
            }
        }
    }
    @{
        Id = 'V14'; Name = 'iterations 遠超 max（999/50）→ 立即強制停'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ iterations = 999 }
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-That (-not $r.Blocked) '超出上限不該 block'
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) 'state.json 應被刪除'
        }
    }

    # ---- arm hook: /autopilot on|off|status ------------------------------
    @{
        Id = 'A1'; Name = 'arm：/autopilot on <任務> 建旗標並綁定本 session'
        Body = {
            param($impl, $sb)
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-NEW'; prompt = '/autopilot on 把 CI 修綠' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            $s = Get-SandboxState $sb
            Assert-That ($null -ne $s -and $s -ne 'INVALID') 'state.json 應被建立且為合法 JSON'
            Assert-Equal 'sess-NEW' $s.session_id 'session_id 應為本 session'
            Assert-Equal 0 $s.iterations 'iterations 應為 0'
            Assert-Equal 50 $s.max_iterations 'max_iterations 應為 50'
            Assert-Equal '把 CI 修綠' $s.task 'task 應被記錄'
            Assert-That ($r.Context -match '已武裝') "additionalContext 應告知已武裝，實得：'$($r.Context)'"
        }
    }
    @{
        Id = 'A2'; Name = 'arm：/autopilot off 刪掉旗標與 done'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            New-Item -ItemType File -Path $sb.Done -Force | Out-Null
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-A'; prompt = '/autopilot off' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) 'state.json 應被刪除'
            Assert-That (-not (Test-Path -LiteralPath $sb.Done)) 'done 應被刪除'
        }
    }
    @{
        Id = 'A3'; Name = 'arm：/autopilot status 不改動任何狀態'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ iterations = 4 }
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-A'; prompt = '/autopilot status' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-Equal 4 (Get-SandboxState $sb).iterations 'iterations 不該被動'
        }
    }
    @{
        Id = 'A4'; Name = 'arm：裸 /autopilot（未帶 on）不得武裝'
        Body = {
            param($impl, $sb)
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-A'; prompt = '/autopilot' } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) '不該建立 state.json'
        }
    }
    @{
        Id = 'A5'; Name = 'arm 回歸：殘留的 done 必須在 on 時清掉（否則第一次 Stop 就被放行）'
        Body = {
            param($impl, $sb)
            New-Item -ItemType File -Path $sb.Done -Force | Out-Null
            Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-A'; prompt = '/autopilot on 任務' } $sb | Out-Null
            Assert-That (-not (Test-Path -LiteralPath $sb.Done)) '殘留 done 應被清掉'
            $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-Equal 'block' $r.Decision '武裝後第一次 Stop 應續跑'
        }
    }
    @{
        Id = 'A6'; Name = 'arm：多行任務描述（第一行 /autopilot on ...，後續換行細節）仍須武裝'
        Body = {
            param($impl, $sb)
            $prompt = "/autopilot on 把 strategies/ 接到回測框架`n細節：先跑 dry-run`n再跑一次真實回測"
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-ML'; prompt = $prompt } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            Assert-That (Test-Path -LiteralPath $sb.State) '多行任務也必須建立 state.json（否則使用者以為開了、其實沒開）'
            $s = Get-SandboxState $sb
            Assert-Equal 'sess-ML' $s.session_id 'session_id'
            Assert-That ($s.task -match '把 strategies/ 接到回測框架') "task 應至少含第一行，實得：'$($s.task)'"
            Assert-That ($r.Context -match '已武裝') 'additionalContext 應告知已武裝'
        }
    }
    @{
        Id = 'A7'; Name = 'arm：任務含雙引號／反斜線／中文，state.json 仍為合法 JSON'
        Body = {
            param($impl, $sb)
            $task = '修 "C:\path\to\file" 的 UTF-8 問題 & 加 --force 旗標'
            $r = Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-Q'; prompt = "/autopilot on $task" } $sb
            Assert-Equal 0 $r.ExitCode 'exit code'
            $s = Get-SandboxState $sb
            Assert-That ($s -ne 'INVALID' -and $null -ne $s) 'state.json 必須是合法 JSON'
            Assert-Equal $task $s.task 'task 應原樣保留'
            # 旗標壞掉的話下一輪 Stop 會 fail-open，等於 autopilot 靜默失效
            $r2 = Invoke-Hook $impl Stop @{ session_id = 'sess-Q' } $sb
            Assert-Equal 'block' $r2.Decision '含特殊字元的任務不該讓續跑失效'
        }
    }
    @{
        Id = 'A8'; Name = 'arm：prompt 前置空白仍可武裝'
        Body = {
            param($impl, $sb)
            Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-A'; prompt = '   /autopilot on 任務' } $sb | Out-Null
            Assert-That (Test-Path -LiteralPath $sb.State) '前置空白不該擋掉武裝'
        }
    }

    # ---- stress ----------------------------------------------------------
    @{
        Id = 'S1'; Name = "壓測：連跑到上限（$MaxRounds 輪）後精準放行一次"
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb @{ max_iterations = $MaxRounds }
            for ($i = 1; $i -le $MaxRounds; $i++) {
                $r = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
                Assert-Equal 'block' $r.Decision "第 $i/$MaxRounds 輪應續跑"
                Assert-That ($r.Reason -match "第\s*$i/$MaxRounds") "第 $i 輪 reason 的計數不對：'$($r.Reason)'"
            }
            $last = Invoke-Hook $impl Stop @{ session_id = 'sess-A' } $sb
            Assert-That (-not $last.Blocked) "第 $($MaxRounds + 1) 次應放行"
            Assert-That (-not (Test-Path -LiteralPath $sb.State)) '達上限後 state.json 應被清掉'
            Assert-That ($last.Stderr -match '上限') 'stderr 應提示已達上限'
            return "$MaxRounds 輪 block + 第 $($MaxRounds + 1) 次放行"
        }
    }
    @{
        Id = 'S2'; Name = '壓測：兩個 session 先後 on，旗標只有一份（記錄現行行為）'
        Body = {
            param($impl, $sb)
            Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-1'; prompt = '/autopilot on 任務一' } $sb | Out-Null
            Invoke-Hook $impl UserPromptSubmit @{ session_id = 'sess-2'; prompt = '/autopilot on 任務二' } $sb | Out-Null
            $r1 = Invoke-Hook $impl Stop @{ session_id = 'sess-1' } $sb
            $r2 = Invoke-Hook $impl Stop @{ session_id = 'sess-2' } $sb
            Assert-That (-not $r1.Blocked) 'session 1 應被放行（旗標已被 session 2 覆蓋，不得誤鎖）'
            Assert-Equal 'block' $r2.Decision 'session 2 應正常續跑'
            return '後者覆蓋前者：sess-1 靜默退出 autopilot（單一全域旗標的已知限制）'
        }
    }
    @{
        Id = 'S3'; Name = '壓測：同 session 兩個 Stop 併發 → state.json 不得損毀'
        Body = {
            param($impl, $sb)
            Set-SandboxState $sb
            $savedUp = $env:USERPROFILE; $savedHome = $env:HOME
            try {
                $env:USERPROFILE = $sb.Root
                $env:HOME = if ($impl -eq 'sh') { ConvertTo-PosixPath $sb.Root } else { $sb.Root }
                $h1 = Start-HookAsync -ImplName $impl -Event Stop -Payload @{ session_id = 'sess-A' } -Sandbox $sb
                $h2 = Start-HookAsync -ImplName $impl -Event Stop -Payload @{ session_id = 'sess-A' } -Sandbox $sb
                $a = Wait-HookResult $h1
                $b = Wait-HookResult $h2
            }
            finally {
                $env:USERPROFILE = $savedUp
                if ($null -eq $savedHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue } else { $env:HOME = $savedHome }
            }
            Assert-Equal 0 $a.ExitCode '併發 A exit code'
            Assert-Equal 0 $b.ExitCode '併發 B exit code'
            Assert-That ($a.Blocked -or $b.Blocked) '至少一個應續跑'
            $s = Get-SandboxState $sb
            Assert-That ($s -ne 'INVALID') "併發寫入後 state.json 損毀了：'$([System.IO.File]::ReadAllText($sb.State))'"
            Assert-That ($null -ne $s -and [int]$s.iterations -ge 1 -and [int]$s.iterations -le 2) "iterations 應在 1..2，實得 '$($s.iterations)'"
            return "iterations=$($s.iterations)（lost update 時為 1）"
        }
    }
)

# ─────────────────────────────────────────────────────────────────────────────
# Run
# ─────────────────────────────────────────────────────────────────────────────
$targets = if ($Impl -eq 'all') { @($IMPLS.Keys) } else { @($Impl) }
$skipped = @()

Write-Host ''
Write-Host '════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host " /autopilot 迴圈核心壓測   （沙盒隔離，不動 ~/.claude/.autopilot）" -ForegroundColor Cyan
Write-Host " repo: $RepoRoot" -ForegroundColor DarkGray
Write-Host " 續跑上限測試輪數: $MaxRounds$(if ($Quick) { '  (-Quick)' })" -ForegroundColor DarkGray
Write-Host '════════════════════════════════════════════════════════════════════' -ForegroundColor Cyan

foreach ($name in $targets) {
    $avail = Test-ImplAvailable $name
    if (-not $avail.Ok) {
        $skipped += [pscustomobject]@{ Impl = $name; Why = $avail.Why }
        Write-Host ''
        Write-Host ("── {0}  SKIP：{1}" -f $IMPLS[$name].Label, $avail.Why) -ForegroundColor Yellow
        continue
    }
    Write-Host ''
    Write-Host ("── {0}" -f $IMPLS[$name].Label) -ForegroundColor White
    foreach ($c in $CASES) {
        Invoke-Case -ImplName $name -Id $c.Id -Name $c.Name -Body $c.Body
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
$fails = @($script:Results | Where-Object Status -eq 'FAIL')
$pass  = @($script:Results | Where-Object Status -eq 'PASS')

Write-Host ''
Write-Host '── 結果 ───────────────────────────────────────────────────────────' -ForegroundColor Cyan
foreach ($g in ($script:Results | Group-Object Impl)) {
    $f = @($g.Group | Where-Object Status -eq 'FAIL').Count
    $colour = if ($f -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("  {0,-4} {1} 案例，{2} 失敗" -f $g.Name, $g.Group.Count, $f) -ForegroundColor $colour
}
foreach ($s in $skipped) {
    Write-Host ("  {0,-4} SKIP — {1}" -f $s.Impl, $s.Why) -ForegroundColor Yellow
}

if ($fails.Count) {
    Write-Host ''
    Write-Host '  失敗明細：' -ForegroundColor Red
    foreach ($f in $fails) {
        Write-Host ("   [{0}] {1} {2}" -f $f.Impl, $f.Id, $f.Name) -ForegroundColor Red
        Write-Host ("        {0}" -f $f.Detail) -ForegroundColor DarkRed
    }
}

# 跨實作差異：同一案例在不同實作拿到不同 PASS/FAIL 或不同備註
$parity = $script:Results | Group-Object Id | Where-Object {
    ($_.Group.Status | Select-Object -Unique).Count -gt 1 -or
    (($_.Group | Where-Object Detail) -and (($_.Group.Detail | Select-Object -Unique).Count -gt 1))
}
if ($parity) {
    Write-Host ''
    Write-Host '  跨實作行為差異（parity）：' -ForegroundColor Yellow
    foreach ($p in $parity) {
        Write-Host ("   {0} {1}" -f $p.Name, $p.Group[0].Name) -ForegroundColor Yellow
        foreach ($row in $p.Group) {
            Write-Host ("        {0,-4} {1}  {2}" -f $row.Impl, $row.Status, $row.Detail) -ForegroundColor DarkYellow
        }
    }
}

Write-Host ''
Write-Host ("  總計 {0} 案例：{1} PASS / {2} FAIL" -f $script:Results.Count, $pass.Count, $fails.Count) `
    -ForegroundColor $(if ($fails.Count) { 'Red' } else { 'Green' })
Write-Host ''

exit $(if ($fails.Count) { 1 } else { 0 })
