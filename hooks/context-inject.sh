#!/usr/bin/env bash
# SessionStart hook（POSIX 版）：把跨 repo 的專案 context 注入每個新 session。
#
# 與 context-inject.ps1 完全同一個契約，只是給 Linux / macOS / WSL 用。
# 兩份必須同時維護——install.sh 在非 Windows 機器上渲染的是這一份，
# 若只更新 .ps1，Linux 端會靜默地拿到舊行為（而 hook 的失敗一律是靜默的）。
#
# ── 為什麼這支腳本什麼邏輯都不做 ──
#
# SessionStart hook **同步阻塞 session 開場**——它跑多久，使用者就乾等多久。
# 跨 repo 全掃要 20 秒，沒有人能接受每次開 session 先等 20 秒。
#
# 所以採集與 render 都挪到 `harness context --refresh`（由 nightly loop 跑），
# 本腳本只做兩件事：讀預渲染好的檔、算它多舊。沒有 python、沒有 git、沒有網路。
#
# 新鮮度：cache 是 nightly 產的，「昨天的」是正常狀態、不該吵。
# 只有超過 STALE_DAYS 才加警告——**過期也照樣注入**，因為舊 context 仍遠勝於
# 沒有 context，但必須讓 agent 知道它是舊的。

set -uo pipefail

STALE_DAYS=3

root="${GS_HARNESS_ROOT:-$HOME/gs-harness}"
file="$root/state/context-agent.md"

# 還沒 refresh 過 / 檔案是空的 → 安靜跳過。
# 注入空內容比不注入更糟：agent 會把「有這個區塊但裡面沒東西」讀成「沒事」。
[ -s "$file" ] || exit 0

body="$(cat "$file" 2>/dev/null)" || exit 0
[ -n "${body//[[:space:]]/}" ] || exit 0

# mtime：GNU stat 與 BSD/macOS stat 的旗標不同，兩個都試
mtime="$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0)"
now="$(date +%s)"
age_days=$(( (now - mtime) / 86400 ))

header="# 專案 context（gs-harness，自動注入）"
if [ "$mtime" -gt 0 ] && [ "$age_days" -gt "$STALE_DAYS" ]; then
    header="$header
> ⚠️ 這份 context 已 ${age_days} 天沒更新，內容可能過時。
> 重建：\`harness context --refresh\`"
fi

footer='

---
需要更完整的資料（registry 全表、各 artifact 路徑、原始 JSON）就跑：
  harness context --mode agent --json
  harness validate            # 檢查文件宣稱與現實是否一致
  harness skills status       # skill 分佈、重名遮蔽、未提升為全域的'

text="${header}

${body}${footer}"

# 用 python 產 JSON 才不會被內容裡的引號/換行弄壞；沒有 python 就安靜放棄，
# 不要吐出半殘的 JSON 讓 Claude Code 去解析失敗。
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || exit 0

TEXT="$text" "$PY" -c '
import json, os
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": os.environ["TEXT"],
}}, ensure_ascii=False))
' 2>/dev/null || exit 0

exit 0
