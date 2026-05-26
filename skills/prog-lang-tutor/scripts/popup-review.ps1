# popup-review.ps1
# Pops up a single knowledge point from a repo's knowledge bank as a Windows
# Forms quiz dialog. Updates last_reviewed + reviewed_count in knowledge.json
# after the user closes the popup.
#
# Designed to be invoked by Windows Task Scheduler. Runs in the logged-on
# user's interactive session.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File popup-review.ps1 -RepoSlug autogo
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File popup-review.ps1 -RepoSlug autogo -DryRun

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $RepoSlug,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ----- Locate knowledge.json -----
$dataRoot = Join-Path $PSScriptRoot '..\data'
$jsonPath = Join-Path $dataRoot "$RepoSlug\knowledge.json"

if (-not (Test-Path -LiteralPath $jsonPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Knowledge bank not found:`n$jsonPath`n`nRun /prog-lang-tutor analyze first.",
        "prog-lang-tutor",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

$raw = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8
try {
    $bank = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "knowledge.json is corrupt:`n$jsonPath`n`n$($_.Exception.Message)",
        "prog-lang-tutor",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

$points = @($bank.knowledge_points)
if ($points.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "knowledge.json has zero knowledge_points.`n$jsonPath",
        "prog-lang-tutor",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

# ----- Pick a knowledge point: oldest reviewed first, then least reviewed, then random -----
function Get-LastReviewedSortKey($p) {
    if (-not $p.last_reviewed) { return [DateTime]::MinValue }
    try { return [DateTime]::Parse($p.last_reviewed) } catch { return [DateTime]::MinValue }
}

$sorted = $points |
    Sort-Object `
        @{ Expression = { Get-LastReviewedSortKey $_ }; Ascending = $true },
        @{ Expression = { if ($_.reviewed_count) { [int]$_.reviewed_count } else { 0 } }; Ascending = $true },
        @{ Expression = { Get-Random }; Ascending = $true }

$pick = $sorted[0]

# ----- Build the WinForms popup -----
$form = New-Object System.Windows.Forms.Form
$form.Text = "prog-lang-tutor — $($bank.repo_slug) / $($bank.language)"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(720, 620)
$form.MinimumSize = New-Object System.Drawing.Size(520, 420)
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# Topic header
$lblTopic = New-Object System.Windows.Forms.Label
$lblTopic.Text = "[$($pick.category)] $($pick.topic)"
$lblTopic.AutoSize = $false
$lblTopic.Dock = 'Top'
$lblTopic.Height = 36
$lblTopic.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$lblTopic.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 0)
$form.Controls.Add($lblTopic)

# Question
$lblQuestion = New-Object System.Windows.Forms.Label
$lblQuestion.Text = "Q: $($pick.quiz.question)"
$lblQuestion.AutoSize = $false
$lblQuestion.Dock = 'Top'
$lblQuestion.Height = 56
$lblQuestion.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 4)
$form.Controls.Add($lblQuestion)

# Code box
$codeBox = New-Object System.Windows.Forms.TextBox
$codeBox.Multiline = $true
$codeBox.ReadOnly = $true
$codeBox.ScrollBars = 'Vertical'
$codeBox.WordWrap = $false
$codeBox.Font = New-Object System.Drawing.Font('Consolas', 10)
$codeBox.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$codeBox.Text = if ($pick.quiz.code) { $pick.quiz.code } else { $pick.code_example }
$codeBox.Dock = 'Top'
$codeBox.Height = 180
$form.Controls.Add($codeBox)

# Answer box (hidden until "Show Answer")
$answerBox = New-Object System.Windows.Forms.TextBox
$answerBox.Multiline = $true
$answerBox.ReadOnly = $true
$answerBox.ScrollBars = 'Vertical'
$answerBox.WordWrap = $true
$answerBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$answerBox.BackColor = [System.Drawing.Color]::FromArgb(252, 252, 240)
$answerBox.Text = ""
$answerBox.Dock = 'Fill'
$form.Controls.Add($answerBox)

# Button panel
$btnPanel = New-Object System.Windows.Forms.Panel
$btnPanel.Dock = 'Bottom'
$btnPanel.Height = 56
$form.Controls.Add($btnPanel)

$btnShow = New-Object System.Windows.Forms.Button
$btnShow.Text = "Show Answer"
$btnShow.Size = New-Object System.Drawing.Size(140, 36)
$btnShow.Location = New-Object System.Drawing.Point(12, 10)
$btnPanel.Controls.Add($btnShow)

$btnDone = New-Object System.Windows.Forms.Button
$btnDone.Text = "Got it (close)"
$btnDone.Size = New-Object System.Drawing.Size(140, 36)
$btnDone.Location = New-Object System.Drawing.Point(160, 10)
$btnPanel.Controls.Add($btnDone)

$btnSkip = New-Object System.Windows.Forms.Button
$btnSkip.Text = "Skip (no count)"
$btnSkip.Size = New-Object System.Drawing.Size(140, 36)
$btnSkip.Location = New-Object System.Drawing.Point(308, 10)
$btnPanel.Controls.Add($btnSkip)

# State: did we show the answer?
$script:answerShown = $false
$script:userSkipped = $false

$btnShow.Add_Click({
    $where = ""
    if ($pick.where_used -and @($pick.where_used).Count -gt 0) {
        $where = "`n`n出現位置：`n  - " + ((@($pick.where_used) | Select-Object -First 5) -join "`n  - ")
    }
    $whyImportant = ""
    if ($pick.why_important) {
        $whyImportant = "`n`n為什麼重要：`n$($pick.why_important)"
    }
    $answerBox.Text = "答：`n$($pick.quiz.answer)`n`n解析：`n$($pick.explanation)$whyImportant$where"
    $script:answerShown = $true
    $btnShow.Enabled = $false
})

$btnDone.Add_Click({ $form.Close() })
$btnSkip.Add_Click({
    $script:userSkipped = $true
    $form.Close()
})

# ----- Show (or skip in DryRun) -----
if ($DryRun) {
    Write-Host "[DryRun] Picked knowledge point:"
    Write-Host "  id:         $($pick.id)"
    Write-Host "  topic:      $($pick.topic)"
    Write-Host "  category:   $($pick.category)"
    Write-Host "  difficulty: $($pick.difficulty)"
    Write-Host "  reviewed:   $($pick.reviewed_count)"
    Write-Host "  last:       $($pick.last_reviewed)"
    Write-Host "[DryRun] Would have shown dialog + updated last_reviewed/reviewed_count."
    exit 0
}

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

if (-not $script:answerShown -or $script:userSkipped) {
    exit 0
}

$nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
foreach ($p in $bank.knowledge_points) {
    if ($p.id -eq $pick.id) {
        $count = 0
        if ($p.reviewed_count) { $count = [int]$p.reviewed_count }
        $p | Add-Member -Force -NotePropertyName 'reviewed_count' -NotePropertyValue ($count + 1)
        $p | Add-Member -Force -NotePropertyName 'last_reviewed'  -NotePropertyValue $nowUtc
        break
    }
}

$finalJson = $bank | ConvertTo-Json -Depth 32
[System.IO.File]::WriteAllText($jsonPath, $finalJson, [System.Text.UTF8Encoding]::new($false))
