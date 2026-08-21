# UserPromptSubmit hook for the /autogo skill.
#
# Always pre-fetches the dashboard FrameOutput JSON + renders the ECHO PATH
# table so the skill's empty-input case can echo it without a Bash round-
# trip. Single LLM round-trip — no Bash tool — keeps wall ~1.5-2s.
#
# Supports `-w <alias> [<alias2> ...]` selection: tokens after `-w` that
# consist solely of ASCII letters / digits / underscores / hyphens become
# repeated `--window` args on context_cli, forwarded as ?window=...&window=...
# query params to the server. Server filters by case-insensitive substring
# match against title|app_name. Capture stops at the first non-ASCII-identifier
# token (e.g. Chinese question text) so "/autogo -w mock-calc 有沒有変化"
# correctly extracts only "mock-calc" and leaves the question for the LLM.
#
# Uses PowerShell native pipe (not cmd.exe) to avoid UTF-8 encoding issues:
# cmd.exe pipes with non-UTF-8 code page cause surrogates in context_summary,
# which silently drops the [autogo-json] block and loses filter_aliases.
# @winArgs splatting guarantees correct arg passing; 2>$null drops the
# context_cli stderr breadcrumb (context_summary handles missing breadcrumb).
# Always exits 0 — dashboard down / no-watchers / unmatched aliases are data.
#
# Matched only when user prompt starts with `/autogo` (settings.json
# UserPromptSubmit matcher).
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = 'utf-8'

# Read the JSON payload from stdin so we can parse `-w` from the prompt.
$stdin = [Console]::In.ReadToEnd()

# Extract the prompt field. The payload shape is
# `{"prompt":"<text>", "session_id":"...", ...}` — match the quoted value,
# tolerating JSON-style backslash escapes (\", \\, \n, etc.).
$prompt = ""
$pm = [regex]::Match($stdin, '"prompt"\s*:\s*"((?:[^"\\]|\\.)*)"')
if ($pm.Success) {
    # Unescape the captured value (best-effort — covers the cases that
    # actually show up in /autogo invocations: \", \\, \n).
    $prompt = $pm.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' -replace '\\n', "`n"
}

# Look for `-w <alias> [<alias2> ...]` and collect only ASCII-identifier
# tokens (letters / digits / underscores / hyphens). Stops at the first
# token that is NOT a pure ASCII identifier — this prevents question text
# like "有沒有変化" from being captured as a window alias.
$winArgs = @()
$wm = [regex]::Match($prompt, '(?:^|\s)-w\s+((?:[a-zA-Z0-9_\-]+)(?:\s+[a-zA-Z0-9_\-]+)*)')
if ($wm.Success) {
    foreach ($alias in ($wm.Groups[1].Value.Trim() -split '\s+')) {
        if ($alias) { $winArgs += @("--window", $alias) }
    }
}

# ── Auto-detect autogo Python (.venv) ─────────────────────────────────────────
# Priority: 1) ~/.claude/autogo-path.txt (written by claude/install.ps1)
#           2) common fallback paths ($HOME\autogo, C:\autogo)
$py = $null
$pathFile = Join-Path $env:USERPROFILE ".claude\autogo-path.txt"
if (Test-Path $pathFile) {
    $autogoRoot = (Get-Content $pathFile -Raw -Encoding UTF8).Trim()
    $candidate  = Join-Path $autogoRoot ".venv\Scripts\python.exe"
    if (Test-Path $candidate) { $py = $candidate }
}
if (-not $py) {
    foreach ($r in @((Join-Path $env:USERPROFILE "autogo"), "C:\autogo")) {
        $c = Join-Path $r ".venv\Scripts\python.exe"
        if (Test-Path $c) { $py = $c; break }
    }
}
if (-not $py) {
    Write-Output '[autogo-hook] python venv not found; skill will Bash fallback.'
    exit 0
}

# Run pipeline: context_cli --format=full [@winArgs] → context_summary --input=full
# @winArgs splatting passes --window args as separate arguments (no quoting needed).
# Out-String collapses the PS output stream into a single UTF-8 string for piping.
$ctxOutput  = (& $py -m autogo_dash.context_cli --format=full @winArgs 2>$null | Out-String)
$hookOutput = ($ctxOutput | & $py -m autogo_dash.context_summary --input=full | Out-String)

# --- Top OCR diff: compare current table row's Top OCR with cached value ---
# Parses the last column of the first data row in [autogo-response] table.
# Format: | N | App | Title | Updated | Top OCR |
$currentTopOcr = ""
foreach ($line in ($hookOutput -split "`n")) {
    if ($line -match '^\|\s*\d+\s*\|') {
        if ($line -match '\|\s*([^|]+?)\s*\|\s*$') {
            $currentTopOcr = $matches[1].Trim()
        }
        break
    }
}

$topOcrCacheFile = [System.IO.Path]::Combine($env:TEMP, "autogo-topcr.txt")
$prevTopOcr = ""
try { if (Test-Path $topOcrCacheFile) { $prevTopOcr = (Get-Content $topOcrCacheFile -Raw -Encoding UTF8).Trim() } } catch {}

# Only update cache when we have real Top OCR (skip when no watchers / empty)
$topOcrUnchanged = $currentTopOcr -ne "" -and $currentTopOcr -eq $prevTopOcr
if ($currentTopOcr -ne "") {
    try { [System.IO.File]::WriteAllText($topOcrCacheFile, $currentTopOcr, [System.Text.Encoding]::UTF8) } catch {}
}

# Inject top_ocr_unchanged signal into [autogo-meta] block before output
$signal     = "top_ocr_unchanged: " + ($topOcrUnchanged ? "true" : "false")
$hookOutput = $hookOutput -replace '\[/autogo-meta\]', "$signal`n[/autogo-meta]"

Write-Output $hookOutput
exit 0
