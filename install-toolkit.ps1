# ============================================================================
# gs-claude-toolkit - consumer installer (Windows)
# ============================================================================
# One-click install of the skills / commands / agents / autopilot hooks into
# %USERPROFILE%\.claude\ for *anyone*. This is NOT the author's cross-machine
# sync (that's install.ps1, which symlinks the author's personal CLAUDE.md).
#
# Remote one-liner (copy mode, no Dev Mode needed):
#   irm https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-toolkit.ps1 | iex
#
# With flags over the pipe:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-toolkit.ps1))) -NoHooks
#
# From a local clone:
#   .\install-toolkit.ps1 [-Link] [-NoHooks] [-Dir <path>] [-RepoUrl <url>] [-Branch <name>]
#
# Existing same-named items in ~/.claude/{commands,skills,agents} are backed up
# first; settings.json is merged in-place (never clobbered); your own CLAUDE.md
# is never touched.
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Link,
    [switch]$NoHooks,
    [string]$Dir,
    [string]$RepoUrl = $(if ($env:GS_REPO_URL) { $env:GS_REPO_URL } else { 'https://github.com/gsinvest017-ai/gs-claude-config.git' }),
    [string]$Branch  = $(if ($env:GS_BRANCH)  { $env:GS_BRANCH }  else { 'main' })
)

$ErrorActionPreference = 'Stop'

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$Ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ClaudeDir "backups\toolkit-$Ts"

function Test-Checkout([string]$p) {
    return ($p -and (Test-Path (Join-Path $p 'skills')) -and (Test-Path (Join-Path $p '.claude-plugin\plugin.json')))
}

# --- locate the repo: local checkout or clone -------------------------------
$RepoDir = $Dir
if (-not $RepoDir -and $PSScriptRoot -and (Test-Checkout $PSScriptRoot)) {
    $RepoDir = $PSScriptRoot
}
if (-not $RepoDir) {
    $Cache = if ($env:GS_CACHE) { $env:GS_CACHE } else { Join-Path $env:LOCALAPPDATA 'gs-claude-toolkit' }
    if (Test-Checkout $Cache) {
        Write-Host "==> Updating cached checkout at $Cache"
        git -C $Cache fetch --depth 1 origin $Branch -q; git -C $Cache reset --hard "origin/$Branch" -q
    } else {
        Write-Host "==> Cloning $RepoUrl ($Branch) -> $Cache"
        if (Test-Path $Cache) { Remove-Item -Recurse -Force $Cache }
        git clone --depth 1 --branch $Branch $RepoUrl $Cache -q
    }
    $RepoDir = $Cache
}

if (-not (Test-Checkout $RepoDir)) { throw "$RepoDir is not a gs-claude-config checkout" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "'node' not found. Claude Code bundles Node; ensure it's on PATH (the autopilot hook needs it)."
}

$Mode = if ($Link) { 'link' } else { 'copy' }
Write-Host "==> Installing from $RepoDir  (mode: $Mode)"
if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Path $ClaudeDir | Out-Null }

# --- place one item, backing up any pre-existing target --------------------
function Place([string]$src, [string]$dstDir) {
    $name = Split-Path -Leaf $src
    $dst  = Join-Path $dstDir $name
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    if (Test-Path $dst) {
        $bg = Join-Path $BackupDir (Split-Path -Leaf $dstDir)
        if (-not (Test-Path $bg)) { New-Item -ItemType Directory -Path $bg -Force | Out-Null }
        Move-Item -LiteralPath $dst -Destination $bg -Force
    }
    if ($Mode -eq 'link') {
        # mklink honors Dev Mode for user-scope symlinks; New-Item silently
        # fails without admin even with Dev Mode on.
        if (Test-Path $src -PathType Container) { cmd /c mklink /D "`"$dst`"" "`"$src`"" | Out-Null }
        else { cmd /c mklink "`"$dst`"" "`"$src`"" | Out-Null }
    } else {
        Copy-Item -Recurse -Force $src $dst
    }
}

function Install-Group([string]$group) {
    $srcDir = Join-Path $RepoDir $group
    if (-not (Test-Path $srcDir)) { return }
    $n = 0
    foreach ($item in Get-ChildItem -Force $srcDir) {
        Place $item.FullName (Join-Path $ClaudeDir $group)
        $n++
    }
    Write-Host "  $group`: $n item(s)"
}

Install-Group 'commands'
Install-Group 'skills'
Install-Group 'agents'

# --- hooks + settings -------------------------------------------------------
if (-not $NoHooks) {
    Write-Host '==> Autopilot hook + settings.json'
    $HooksDir = Join-Path $ClaudeDir 'hooks'
    if (-not (Test-Path $HooksDir)) { New-Item -ItemType Directory -Path $HooksDir | Out-Null }
    Copy-Item -Force (Join-Path $RepoDir 'hooks\autopilot.mjs') (Join-Path $HooksDir 'autopilot.mjs')
    $HookMjs = (Join-Path $HooksDir 'autopilot.mjs')
    $HookCmd = 'node "' + $HookMjs + '"'
    $Settings = Join-Path $ClaudeDir 'settings.json'
    if (Test-Path $Settings) {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        Copy-Item -Force $Settings (Join-Path $BackupDir 'settings.json.bak')
    }
    node (Join-Path $RepoDir 'scripts\merge-settings.mjs') $Settings $HookCmd 60
} else {
    Write-Host '==> Skipping hooks (-NoHooks)'
}

Write-Host ''
if (Test-Path $BackupDir) { Write-Host "Backed up pre-existing items -> $BackupDir" }
Write-Host 'Done. Restart Claude Code, then verify:'
Write-Host '  Get-ChildItem ~/.claude/skills | Select-Object -First 5'
Write-Host '  /autopilot status'
Write-Host ''
Write-Host "Uninstall anytime:  $RepoDir\uninstall-toolkit.ps1"
