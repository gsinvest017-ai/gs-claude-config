# PreToolUse hook：受保護分支的硬閘門。
#
# 為什麼需要這支腳本（不是「多一層保險」，是前三層都證實無效）：
#
# 1. 全域 CLAUDE.md 寫「main/master 禁止直接 push（不可協商）」——那只是 prompt，
#    模型可以忽略、agent 可能沒讀到、loop 的 fresh context 可能根本不載入。
#
# 2. permissions 的 deny 規則是**前綴比對，不是語義解析**。
#    `Bash(git push --force:*)` 擋得到 `git push --force origin x`，
#    但擋不到 `git push origin main --force`（參數順序顛倒）。
#    而且規則是 **tool-scoped**：寫 `Bash(...)` 只命中 Bash tool，
#    同一條指令改用 PowerShell tool 跑就直接放行（2026-08 實測確認）。
#
# 3. permission_mode = "bypassPermissions" 的 loop 會**整個繞過** allow/ask/deny。
#    gs-harness 的 nightly-verify 就是這樣設的。
#
# PreToolUse hook 是唯一同時解決這三點的層級：它拿得到**完整指令字串**、
# 對所有 tool 生效、而且在 bypassPermissions 下照樣執行。
#
# 2026-08-21 事故背景：29 個 repo 的 45 個已合併 PR 被 force push 抹除，
# 而「分支保護政策」的文件本身也在被抹掉的那一批裡面。詳見
# gs-harness/docs/incident-forgejo-mirror-2026-08-21.md
#
# ── 設計約束 ─────────────────────────────────────────────────
# * **寧可漏擋也不要誤擋。** 誤擋會讓人把整支 hook 關掉，那等於沒有防線。
#   所以用 **token 解析**而不是大正則：`git push origin main-experiment`
#   這種名字裡剛好有 main 的分支絕不能被擋。
# * 不猜當前分支。裸 `git push`（main 已設 upstream 時同樣危險）刻意不擋——
#   要擋就得跑 git 去問當前分支，那會讓每次工具呼叫都付出 subprocess 成本，
#   而且在非 repo 目錄下會噴錯。這個缺口由 permissions 的 ask 規則補。
# * 解析失敗、非 git 指令、任何例外 → 一律放行（exit 0），不吵。
# * 逃生門：指令內含 `#allow-protected-push` 時放行，讓真的需要時可以明示意圖，
#   而不是把整支 hook 停掉。

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Test-ProtectedRef {
    # 把一個 refspec 正規化成「目的地分支名」，判斷是否為受保護分支。
    #   main                      -> main        受保護
    #   +main                     -> main        受保護（+ 是 force 的另一種寫法）
    #   HEAD:main                 -> main        受保護
    #   HEAD:refs/heads/master    -> master      受保護
    #   dev/foo                   -> dev/foo     放行
    #   main-experiment           -> main-exp…   放行  ← 這是不能誤擋的關鍵案例
    #   feature/main              -> feature/main 放行
    param([string]$Spec)
    if ([string]::IsNullOrWhiteSpace($Spec)) { return $false }
    $s = $Spec.TrimStart('+')
    if ($s.Contains(':')) { $s = $s.Substring($s.LastIndexOf(':') + 1) }   # 取目的地那半
    $s = $s -replace '^refs/heads/', ''
    return ($s -eq 'main' -or $s -eq 'master')
}

