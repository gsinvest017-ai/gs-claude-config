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

.PARAMETER OutFile
    Optional path to also write the report to disk (UTF-8, no BOM).

.PARAMETER ProjectsRoot
    Default: $env:USERPROFILE\.claude\projects
#>
param(
    [int]$Days = 7,
    [int]$Top = 20,
    [ValidateSet('tools','files','bash','errors','tokens','all')]
    [string]$Section = 'all',
    [string]$ProjectFilter = '',
    [string]$OutFile = '',
    [string]$ProjectsRoot = (Join-Path $env:USERPROFILE '.claude\projects')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProjectsRoot)) {
    Write-Output "ProjectsRoot not found: $ProjectsRoot"
    return
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
$totalMessages = 0

foreach ($s in $sessions) {
    $inTok = 0; $outTok = 0; $cacheReadTok = 0; $cacheCreateTok = 0
    $cwd = $null; $model = $null

    foreach ($line in (Get-Content -LiteralPath $s.FullName -Encoding utf8 -ErrorAction SilentlyContinue)) {
        $totalMessages++
        if (-not $line) { continue }
        try { $msg = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }

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
            }
        }
        elseif ($msg.type -eq 'user' -and $msg.message -and $msg.message.content -is [array]) {
            foreach ($c in @($msg.message.content)) {
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
if ($ProjectFilter) { $header += " (filtered: ``$ProjectFilter``)" }
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

$report = $sb.ToString()
Write-Output $report

if ($OutFile) {
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $report | Set-Content -Path $OutFile -Encoding utf8
    Write-Output ""
    Write-Output "[Saved to $OutFile]"
}
