# schedule-review.ps1
# Creates / replaces a Windows Task Scheduler task that pops up a knowledge
# point review for a given repo slug every N minutes.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File schedule-review.ps1 -RepoSlug autogo -IntervalMinutes 30
#
# Lifetime:
#   - Task only runs while the user is logged on (interactive session) so the
#     popup actually appears on the desktop.
#   - Replaces any existing task of the same name.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $RepoSlug,
    [Parameter(Mandatory = $true)] [int]    $IntervalMinutes
)

$ErrorActionPreference = 'Stop'

if ($IntervalMinutes -lt 15) {
    Write-Error "IntervalMinutes < 15 is not allowed (annoyance guard). Got: $IntervalMinutes"
    exit 2
}
if ($IntervalMinutes -gt 1439) {
    Write-Error "IntervalMinutes > 1439 (24h) is not allowed. Got: $IntervalMinutes"
    exit 2
}

$dataRoot = Join-Path $PSScriptRoot '..\data'
$jsonPath = Join-Path $dataRoot "$RepoSlug\knowledge.json"
if (-not (Test-Path -LiteralPath $jsonPath)) {
    Write-Error "No knowledge.json for slug '$RepoSlug': $jsonPath`nRun /prog-lang-tutor analyze first."
    exit 3
}

$popupScript = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'popup-review.ps1')).Path
$taskName    = "ClaudeCode-ProgLangTutor-Review-$RepoSlug"

# Use ScheduledTasks module (modern API) to avoid schtasks.exe quoting hell.
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed existing task: $taskName"
    }

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$popupScript`" -RepoSlug `"$RepoSlug`""

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 365)

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

    $principal = New-ScheduledTaskPrincipal `
        -UserId $env:USERNAME `
        -LogonType Interactive `
        -RunLevel Limited

    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
        -Description "Pops up a random knowledge point from $RepoSlug every $IntervalMinutes minutes."

    Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null

    $now = Get-Date
    $next = $now.AddMinutes(1)
    Write-Host ""
    Write-Host "Created scheduled task:"
    Write-Host "  Name:    $taskName"
    Write-Host "  Repo:    $RepoSlug"
    Write-Host "  Every:   $IntervalMinutes minutes"
    Write-Host "  Next:    $($next.ToString('yyyy-MM-dd HH:mm'))"
    Write-Host ""
    Write-Host "To stop: /prog-lang-tutor unschedule $RepoSlug"
    Write-Host "  Or:   powershell -File `"$PSScriptRoot\unschedule-review.ps1`" -RepoSlug $RepoSlug"
} catch {
    Write-Error "Failed to create task: $($_.Exception.Message)"
    exit 4
}
