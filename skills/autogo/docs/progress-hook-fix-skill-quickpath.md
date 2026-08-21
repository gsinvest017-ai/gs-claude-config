# safe-yolo: autogo hook -w 解析修復 + SKILL.md 快捷路徑

## 目標
按優先順序修兩件事：
1. `autogo-prefetch.ps1` 的 `-w` alias 正規式把中文問句也當成 alias token，導致 `filter_aliases` 永遠為空（`--window 有沒有変化` 讓 server 收不到合法 alias）。
2. SKILL.md 加入「有沒有變化」快捷路徑（grep key values，省去讀 60-100KB persisted 檔的三步 tool call），並修正 /loop 範例 interval（30s→1m）。

## 根因分析
- hook 正規式：`([^\-].*?)(?=\s+-[a-zA-Z]|\s*$)` 的 lookahead `\s*$` 使 `.*?` 貪婪展開到句尾
- 結果：`mock-calc 有沒有変化` 整串被 split 成 `["mock-calc", "有沒有変化"]`，兩個都帶入 `--window`
- context_cli 的 `_build_full_path` 把 `有沒有変化` URL-encode 後送出，server 雖收到但 `matched_aliases` 為空（無 watcher title 含此字串），`filter_aliases` 顯示接收到的 aliases（含中文）... 但實際 `filter_aliases: []` 的原因更可能是 cmd.exe 的多位元組字元傳遞問題，讓整個 window arg 靜默失效
- 最安全的修法：alias 只允許 ASCII 識別符（`[a-zA-Z0-9_\-]+`），碰到中文/空格即停止

## 計畫 milestone

- [x] M1：修 `autogo-prefetch.ps1` regex（ASCII-only alias）+ 更新 hook 文件說明
- [x] M2：SKILL.md 加「有沒有變化」快捷路徑 + 修 /loop 範例 interval（30s→1m + 警告）
- [x] M3：進度檔更新並 commit

## 進度日誌

### M1 — 修 autogo-prefetch.ps1 regex

將 alias 捕捉從 `([^\-].*?)(?=...)` 改為 `((?:[a-zA-Z0-9_\-]+)(?:\s+[a-zA-Z0-9_\-]+)*)`，
只捕捉 ASCII 識別符 token（字母/數字/底線/連字符），碰到中文或其他 Unicode 字元即停止。
同時更新 header 說明。

## Fallback 指引
- rollback hook：`git revert HEAD` 在 gs-claude-config repo
- rollback SKILL.md 同上
- 影響檔案：`~/.claude/hooks/autogo-prefetch.ps1`、`~/.claude/skills/autogo/SKILL.md`