try {
    $stdin = [Console]::In.ReadToEnd()
    if (-not $stdin) { exit 0 }

    $payload = $null
    try { $payload = $stdin | ConvertFrom-Json } catch { exit 0 }
    if (-not $payload) { exit 0 }

    if ([string]$payload.tool_name -notin @('Bash', 'PowerShell')) { exit 0 }

    $cmd = [string]$payload.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

    # 快速路徑：這支 hook 每次工具呼叫都會跑，沒有 push 就立刻結束
    if ($cmd -notmatch 'push') { exit 0 }
    if ($cmd -match '#\s*allow-protected-push') { exit 0 }

    # ── 先剝掉 heredoc 內文 ──────────────────────────────────────
    # 沒有這一步會有一整類誤擋：用 heredoc 寫的 commit message／文件內容
    # 只要「引用」了 git 指令（例如本 hook 自己的 commit message 就寫了
    # `git push origin main --force`），就會被當成真的要執行。
    # 這是實際踩到的——本 hook 上線第一次就把自己的 commit 擋掉了。
    $cmdForScan = [regex]::Replace(
        $cmd,
        '<<-?\s*[''"]?(\w+)[''"]?\r?\n[\s\S]*?\r?\n\1\b',
        ' <<HEREDOC_STRIPPED> ')

    $reason = $null

    # 一條指令可能串了好幾段。除了 ; && || | 之外，**換行也要切**——
    # 多行 Bash 區塊裡每一行是獨立指令，不切的話 `git add` 那行的 git
    # 會跟好幾行之後的 push 被湊成同一條指令。
    foreach ($segment in ($cmdForScan -split '(?:;|&&|\|\||\||\r?\n)')) {
        if ($segment -notmatch '(?i)\bgit\b') { continue }

        # 切 token（引號內的空白不切）
        $tokens = [regex]::Matches($segment, '"[^"]*"|''[^'']*''|\S+') |
                  ForEach-Object { $_.Value.Trim('"', "'") }
        if (-not $tokens) { continue }

        # 找 "git ... push"（中間可能夾 -C <path> 這類全域選項）
        $gi = [array]::IndexOf($tokens, ($tokens | Where-Object { $_ -match '(?i)(^|[\\/])git(\.exe)?$' } | Select-Object -First 1))
        if ($gi -lt 0) { continue }
        $pi = -1
        for ($i = $gi + 1; $i -lt $tokens.Count; $i++) {
            if ($tokens[$i] -eq 'push') { $pi = $i; break }
        }
        if ($pi -lt 0) { continue }

        $args = @($tokens[($pi + 1)..($tokens.Count - 1)]) | Where-Object { $_ }

        # ── 規則 1：force（不論出現在哪個位置）──────────────────
        if ($args | Where-Object { $_ -in @('--force', '-f', '--force-with-lease') -or $_ -like '--force-with-lease=*' }) {
            $reason = 'force push'; break
        }

        # ── 規則 2：--mirror（會同步刪除遠端多出來的 ref）────────
        if ($args -contains '--mirror') {
            $reason = '--mirror（會覆蓋並刪除遠端 ref）'; break
        }

        $positional = @($args | Where-Object { $_ -notlike '-*' })

        # ── 規則 3：刪除遠端的 main/master ─────────────────────
        if (($args -contains '--delete' -or $args -contains '-d') -and
            ($positional | Where-Object { Test-ProtectedRef $_ })) {
            $reason = '刪除遠端受保護分支'; break
        }

        # ── 規則 4：refspec 帶 + 前綴（等同 force）─────────────
        if ($positional | Where-Object { $_.StartsWith('+') -and $_.Length -gt 1 }) {
            $reason = '帶 + 前綴的 refspec（等同 force push）'; break
        }

        # ── 規則 5：明確指名推到 main / master ─────────────────
        # positional[0] 是 remote，之後才是 refspec，所以從第 2 個起算
        if ($positional.Count -ge 2) {
            $refspecs = @($positional[1..($positional.Count - 1)])
            if ($refspecs | Where-Object { Test-ProtectedRef $_ }) {
                $reason = '直接推到受保護分支 main/master'; break
            }
        }
    }

    if (-not $reason) { exit 0 }

    $msg = @"
已由 branch-guard hook 阻擋：$reason

偵測到的指令：
  $cmd

分支保護是不可協商的政策（見全域 CLAUDE.md）。請改走 PR：
  git checkout -b dev/<主題> origin/main
  git push -u origin dev/<主題>
  gh pr create --base main

2026-08-21 事故紀錄：29 個 repo 的 45 個已合併 PR 曾被 force push 抹除，
其中包含分支保護政策的文件本身。復原一律走 PR，不要用 force push 還原——
被覆蓋之後遠端通常也有新 commit，force 回去會造成第二次資料損失。

若這次確實必須執行，在指令尾端加上 #allow-protected-push 明示意圖。
"@

    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $msg
        }
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
catch {
    # 任何未預期的錯誤都放行——hook 壞掉不該讓使用者無法工作
    exit 0
}
