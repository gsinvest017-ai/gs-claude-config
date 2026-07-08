# Refresh the vendored copies of the skills that live in the sibling repo
# `quant-research-skill` (Windows counterpart of sync-vendored-skills.sh).
#
# `skills/quant-researcher` and `skills/review-strategy` are VENDORED (real
# copies) rather than symlinks so they survive a `git clone` plugin install.
# The sibling repo stays the source of truth — edit there, run this to pull the
# changes back in, then commit.
#
# Usage:  scripts\sync-vendored-skills.ps1 [-SrcRoot <path-to-quant-research-skill>]

[CmdletBinding()]
param(
    [string]$SrcRoot = (Join-Path $env:USERPROFILE 'quant-research-skill')
)

$ErrorActionPreference = 'Stop'

$RepoDir  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Vendored = @('quant-researcher', 'review-strategy')

if (-not (Test-Path (Join-Path $SrcRoot 'skills'))) {
    Write-Error "sibling repo not found at $SrcRoot (no skills/ dir). Clone it first: git clone https://github.com/gsinvest017-ai/quant-research-skill.git `"$SrcRoot`""
}

foreach ($s in $Vendored) {
    $src = Join-Path $SrcRoot "skills\$s"
    $dst = Join-Path $RepoDir "skills\$s"
    if (-not (Test-Path $src)) {
        Write-Warning "$src missing - skipped"
        continue
    }
    if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item -Recurse -Force (Join-Path $src '*') $dst
    Write-Host "synced skills/$s  <-  $src"
}

Write-Host ''
Write-Host "Done. Review + commit:  git -C `"$RepoDir`" add skills/ ; git -C `"$RepoDir`" commit"
