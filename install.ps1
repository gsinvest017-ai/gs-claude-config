# Install gs-claude-config into $env:USERPROFILE\.claude\ via symlinks.
# Windows-native counterpart to install.sh.
#
# Idempotent. If ~/.claude/{commands,skills,CLAUDE.md} already exist as
# regular files/dirs (not symlinks), they get moved to ~/.claude/backups/
# with a timestamp suffix before the symlink is created.
#
# settings.json is *not* symlinked. It gets rendered from
# settings.template.json (with __HOME__ -> $HOME) only if no settings.json
# is present yet — existing settings are never overwritten.
#
# Symlink creation note (per user memory):
#   New-Item -ItemType SymbolicLink silently fails without admin even with
#   Dev Mode on. We use `cmd /c mklink` instead, which honors Dev Mode for
#   user-scope symlinks. Requires Windows 10 1703+ with Developer Mode
#   enabled (Settings -> Privacy & security -> For developers).

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ClaudeDir "backups\install-$Timestamp"

if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir | Out-Null
}

# --- Sibling repo: quant-research-skill ---
# Two skills (quant-researcher, review-strategy) are relative symlinks
# pointing into this sibling. Clone it on a fresh machine so the symlinks
# resolve. Edit $QRSRemote if you fork it.
$QRSRemote = 'https://github.com/gsinvest017-ai/quant-research-skill.git'
$QRSDir    = Join-Path $env:USERPROFILE 'quant-research-skill'
if (-not (Test-Path $QRSDir)) {
    Write-Host '==> Cloning sibling repo quant-research-skill'
    # core.symlinks=true matters on Windows so checked-in symlinks survive
    git -c core.symlinks=true clone $QRSRemote $QRSDir
}

function Backup-IfExists {
    param([string]$Target)

    if (-not (Test-Path $Target)) { return }

    # If it's already a symlink (file or dir), just remove it.
    $item = Get-Item -LiteralPath $Target -Force
    if ($item.LinkType -eq 'SymbolicLink') {
        Remove-Item -LiteralPath $Target -Force -Recurse
        return
    }

    if (-not (Test-Path $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    Move-Item -LiteralPath $Target -Destination $script:BackupDir -Force
    Write-Host "  backed up existing $(Split-Path -Leaf $Target) -> $script:BackupDir"
}

function New-RepoSymlink {
    param(
        [string]$Source,   # absolute path inside repo
        [string]$Dest      # absolute path under ~/.claude/
    )

    Backup-IfExists -Target $Dest

    # cmd /c mklink chosen over New-Item: New-Item -ItemType SymbolicLink
    # silently fails without admin even with Dev Mode on.
    if (Test-Path $Source -PathType Container) {
        cmd /c mklink /D "`"$Dest`"" "`"$Source`"" | Out-Null
    } else {
        cmd /c mklink "`"$Dest`"" "`"$Source`"" | Out-Null
    }
    Write-Host "  linked $(Split-Path -Leaf $Dest) -> $Source"
}

Write-Host "==> Linking commands/, skills/, CLAUDE.md into $ClaudeDir"
New-RepoSymlink -Source (Join-Path $RepoDir 'commands')  -Dest (Join-Path $ClaudeDir 'commands')
New-RepoSymlink -Source (Join-Path $RepoDir 'skills')    -Dest (Join-Path $ClaudeDir 'skills')
New-RepoSymlink -Source (Join-Path $RepoDir 'CLAUDE.md') -Dest (Join-Path $ClaudeDir 'CLAUDE.md')

Write-Host '==> settings.json'
$SettingsTarget = Join-Path $ClaudeDir 'settings.json'
if (Test-Path $SettingsTarget) {
    Write-Host '  exists already - left untouched. Diff against settings.template.json manually if you want to merge new keys.'
} else {
    $template = Get-Content (Join-Path $RepoDir 'settings.template.json') -Raw
    $rendered = $template -replace '__HOME__', $env:USERPROFILE.Replace('\', '/')
    Set-Content -Path $SettingsTarget -Value $rendered -Encoding UTF8 -NoNewline
    Write-Host "  rendered settings.template.json -> $SettingsTarget"
}

Write-Host ''
Write-Host 'Done. Verify with:'
Write-Host '  Get-ChildItem ~/.claude/ | Where-Object { $_.LinkType -eq ''SymbolicLink'' }'
Write-Host ''
Write-Host "Note: install.ps1 doesn't install apps/fonts. For one-shot Windows onboarding (winget, oh-my-posh, Nerd Fonts, etc.), use the chezmoi path instead:"
Write-Host '  chezmoi init https://github.com/<owner>/gs-claude-config.git'
Write-Host '  chezmoi apply'
