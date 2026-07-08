# gs-claude-toolkit - uninstaller (Windows).
# Removes the commands/skills/agents this toolkit installed into ~/.claude/,
# the autopilot.mjs hook, and the autopilot entries in settings.json. Only
# names matching this repo's own are removed; other ~/.claude content and your
# backups/ are left untouched.
#
#   .\uninstall-toolkit.ps1 [-Dir <checkout>] [-KeepHooks]

[CmdletBinding()]
param(
    [string]$Dir,
    [switch]$KeepHooks
)

$ErrorActionPreference = 'Stop'
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'

function Test-Checkout([string]$p) {
    return ($p -and (Test-Path (Join-Path $p 'skills')) -and (Test-Path (Join-Path $p '.claude-plugin\plugin.json')))
}

$RepoDir = $Dir
if (-not $RepoDir -and $PSScriptRoot -and (Test-Checkout $PSScriptRoot)) { $RepoDir = $PSScriptRoot }
if (-not (Test-Checkout $RepoDir)) { throw 'run from a checkout or pass -Dir <checkout>' }

foreach ($group in 'commands', 'skills', 'agents') {
    $srcDir = Join-Path $RepoDir $group
    if (-not (Test-Path $srcDir)) { continue }
    $n = 0
    foreach ($item in Get-ChildItem -Force $srcDir) {
        $dst = Join-Path $ClaudeDir "$group\$($item.Name)"
        if (Test-Path $dst) { Remove-Item -Recurse -Force $dst; $n++ }
    }
    Write-Host "  removed $n item(s) from $group"
}

if (-not $KeepHooks) {
    $HookMjs = Join-Path $ClaudeDir 'hooks\autopilot.mjs'
    if (Test-Path $HookMjs) { Remove-Item -Force $HookMjs }
    $Settings = Join-Path $ClaudeDir 'settings.json'
    if ((Test-Path $Settings) -and (Get-Command node -ErrorAction SilentlyContinue)) {
        node (Join-Path $RepoDir 'scripts\merge-settings.mjs') $Settings '--remove'
    }
}

Write-Host ''
Write-Host "Done. Backups (if any) remain under $ClaudeDir\backups\ - restore by hand if needed."
