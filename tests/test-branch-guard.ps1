$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$hook = "C:\Users\User\.claude\hooks\branch-guard.ps1"

$mustDeny = @(
    'git push --force origin main',
    'git push origin main --force',
    'git push -f',
    'git push origin main',
    'git push upstream master',
    'git push origin +main:main',
    'git push --mirror origin',
    'git push origin HEAD:main',
    'git push origin HEAD:refs/heads/master',
    'git push origin --delete main',
    'git push --force-with-lease origin main',
    'git push --force-with-lease=main:abc123 origin main',
    'git -C /c/Users/User/gs-harness push origin main',
    'cd /tmp && git push origin master',
    'git push origin dev/foo && git push origin main',
    'git push -u origin main',
    'git push origin refs/heads/main'
)

# 多行 + heredoc 的必擋案例：真的要推 main，只是寫在多行區塊裡
$denyMultiline = @"
cd /c/Users/User/gs-harness
git add .
git commit -m "wip"
git push origin main
"@

$mustAllow = @(
    'git push -u origin dev/phase0-fix',
    'git push origin dev/incident-forgejo-mirror',
    'git push',
    'git push origin main-experiment',
    'git push origin feature/main',
    'git push origin mainline',
    'git push origin master-notes',
    'git status',
    'npm run push-docs',
    'echo "do not push to main"',
    'git log --oneline -1',
    'git push origin dev/x --set-upstream',
    'git fetch origin main',
    'git push origin main #allow-protected-push',
    'gh pr create --base main --head dev/x',
    'git commit -m "fix: 別再用 git push --force"'
)

# 迴歸案例：commit message 用 heredoc 寫，內文「引用」了 git 指令。
# 這是本 hook 上線第一次就踩到的誤擋——它把自己的 commit 擋掉了。
$allowHeredoc = @"
cd /c/Users/User/gs-claude-config
git add hooks/branch-guard.ps1
git commit -F - <<'EOF'
feat: 新增 branch-guard hook

deny 規則是前綴比對，`Bash(git push --force:*)` 擋不到
`git push origin main --force` 這種參數順序顛倒的寫法。
EOF
git push origin dev/phase0-fix-dead-imports
"@

# 多行但每一行都合法
$allowMultiline = @"
git fetch origin
git checkout -b dev/foo origin/main
git push -u origin dev/foo
"@

function Invoke-Hook([string]$cmd, [string]$tool = 'Bash') {
    $payload = @{ tool_name = $tool; tool_input = @{ command = $cmd } } | ConvertTo-Json -Compress
    $out = $payload | pwsh -NoProfile -NonInteractive -File $hook 2>$null
    return [bool]($out -and $out -match 'permissionDecision')
}

$fail = 0
$total = 0

Write-Host "=== 必須擋下（deny）===" -ForegroundColor Cyan
foreach ($c in $mustDeny) {
    $total++
    if (Invoke-Hook $c) { Write-Host ("  PASS  " + $c) }
    else { Write-Host ("  FAIL  漏擋 -> " + $c) -ForegroundColor Red; $fail++ }
}
$total++
if (Invoke-Hook $denyMultiline) { Write-Host "  PASS  [多行區塊內真的 push main]" }
else { Write-Host "  FAIL  漏擋 -> [多行區塊內真的 push main]" -ForegroundColor Red; $fail++ }

Write-Host "`n=== 必須放行（allow）===" -ForegroundColor Cyan
foreach ($c in $mustAllow) {
    $total++
    if (-not (Invoke-Hook $c)) { Write-Host ("  PASS  " + $c) }
    else { Write-Host ("  FAIL  誤擋 -> " + $c) -ForegroundColor Red; $fail++ }
}
$total++
if (-not (Invoke-Hook $allowHeredoc)) { Write-Host "  PASS  [heredoc commit message 引用 git push --force]" }
else { Write-Host "  FAIL  誤擋 -> [heredoc commit message 引用 git push --force]" -ForegroundColor Red; $fail++ }
$total++
if (-not (Invoke-Hook $allowMultiline)) { Write-Host "  PASS  [多行區塊，每行都合法]" }
else { Write-Host "  FAIL  誤擋 -> [多行區塊，每行都合法]" -ForegroundColor Red; $fail++ }

Write-Host "`n=== PowerShell tool 也要生效（tool-scoped 缺口的重點）===" -ForegroundColor Cyan
$total++
if (Invoke-Hook 'git push origin main' 'PowerShell') { Write-Host "  PASS  PowerShell tool 的 git push origin main 被擋" }
else { Write-Host "  FAIL  PowerShell tool 未被擋" -ForegroundColor Red; $fail++ }

Write-Host "`n=== 不相干的 tool 要放行 ===" -ForegroundColor Cyan
$total++
if (-not (Invoke-Hook 'git push origin main' 'Read')) { Write-Host "  PASS  Read tool 不受影響" }
else { Write-Host "  FAIL  Read tool 被誤擋" -ForegroundColor Red; $fail++ }

Write-Host ""
if ($fail -eq 0) { Write-Host "全部通過（$total 案例）" -ForegroundColor Green }
else { Write-Host "$fail / $total 案例失敗" -ForegroundColor Red }
exit $fail
