# unschedule-review.ps1
# Removes one or all ClaudeCode-ProgLangTutor-Review-* scheduled tasks.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File unschedule-review.ps1                  # remove ALL prog-lang-tutor tasks
#   powershell -ExecutionPolicy Bypass -File unschedule-review.ps1 -RepoSlug autogo # remove just one

[CmdletBinding()]
param(
    [string] $RepoSlug
)

$ErrorActionPreference = 'Stop'

if ($RepoSlug) {
    $taskName = "ClaudeCode-ProgLangTutor-Review-$RepoSlug"
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "No task named '$taskName' — nothing to remove."
        exit 0
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed: $taskName"
    exit 0
}

$all = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -like 'ClaudeCode-ProgLangTutor-Review-*'
}
if (-not $all -or @($all).Count -eq 0) {
    Write-Host "No ClaudeCode-ProgLangTutor-Review-* tasks found."
    exit 0
}

foreach ($t in $all) {
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
    Write-Host "Removed: $($t.TaskName)"
}
Write-Host "Removed $(@($all).Count) task(s)."
