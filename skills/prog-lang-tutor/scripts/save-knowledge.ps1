# save-knowledge.ps1
# Persists a knowledge.json bundle produced by /prog-lang-tutor analyze
# into the canonical data dir under ~/.claude/skills/prog-lang-tutor/data/<slug>/.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File save-knowledge.ps1 `
#     -RepoPath "C:\Users\User\autogo" `
#     -Language "python" `
#     -KnowledgeJsonPath "C:\Temp\autogo-knowledge.json"
#
# Behavior:
#   - Derives slug from leaf of RepoPath (lowercase, spaces -> "_").
#   - Creates data/<slug>/ if missing.
#   - Validates the incoming JSON parses + has a "knowledge_points" array.
#   - Stamps repo_path, language, analyzed_at (ISO 8601 UTC) into the JSON.
#   - Writes to data/<slug>/knowledge.json (UTF-8, no BOM).
#   - Prints the final path so the caller can show it to the user.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $RepoPath,
    [Parameter(Mandatory = $true)] [string] $Language,
    [Parameter(Mandatory = $true)] [string] $KnowledgeJsonPath,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Error "RepoPath does not exist: $RepoPath"
    exit 2
}
if (-not (Test-Path -LiteralPath $KnowledgeJsonPath)) {
    Write-Error "KnowledgeJsonPath does not exist: $KnowledgeJsonPath"
    exit 2
}

$resolvedRepo = (Resolve-Path -LiteralPath $RepoPath).Path
$leaf = Split-Path -Leaf $resolvedRepo
$slug = ($leaf -replace '\s+', '_').ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($slug)) {
    Write-Error "Could not derive slug from RepoPath: $RepoPath"
    exit 2
}

$dataRoot = Join-Path $PSScriptRoot '..\data'
$dataRoot = (Resolve-Path -LiteralPath $dataRoot -ErrorAction SilentlyContinue).Path
if (-not $dataRoot) {
    $dataRoot = Join-Path $PSScriptRoot '..\data'
    New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    $dataRoot = (Resolve-Path -LiteralPath $dataRoot).Path
}
$slugDir = Join-Path $dataRoot $slug
if (-not (Test-Path -LiteralPath $slugDir)) {
    New-Item -ItemType Directory -Path $slugDir | Out-Null
}

$targetPath = Join-Path $slugDir 'knowledge.json'

if ((Test-Path -LiteralPath $targetPath) -and (-not $Force)) {
    Write-Host "knowledge.json already exists at: $targetPath"
    Write-Host "Re-run with -Force to overwrite, or use a different RepoPath."
    exit 3
}

$rawJson = Get-Content -LiteralPath $KnowledgeJsonPath -Raw -Encoding UTF8
try {
    $parsed = $rawJson | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Input is not valid JSON: $($_.Exception.Message)"
    exit 4
}

if (-not $parsed.PSObject.Properties.Name -contains 'knowledge_points') {
    Write-Error "Input JSON missing required field: knowledge_points (array)"
    exit 4
}
if ($parsed.knowledge_points -isnot [System.Collections.IEnumerable]) {
    Write-Error "knowledge_points must be an array"
    exit 4
}

$nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$parsed | Add-Member -Force -NotePropertyName 'repo_path'   -NotePropertyValue $resolvedRepo
$parsed | Add-Member -Force -NotePropertyName 'repo_slug'   -NotePropertyValue $slug
$parsed | Add-Member -Force -NotePropertyName 'language'    -NotePropertyValue $Language
$parsed | Add-Member -Force -NotePropertyName 'analyzed_at' -NotePropertyValue $nowUtc

$finalJson = $parsed | ConvertTo-Json -Depth 32

[System.IO.File]::WriteAllText($targetPath, $finalJson, [System.Text.UTF8Encoding]::new($false))

$count = @($parsed.knowledge_points).Count
Write-Host "Saved $count knowledge points to:"
Write-Host "  $targetPath"
Write-Host ""
Write-Host "Next: /prog-lang-tutor schedule 30m $slug  # set up periodic popup review"
