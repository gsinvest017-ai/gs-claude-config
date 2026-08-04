# ============================================================================
# gs-claude-toolkit - Codex CLI consumer installer (Windows)
# ============================================================================
# Installs the repo's reusable skills into %USERPROFILE%\.codex\skills and,
# optionally, Codex-native autopilot hooks into %USERPROFILE%\.codex\hooks plus
# %USERPROFILE%\.codex\hooks.json. This does not touch ~/.claude.
#
# From a local clone:
#   .\install-codex-toolkit.ps1 [-Link] [-NoHooks] [-BypassPermissions] [-Dir <path>] [-RepoUrl <url>] [-Branch <name>]
#
# Remote one-liner:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-codex-toolkit.ps1))) -BypassPermissions
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Link,
    [switch]$NoHooks,
    [switch]$BypassPermissions,
    [string]$Dir,
    [string]$RepoUrl = $(if ($env:GS_REPO_URL) { $env:GS_REPO_URL } else { 'https://github.com/gsinvest017-ai/gs-claude-config.git' }),
    [string]$Branch  = $(if ($env:GS_BRANCH)  { $env:GS_BRANCH }  else { 'main' })
)

$ErrorActionPreference = 'Stop'

$CodexDir  = Join-Path $env:USERPROFILE '.codex'
$Ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $CodexDir "backups\toolkit-$Ts"

function Test-Checkout([string]$p) {
    return ($p -and (Test-Path (Join-Path $p 'skills')) -and (Test-Path (Join-Path $p '.claude-plugin\plugin.json')))
}

$RepoDir = $Dir
if (-not $RepoDir -and $PSScriptRoot -and (Test-Checkout $PSScriptRoot)) {
    $RepoDir = $PSScriptRoot
}
if (-not $RepoDir) {
    $Cache = if ($env:GS_CACHE) { $env:GS_CACHE } else { Join-Path $env:LOCALAPPDATA 'gs-claude-toolkit' }
    if (Test-Checkout $Cache) {
        Write-Host "==> Updating cached checkout at $Cache"
        git -C $Cache fetch --depth 1 origin $Branch -q
        git -C $Cache reset --hard "origin/$Branch" -q
    } else {
        Write-Host "==> Cloning $RepoUrl ($Branch) -> $Cache"
        if (Test-Path $Cache) { Remove-Item -Recurse -Force $Cache }
        git clone --depth 1 --branch $Branch $RepoUrl $Cache -q
    }
    $RepoDir = $Cache
}

if (-not (Test-Checkout $RepoDir)) { throw "$RepoDir is not a gs-claude-config checkout" }

$Mode = if ($Link) { 'link' } else { 'copy' }
Write-Host "==> Installing Codex toolkit from $RepoDir  (mode: $Mode)"
if (-not (Test-Path $CodexDir)) { New-Item -ItemType Directory -Path $CodexDir | Out-Null }

function Backup-Path([string]$path, [string]$bucket) {
    if (-not (Test-Path $path)) { return }
    $bg = Join-Path $BackupDir $bucket
    if (-not (Test-Path $bg)) { New-Item -ItemType Directory -Path $bg -Force | Out-Null }
    Move-Item -LiteralPath $path -Destination $bg -Force
}

function Place([string]$src, [string]$dstDir) {
    $name = Split-Path -Leaf $src
    $dst  = Join-Path $dstDir $name
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    if (Test-Path $dst) { Backup-Path $dst (Split-Path -Leaf $dstDir) }
    if ($Mode -eq 'link') {
        if (Test-Path $src -PathType Container) { cmd /c mklink /D "`"$dst`"" "`"$src`"" | Out-Null }
        else { cmd /c mklink "`"$dst`"" "`"$src`"" | Out-Null }
    } else {
        Copy-Item -Recurse -Force $src $dst
    }
}

function Install-Skills {
    $srcDir = Join-Path $RepoDir 'skills'
    $dstDir = Join-Path $CodexDir 'skills'
    $n = 0
    foreach ($item in Get-ChildItem -Force $srcDir) {
        Place $item.FullName $dstDir
        $n++
    }
    Write-Host "  skills: $n item(s)"
}

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{ hooks = [pscustomobject]@{} }
    }
    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ hooks = [pscustomobject]@{} }
    }
    return ($raw | ConvertFrom-Json)
}

