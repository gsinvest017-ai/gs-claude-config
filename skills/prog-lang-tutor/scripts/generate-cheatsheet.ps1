# generate-cheatsheet.ps1
# ------------------------------------------------------------
# Convert data/<slug>/knowledge.json into a human-readable
# Markdown cheatsheet (Concept / Usage / Caveats per category).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File generate-cheatsheet.ps1 -RepoSlug <slug> [-Force]
#
# Output:
#   data/<slug>/cheatsheet.md
#
# Skips regeneration when cheatsheet.md is newer than knowledge.json
# (unless -Force is passed).
# ------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoSlug,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $scriptDir
$dataDir   = Join-Path $skillRoot "data\$RepoSlug"
$kbPath    = Join-Path $dataDir 'knowledge.json'
$outPath   = Join-Path $dataDir 'cheatsheet.md'

if (-not (Test-Path $kbPath)) {
    Write-Error "knowledge.json not found at: $kbPath`nRun '/prog-lang-tutor analyze' first."
    exit 1
}

# Skip if up to date
if ((Test-Path $outPath) -and -not $Force) {
    $kbTime  = (Get-Item $kbPath).LastWriteTime
    $outTime = (Get-Item $outPath).LastWriteTime
    if ($outTime -ge $kbTime) {
        Write-Host "Cheatsheet is up to date (knowledge.json mtime <= cheatsheet.md mtime)."
        Write-Host "Path: $outPath"
        Write-Host "Pass -Force to regenerate anyway."
        exit 0
    }
}

$kb = Get-Content -Path $kbPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $kb.points -or $kb.points.Count -eq 0) {
    Write-Error "knowledge.json has no 'points' entries."
    exit 1
}

# Helpers --------------------------------------------------------------------

function Slug([string]$s) {
    return ($s.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Esc-Md([string]$s) {
    if ($null -eq $s) { return '' }
    return $s
}

# Group by category, preserve original order within category
$byCategory = [ordered]@{}
foreach ($p in $kb.points) {
    $cat = if ($p.category) { $p.category } else { 'misc' }
    if (-not $byCategory.Contains($cat)) {
        $byCategory[$cat] = @()
    }
    $byCategory[$cat] += $p
}

# Sort categories by # of points desc, then alphabetically
$sortedCats = $byCategory.Keys | Sort-Object @{Expression = { $byCategory[$_].Count }; Descending = $true }, @{Expression = { $_ }}

# Build markdown ------------------------------------------------------------

$sb = [System.Text.StringBuilder]::new()
$lang = if ($kb.language) { $kb.language } else { 'code' }
$langTitle = (Get-Culture).TextInfo.ToTitleCase($lang.ToString())
$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

[void]$sb.AppendLine("# $langTitle Cheatsheet — $RepoSlug")
[void]$sb.AppendLine()
[void]$sb.AppendLine("> 自動產生於 $generated。")
[void]$sb.AppendLine("> 共 **$($kb.points.Count)** 個知識點、$($byCategory.Count) 個分類。")
if ($kb.repo_path) {
    [void]$sb.AppendLine("> Repo: ``$($kb.repo_path)``")
}
if ($kb.language_share) {
    [void]$sb.AppendLine("> 語言佔比：files $($kb.language_share.files)、lines $($kb.language_share.lines)")
}
[void]$sb.AppendLine("> Source: ``data/$RepoSlug/knowledge.json``")
[void]$sb.AppendLine()

# ---- Table of Contents ----
[void]$sb.AppendLine("## Table of Contents")
[void]$sb.AppendLine()
foreach ($cat in $sortedCats) {
    $count = $byCategory[$cat].Count
    $anchor = Slug $cat
    [void]$sb.AppendLine("- [$cat](#$anchor) ($count)")
}
[void]$sb.AppendLine("- [Quick reference index](#quick-reference-index)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()

# ---- Sections per category ----
foreach ($cat in $sortedCats) {
    [void]$sb.AppendLine("## $cat")
    [void]$sb.AppendLine()

    foreach ($p in $byCategory[$cat]) {
        $diff = if ($p.difficulty) { $p.difficulty } else { '?' }
        [void]$sb.AppendLine("### $($p.topic)  *(difficulty: $diff/5)*")
        [void]$sb.AppendLine()

        # Concept
        [void]$sb.AppendLine("**Concept**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((Esc-Md $p.explanation))
        [void]$sb.AppendLine()

        # Usage
        [void]$sb.AppendLine("**Usage**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("``````$lang")
        [void]$sb.AppendLine($p.code_example)
        [void]$sb.AppendLine("``````")
        if ($p.where_used -and $p.where_used.Count -gt 0) {
            $first = $p.where_used[0]
            $more = ''
            if ($p.where_used.Count -gt 1) {
                $more = " (+$($p.where_used.Count - 1) more)"
            }
            [void]$sb.AppendLine("*Used at:* ``$first``$more")
            [void]$sb.AppendLine()
        }

        # Caveats
        [void]$sb.AppendLine("**Caveats / Why it matters**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((Esc-Md $p.why_important))
        [void]$sb.AppendLine()
        if ($p.quiz -and $p.quiz.answer) {
            [void]$sb.AppendLine("<details><summary>常見踩雷（展開）</summary>")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine((Esc-Md $p.quiz.answer))
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("</details>")
            [void]$sb.AppendLine()
        }

        [void]$sb.AppendLine("---")
        [void]$sb.AppendLine()
    }
}

# ---- Quick reference index ----
[void]$sb.AppendLine("## Quick reference index")
[void]$sb.AppendLine()
[void]$sb.AppendLine("| Topic | Category | Difficulty | Used at |")
[void]$sb.AppendLine("|---|---|---:|---|")
$sortedPoints = $kb.points | Sort-Object topic
foreach ($p in $sortedPoints) {
    $cat = if ($p.category) { $p.category } else { 'misc' }
    $diff = if ($p.difficulty) { $p.difficulty } else { '?' }
    $loc = if ($p.where_used -and $p.where_used.Count -gt 0) { '`' + $p.where_used[0] + '`' } else { '—' }
    $topicEsc = $p.topic -replace '\|', '\|'
    [void]$sb.AppendLine("| $topicEsc | $cat | $diff | $loc |")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("---")
[void]$sb.AppendLine()
[void]$sb.AppendLine("_Regenerate with:_ ``powershell -File scripts/generate-cheatsheet.ps1 -RepoSlug $RepoSlug -Force``")

# Write file ----------------------------------------------------------------
$content = $sb.ToString()
[System.IO.File]::WriteAllText($outPath, $content, [System.Text.UTF8Encoding]::new($false))

$bytes = (Get-Item $outPath).Length
$kb_kb = [math]::Round($bytes / 1024, 1)

Write-Host "Generated cheatsheet:"
Write-Host "  Path:      $outPath"
Write-Host "  Sections:  $($byCategory.Count) categories"
Write-Host "  Points:    $($kb.points.Count)"
Write-Host "  Size:      $kb_kb KB"
Write-Host ""
Write-Host "Open in VS Code: code `"$outPath`""
