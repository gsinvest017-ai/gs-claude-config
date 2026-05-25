#requires -Version 7.0
<#
.SYNOPSIS
    Mine ~/.claude/projects/*.jsonl for development-useful patterns.

.DESCRIPTION
    Aggregates tool usage, file heatmap, Bash commands, recurring errors,
    and token hotspots from Claude Code session JSONL files. Outputs a
    Markdown report; does not modify any file or settings.

.PARAMETER Days
    Only scan sessions modified within the last N days. Default 7.

.PARAMETER Top
    How many rows per ranking. Default 20.

.PARAMETER Section
    One of: tools, files, bash, errors, tokens, all (default).

.PARAMETER ProjectFilter
    Substring match against the sanitized-cwd directory name (e.g. 'gs-strategy').

.PARAMETER Repo
    Repo-scoped mode. Pass an absolute path, or 'auto' to resolve the git
    top-level from the current working directory. When set, only messages
    whose `cwd` is at or under this path are included, and the report header
    plus repo-specific sections (untracked) become available.

.PARAMETER OutFile
    Optional path to also write the report to disk (UTF-8, no BOM).

.PARAMETER ProjectsRoot
    Default: $env:USERPROFILE\.claude\projects
#>
param(
    [int]$Days = 7,
    [int]$Top = 20,
    [ValidateSet('tools','files','bash','errors','tokens','prompts','subagents','untracked','all')]
    [string]$Section = 'all',
    [string]$ProjectFilter = '',
    [string]$Repo = '',
    [string]$OutFile = '',
    [string]$ProjectsRoot = (Join-Path $env:USERPROFILE '.claude\projects')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProjectsRoot)) {
    Write-Output "ProjectsRoot not found: $ProjectsRoot"
    return
}

if ($Repo -eq 'auto') {
    $here = (Get-Location).Path
    $gitRoot = $null
    try { $gitRoot = (& git -C $here rev-parse --show-toplevel 2>$null) } catch {}
    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        $Repo = ($gitRoot | Out-String).Trim() -replace '/', '\'
    } else {
        $Repo = $here
    }
}
if ($Repo) {
    $resolved = (Resolve-Path -LiteralPath $Repo -ErrorAction SilentlyContinue)
    if ($resolved) { $Repo = $resolved.Path }
    $Repo = $Repo.TrimEnd('\','/')
}

$cutoff = (Get-Date).AddDays(-$Days)
$sessions = Get-ChildItem -Path $ProjectsRoot -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $cutoff }

if ($ProjectFilter) {
    $sessions = $sessions | Where-Object { $_.Directory.Name -like "*$ProjectFilter*" }
}

if (-not $sessions -or $sessions.Count -eq 0) {
    Write-Output "No sessions found in last $Days days under $ProjectsRoot"
    if ($ProjectFilter) { Write-Output "(filter: '$ProjectFilter')" }
    return
}

$toolCounts    = @{}
$filePaths     = @{}
$bashCmds      = @{}
$errorPatterns = @{}
$sessionStats  = [System.Collections.Generic.List[object]]::new()
$promptLog     = [System.Collections.Generic.List[object]]::new()
$agentCalls    = [ordered]@{}
$totalMessages = 0

foreach ($s in $sessions) {
    $inTok = 0; $outTok = 0; $cacheReadTok = 0; $cacheCreateTok = 0
    $cwd = $null; $model = $null

    foreach ($line in (Get-Content -LiteralPath $s.FullName -Encoding utf8 -ErrorAction SilentlyContinue)) {
        $totalMessages++
        if (-not $line) { continue }
        try { $msg = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }

        if ($Repo -and $msg.cwd) {
            $msgCwd = ([string]$msg.cwd).TrimEnd('\','/')
            if ($msgCwd -ne $Repo -and -not $msgCwd.StartsWith($Repo + '\', [StringComparison]::OrdinalIgnoreCase) -and -not $msgCwd.StartsWith($Repo + '/', [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }

        if (-not $cwd -and $msg.cwd) { $cwd = $msg.cwd }

        if ($msg.type -eq 'assistant') {
            $u = $msg.message.usage
            if ($u) {
                if ($u.input_tokens)               { $inTok          += [int]$u.input_tokens }
                if ($u.output_tokens)              { $outTok         += [int]$u.output_tokens }
                if ($u.cache_read_input_tokens)    { $cacheReadTok   += [int]$u.cache_read_input_tokens }
                if ($u.cache_creation_input_tokens){ $cacheCreateTok += [int]$u.cache_creation_input_tokens }
                if (-not $model -and $msg.message.model) { $model = $msg.message.model }
            }

            $contents = @($msg.message.content)
            foreach ($c in $contents) {
                if ($c.type -ne 'tool_use') { continue }
                $name = $c.name
                if (-not $name) { continue }
                if ($toolCounts.ContainsKey($name)) { $toolCounts[$name]++ } else { $toolCounts[$name] = 1 }

                if ($name -in 'Read','Edit','Write','MultiEdit','NotebookEdit') {
                    $fp = $c.input.file_path
                    if ($fp) {
                        if (-not $filePaths.ContainsKey($fp)) {
                            $filePaths[$fp] = @{Read=0; Edit=0; Write=0}
                        }
                        switch ($name) {
                            'Read'         { $filePaths[$fp].Read  += 1 }
                            'Edit'         { $filePaths[$fp].Edit  += 1 }
                            'MultiEdit'    { $filePaths[$fp].Edit  += 1 }
                            'NotebookEdit' { $filePaths[$fp].Edit  += 1 }
                            'Write'        { $filePaths[$fp].Write += 1 }
                        }
                    }
                }

                if ($name -eq 'Bash' -and $c.input.command) {
                    $cmd = ([string]$c.input.command).Trim()
                    if ($cmd.Length -gt 200) { $cmd = $cmd.Substring(0,200) + '...' }
                    if ($bashCmds.ContainsKey($cmd)) { $bashCmds[$cmd]++ } else { $bashCmds[$cmd] = 1 }
                }

                if ($name -eq 'Agent' -and $c.id) {
                    $ts = $null
                    if ($msg.timestamp) { try { $ts = [datetime]$msg.timestamp } catch {} }
                    $agentCalls[[string]$c.id] = [PSCustomObject]@{
                        Id          = [string]$c.id
                        Timestamp   = $ts
                        Session     = $s.BaseName
                        Cwd         = $msg.cwd
                        SubagentType= [string]$c.input.subagent_type
                        Description = [string]$c.input.description
                        PromptHead  = if ($c.input.prompt) { ([string]$c.input.prompt).Substring(0, [Math]::Min(160, ([string]$c.input.prompt).Length)) } else { '' }
                        ResultHead  = ''
                    }
                }
            }
        }
        elseif ($msg.type -eq 'user' -and $msg.message -and $msg.message.content -is [string]) {
            $txt = ([string]$msg.message.content).Trim()
            $skipPrefixes = @(
                '<command-message>', '<command-name>', '<command-args>',
                '<local-command-stdout>', '<local-command-caveat>',
                '<bash-input>', '<bash-stdout>', '<bash-stderr>',
                '<system-reminder>'
            )
            $isWrapper = $false
            foreach ($p in $skipPrefixes) { if ($txt.StartsWith($p)) { $isWrapper = $true; break } }
            if ($txt -and -not $isWrapper) {
                $ts = $null
                if ($msg.timestamp) { try { $ts = [datetime]$msg.timestamp } catch {} }
                $promptLog.Add([PSCustomObject]@{
                    Timestamp = $ts
                    Session   = $s.BaseName
                    Cwd       = $msg.cwd
                    Prompt    = $txt
                })
            }
        }
        elseif ($msg.type -eq 'user' -and $msg.message -and $msg.message.content -is [array]) {
            foreach ($c in @($msg.message.content)) {
                if ($c.type -eq 'tool_result' -and $c.tool_use_id -and $agentCalls.Contains([string]$c.tool_use_id)) {
                    $text = ''
                    if ($c.content -is [string]) { $text = $c.content }
                    elseif ($c.content) {
                        $first = @($c.content)[0]
                        if ($first.text) { $text = [string]$first.text }
                    }
                    if ($text) {
                        $clean = ($text -replace '\s+',' ').Trim()
                        if ($clean.Length -gt 200) { $clean = $clean.Substring(0,200) + '…' }
                        $agentCalls[[string]$c.tool_use_id].ResultHead = $clean
                    }
                }
                if ($c.type -eq 'tool_result' -and $c.is_error -eq $true) {
                    $text = ''
                    if ($c.content -is [string]) {
                        $text = $c.content
                    } elseif ($c.content) {
                        $first = @($c.content)[0]
                        if ($first.text) { $text = [string]$first.text }
                    }
                    if ($text) {
                        $sig = ($text -replace '\s+',' ').Trim()
                        if ($sig.Length -gt 120) { $sig = $sig.Substring(0,120) }
                        if ($errorPatterns.ContainsKey($sig)) { $errorPatterns[$sig]++ } else { $errorPatterns[$sig] = 1 }
                    }
                }
            }
        }
    }

    $sessionStats.Add([PSCustomObject]@{
        Session     = $s.BaseName
        Date        = $s.LastWriteTime
        Cwd         = $cwd
        Model       = $model
        InputTok    = $inTok
        OutputTok   = $outTok
        CacheRead   = $cacheReadTok
        CacheCreate = $cacheCreateTok
        Total       = $inTok + $outTok
    })
}

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine("# Claude Code Insights — last $Days days")
$null = $sb.AppendLine("")
$header = "Scanned **$($sessions.Count) sessions** / **$totalMessages messages** under ``$ProjectsRoot``"
if ($ProjectFilter) { $header += " (project filter: ``$ProjectFilter``)" }
if ($Repo)          { $header += " (repo: ``$Repo``)" }
$null = $sb.AppendLine($header)
$null = $sb.AppendLine("")

function Add-MdSection {
    param([string]$Title, [scriptblock]$Body)
    $null = $sb.AppendLine("## $Title")
    $null = $sb.AppendLine("")
    foreach ($line in (& $Body)) { $null = $sb.AppendLine([string]$line) }
    $null = $sb.AppendLine("")
}

if ($Section -in 'tools','all') {
    Add-MdSection 'Tool frequency' {
        if ($toolCounts.Count -eq 0) { '_No tool calls in scanned sessions._'; return }
        '| Tool | Count |'
        '|------|------:|'
        $toolCounts.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $Top |
            ForEach-Object { "| $($_.Key) | $($_.Value) |" }
    }
}

if ($Section -in 'files','all') {
    Add-MdSection "File heatmap (top $Top)" {
        if ($filePaths.Count -eq 0) { '_No file operations in scanned sessions._'; return }
        '| File | Read | Edit | Write |'
        '|------|-----:|-----:|------:|'
        $filePaths.GetEnumerator() |
            Sort-Object { $_.Value.Read + $_.Value.Edit + $_.Value.Write } -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $f = $_.Key
                $v = $_.Value
                "| ``$f`` | $($v.Read) | $($v.Edit) | $($v.Write) |"
            }
    }
}

if ($Section -in 'bash','all') {
    Add-MdSection "Bash commands (top $Top by frequency)" {
        if ($bashCmds.Count -eq 0) { '_No Bash invocations in scanned sessions._'; return }
        '| Count | Command |'
        '|------:|---------|'
        $bashCmds.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $c = $_.Key -replace '\|','\|'
                "| $($_.Value) | ``$c`` |"
            }
    }
}

if ($Section -in 'errors','all') {
    Add-MdSection "Recurring tool errors (top $Top)" {
        if ($errorPatterns.Count -eq 0) { '_No tool errors detected in scanned sessions._'; return }
        '| Count | Error signature |'
        '|------:|-----------------|'
        $errorPatterns.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $sig = $_.Key -replace '\|','\|'
                "| $($_.Value) | $sig |"
            }
    }
}

if ($Section -in 'prompts','all') {
    Add-MdSection "Recent prompts (top $Top, newest first)" {
        if ($promptLog.Count -eq 0) { '_No user prompts captured._'; return }
        '| When | Session | Prompt |'
        '|------|---------|--------|'
        $promptLog |
            Where-Object { $_.Timestamp } |
            Sort-Object Timestamp -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $shortId = $_.Session.Substring(0, [Math]::Min(8, $_.Session.Length))
                $dateStr = $_.Timestamp.ToString('yyyy-MM-dd HH:mm')
                $p = $_.Prompt -replace '\s+',' '
                if ($p.Length -gt 140) { $p = $p.Substring(0,140) + '…' }
                $p = $p -replace '\|','\|'
                "| $dateStr | ``$shortId`` | $p |"
            }
    }
}

if ($Section -in 'tokens','all') {
    Add-MdSection "Token hotspots (top $Top sessions by input+output)" {
        if ($sessionStats.Count -eq 0) { '_No assistant token usage recorded._'; return }
        '| Session | Date | Cwd | Model | InputTok | OutputTok | CacheRead |'
        '|---------|------|-----|-------|---------:|----------:|----------:|'
        $sessionStats |
            Sort-Object Total -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $shortId = $_.Session.Substring(0, [Math]::Min(8, $_.Session.Length))
                $dateStr = $_.Date.ToString('yyyy-MM-dd HH:mm')
                $cwdStr  = if ($_.Cwd)   { $_.Cwd }   else { '(unknown)' }
                $mdlStr  = if ($_.Model) { $_.Model } else { '-' }
                "| ``$shortId`` | $dateStr | ``$cwdStr`` | $mdlStr | $($_.InputTok) | $($_.OutputTok) | $($_.CacheRead) |"
            }
    }
}

if ($Section -in 'subagents','all') {
    Add-MdSection "Subagent calls (top $Top, newest first)" {
        if ($agentCalls.Count -eq 0) { '_No Agent tool_use invocations in scope._'; return }
        '| When | Session | Subagent | Description | Result preview |'
        '|------|---------|----------|-------------|----------------|'
        $agentCalls.Values |
            Where-Object { $_.Timestamp } |
            Sort-Object Timestamp -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                $shortId = $_.Session.Substring(0, [Math]::Min(8, $_.Session.Length))
                $dateStr = $_.Timestamp.ToString('yyyy-MM-dd HH:mm')
                $sub     = if ($_.SubagentType) { $_.SubagentType } else { '(default)' }
                $desc    = ($_.Description -replace '\s+',' ') -replace '\|','\|'
                if ($desc.Length -gt 60) { $desc = $desc.Substring(0,60) + '…' }
                $res     = ($_.ResultHead -replace '\|','\|')
                if (-not $res) { $res = '_(no result captured)_' }
                "| $dateStr | ``$shortId`` | $sub | $desc | $res |"
            }
    }
}

if ($Section -in 'untracked','all') {
    Add-MdSection "Files Claude touched vs git state" {
        if (-not $Repo) {
            '_Requires `-Repo <path>` (or `-Repo auto`) — needs a real git repo to cross-reference._'
            return
        }
        $gitOk = $false
        try { & git -C $Repo rev-parse --is-inside-work-tree *>$null; if ($LASTEXITCODE -eq 0) { $gitOk = $true } } catch {}
        if (-not $gitOk) {
            "_$Repo is not a git work tree; skipping._"
            return
        }
        $statusLines = & git -C $Repo status --porcelain 2>$null
        $dirty = @{}
        foreach ($ln in $statusLines) {
            if (-not $ln) { continue }
            $code = $ln.Substring(0,2)
            $rel  = $ln.Substring(3)
            if ($rel.Contains(' -> ')) { $rel = ($rel -split ' -> ')[-1] }
            $rel = $rel.Trim('"')
            $abs = (Join-Path $Repo $rel) -replace '/', '\'
            $dirty[$abs] = $code.Trim()
        }
        $touchedInRepo = $filePaths.GetEnumerator() | Where-Object {
            $_.Key -like "$Repo\*" -or $_.Key -like "$Repo/*"
        }
        if (-not $touchedInRepo) {
            '_No files in this repo were touched by Claude in scanned sessions._'
            return
        }
        $rows = foreach ($e in $touchedInRepo) {
            $abs = $e.Key
            $v   = $e.Value
            $st  = if ($dirty.ContainsKey($abs)) { $dirty[$abs] } else { '' }
            [PSCustomObject]@{
                File   = $abs
                Status = $st
                Read   = $v.Read
                Edit   = $v.Edit
                Write  = $v.Write
                Total  = $v.Read + $v.Edit + $v.Write
                Dirty  = [bool]$st
            }
        }
        $dirtyRows = $rows | Where-Object Dirty | Sort-Object Total -Descending | Select-Object -First $Top
        if (-not $dirtyRows) {
            '_All touched files are committed and tracked. ✓_'
            return
        }
        '_Status codes: `??`=untracked, `M`=modified, `A`=added, `D`=deleted, `R`=renamed._'
        ''
        '| Status | File | Read | Edit | Write |'
        '|--------|------|-----:|-----:|------:|'
        foreach ($r in $dirtyRows) {
            "| ``$($r.Status)`` | ``$($r.File)`` | $($r.Read) | $($r.Edit) | $($r.Write) |"
        }
    }
}

$report = $sb.ToString()
Write-Output $report

if ($OutFile) {
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $report | Set-Content -Path $OutFile -Encoding utf8
    Write-Output ""
    Write-Output "[Saved to $OutFile]"
}
