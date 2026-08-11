# UserPromptSubmit hook：使用者提到 KAN-123 這種 ticket 編號時，把那幾張單的
# 現況注入 context，省掉一次「先查再答」的往返。
#
# 設計上的三個約束：
#
# 1. 這支腳本每一次 prompt 都會跑，所以**沒有命中就必須立刻結束**。正規式比對
#    在毫秒等級，只有真的出現 KAN-<數字> 時才會碰網路。
#
# 2. settings.json 用 `matcher` 正規式決定要不要啟動這支 hook，所以主要的守門
#    在那裡（`[Kk][Aa][Nn]-\d+`）——沒有 ticket 編號的 prompt 根本不會 spawn
#    pwsh，省下每次 prompt 約 340ms 的啟動成本。腳本內的比對是第二道，
#    用來處理 matcher 命中但取不到 prompt 的情況。
#
# 3. **永遠 exit 0、永遠不要吵。** 查不到、沒裝 kan、憑證過期、Jira 掛掉，
#    一律安靜跳過。hook 不該把使用者的 prompt 擋下來。
#
# 憑證與設定重用 ~/.kan/kan.ps1（dot-source 只是定義函式，不碰網路），
# 避免在這裡複製一份 DPAPI 解密與設定解析邏輯出來各自漂移。

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

try {
    $stdin = [Console]::In.ReadToEnd()
    if (-not $stdin) { exit 0 }

    # payload 形狀是 {"prompt":"<text>", "session_id":"...", ...}
    $m = [regex]::Match($stdin, '"prompt"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { exit 0 }
    $prompt = $m.Groups[1].Value -replace '\\"', '"' -replace '\\\\', '\' -replace '\\n', "`n"

    # 快速路徑：沒有 ticket 編號就直接走人，不載入任何東西
    $keys = [regex]::Matches($prompt, '(?i)\bKAN-\d+\b') |
        ForEach-Object { $_.Value.ToUpper() } | Select-Object -Unique
    if (-not $keys) { exit 0 }
    # 上限 5 張：再多就不是「談這幾張單」而是在跑報表，那該由模型自己下 kan jql
    if ($keys.Count -gt 5) { $keys = $keys | Select-Object -First 5 }

    $kanPath = Join-Path $HOME '.kan\kan.ps1'
    if (-not (Test-Path $kanPath)) { exit 0 }
    . $kanPath

    $jql = 'key in (' + ($keys -join ',') + ')'
    $issues = @(script:KanRest ("search/jql?jql=" + [uri]::EscapeDataString($jql) +
        "&maxResults=5&fields=summary,status,assignee,updated")).issues
    if (-not $issues) { exit 0 }

    $site = (script:KanConfig).site
    $lines = foreach ($i in $issues) {
        $f = $i.fields
        $who = if ($f.assignee) { $f.assignee.displayName } else { '未指派' }
        "$($i.key)  [$($f.status.name)]  $who  —  $($f.summary)`n  $site/browse/$($i.key)"
    }

    # 找不到的 key 明講，不要讓模型以為是自己看漏了
    $found = @($issues | ForEach-Object { $_.key })
    $missing = @($keys | Where-Object { $found -notcontains $_ })

    $body = "使用者提到的 Jira ticket 現況（由 kan-context hook 即時查詢，唯讀）：`n" +
            ($lines -join "`n")
    if ($missing) { $body += "`n查無此單（可能不存在或無權限）：" + ($missing -join '、') }
    $body += "`n需要更多細節用 kan v <key>；要改動請依 kan skill 的規則，寫入會掛在使用者本人帳號上。"

    $out = @{ hookSpecificOutput = @{
        hookEventName     = 'UserPromptSubmit'
        additionalContext = $body
    } } | ConvertTo-Json -Compress -Depth 4
    [Console]::Out.Write($out)
} catch {
    # 安靜失敗：hook 出問題不該影響使用者送出 prompt
}
exit 0