function Ensure-HookEvent($root, [string]$eventName) {
    if (-not $root.PSObject.Properties['hooks']) {
        $root | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    if (-not $root.hooks.PSObject.Properties[$eventName]) {
        $root.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @()
    }
}

function Add-CodexHook($root, [string]$eventName, [string]$command, [int]$timeout) {
    Ensure-HookEvent $root $eventName
    foreach ($entry in @($root.hooks.$eventName)) {
        foreach ($hook in @($entry.hooks)) {
            if ([string]$hook.command -eq $command) { return }
        }
    }
    $newEntry = [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type    = 'command'
                command = $command
                timeout = $timeout
            }
        )
    }
    $root.hooks.$eventName = @($root.hooks.$eventName) + $newEntry
}

function Install-CodexHooks {
    if ($NoHooks) {
        Write-Host '==> Skipping Codex hooks (-NoHooks)'
        return
    }

    Write-Host '==> Codex autopilot hooks + hooks.json'
    $HooksDir = Join-Path $CodexDir 'hooks'
    if (-not (Test-Path $HooksDir)) { New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null }

    foreach ($name in 'autopilot-arm.ps1', 'autopilot-continue.ps1') {
        Copy-Item -Force (Join-Path $RepoDir "codex-hooks\$name") (Join-Path $HooksDir $name)
    }

    $HooksJson = Join-Path $CodexDir 'hooks.json'
    if (Test-Path $HooksJson) {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        Copy-Item -Force $HooksJson (Join-Path $BackupDir 'hooks.json.bak')
    }

    $root = Read-JsonFile $HooksJson
    $arm = 'pwsh -NoProfile -NonInteractive -File "' + (Join-Path $HooksDir 'autopilot-arm.ps1') + '"'
    $continue = 'pwsh -NoProfile -NonInteractive -File "' + (Join-Path $HooksDir 'autopilot-continue.ps1') + '"'
    Add-CodexHook $root 'UserPromptSubmit' $arm 10
    Add-CodexHook $root 'Stop' $continue 30
    ($root | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $HooksJson -Encoding UTF8
}

function Enable-BypassPermissions {
    if (-not $BypassPermissions) { return }

    Write-Host '==> Enabling Codex default bypass permissions'
    $ConfigToml = Join-Path $CodexDir 'config.toml'
    if (Test-Path $ConfigToml) {
        if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        Copy-Item -Force $ConfigToml (Join-Path $BackupDir 'config.toml.bak')
        $lines = Get-Content -LiteralPath $ConfigToml
    } else {
        $lines = @()
    }

    $filtered = New-Object System.Collections.Generic.List[string]
    $inRoot = $true
    $skipManagedBlock = $false
    foreach ($line in $lines) {
        if ($line -match '^# >>> gs-codex-toolkit bypass permissions >>>') {
            $skipManagedBlock = $true
            continue
        }
        if ($skipManagedBlock) {
            if ($line -match '^# <<< gs-codex-toolkit bypass permissions <<<') {
                $skipManagedBlock = $false
            }
            continue
        }
        if ($line -match '^\s*\[') { $inRoot = $false }
        if ($inRoot -and $line -match '^\s*(approval_policy|sandbox_mode)\s*=') { continue }
        $filtered.Add($line)
    }

    $block = @(
        '# >>> gs-codex-toolkit bypass permissions >>>',
        'approval_policy = "never"',
        'sandbox_mode = "danger-full-access"',
        '# <<< gs-codex-toolkit bypass permissions <<<',
        ''
    )
    $newLines = @($block) + $filtered.ToArray()
    Set-Content -LiteralPath $ConfigToml -Encoding UTF8 -Value $newLines
}

Install-Skills
Install-CodexHooks
Enable-BypassPermissions

Write-Host ''
if (Test-Path $BackupDir) { Write-Host "Backed up pre-existing items -> $BackupDir" }
Write-Host 'Done. Restart Codex CLI, then verify:'
Write-Host '  Get-ChildItem ~/.codex/skills | Select-Object -First 5'
Write-Host '  Get-Content ~/.codex/hooks.json -Raw'
if ($BypassPermissions) {
    Write-Host '  Get-Content ~/.codex/config.toml -Raw | Select-String "approval_policy|sandbox_mode"'
}


