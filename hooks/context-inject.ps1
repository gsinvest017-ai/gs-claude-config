# SessionStart hook：把跨 repo 的專案 context 注入每個新 session。
#
# 報告 B4 稱之為 benevolent prompt injection —— 目標是「每個 fresh session 的
# agent，開場就像剛加入專案但已完整 onboarding 的資深工程師」。
#
# 稽核發現這一格是 🔴 25%：hook 機制本身是 production 級（8 個 hook 註冊、
# 3 支用 hookSpecificOutput.additionalContext），但全機 49 份 settings 檔
# **SessionStart 零命中**，而唯一無條件注入的內容是螢幕 OCR，與專案無關。
#
# ── 為什麼這支腳本什麼邏輯都不做 ──
#
# SessionStart hook 只有約 1.5s 預算（memory 記載：跨 repo 全掃要 20s，
# 必須 -Detach）。超時的 hook 會被**靜默丟棄**——設定裡有 hook、實際從來沒
# 注入過，而且沒有任何錯誤訊息。那正是這整套稽核在對付的「假綠燈」。
#
# 所以採集與 render 都挪到 `harness context --refresh`（由 nightly loop 跑，
# 那時有的是時間），本腳本只做兩件事：讀一個預渲染好的檔、算它多舊。
# 沒有 python 啟動、沒有 git、沒有網路。
#
# 新鮮度：cache 是 nightly 產的，所以「昨天的」是正常狀態，不該吵。
# 只有超過 STALE_DAYS 才在注入內容最上方加一行警告——**過期也照樣注入**，
# 因為舊 context 仍遠勝於沒有 context，但必須讓 agent 知道它是舊的。

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$StaleDays = 3

try {
    $root = $env:GS_HARNESS_ROOT
    if (-not $root) { $root = Join-Path $env:USERPROFILE 'gs-harness' }
    $file = Join-Path $root 'state\context-agent.md'

    if (-not (Test-Path -LiteralPath $file)) { exit 0 }   # 還沒 refresh 過就安靜跳過

    $body = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($body)) { exit 0 }

    $age = ((Get-Date) - (Get-Item -LiteralPath $file).LastWriteTime).TotalDays
    $header = "# 專案 context（gs-harness，自動注入）"
    if ($age -gt $StaleDays) {
        $header += "`n> ⚠️ 這份 context 已 {0:N0} 天沒更新，內容可能過時。" -f $age
        $header += "`n> 重建：``harness context --refresh``"
    }

    $text = $header + "`n`n" + $body.TrimEnd() + @"


---
需要更完整的資料（registry 全表、各 artifact 路徑、原始 JSON）就跑：
  harness context --mode agent --json
  harness validate            # 檢查文件宣稱與現實是否一致
  harness skills status       # skill 分佈、重名遮蔽、未提升為全域的
"@

    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'SessionStart'
            additionalContext = $text
        }
    }
    $out | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
catch {
    # hook 壞掉不該讓 session 起不來，也不該吵
    exit 0
}
