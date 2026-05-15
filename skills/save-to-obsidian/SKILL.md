---
name: save-to-obsidian
description: 把當前對話彙整成 Markdown 並存進使用者的 Obsidian vault。當使用者輸入 /save-to-obsidian、說「存到 Obsidian」、「匯入到知識庫」、「把剛剛這段存起來（在 Obsidian）」、「加到 Obsidian 筆記」時啟動。會自動判斷主題分類到對應子資料夾（健康/量化/工程/產業），補上 frontmatter、tags、日期，並回傳 obsidian:// URI 讓使用者一鍵在 Obsidian 開啟。
---

# /save-to-obsidian — 對話彙整成 Obsidian 筆記

當使用者要求把對話內容存進 Obsidian 時啟動，把指定段落彙整成一份結構化的 Markdown 筆記寫入本機 vault。

## Vault 設定

- **Vault 路徑**：`C:\Users\User\Documents\Obsidian Vault\`
- **預設子資料夾對應**：
  - 健康、人因工程、辦公習慣、運動 → `健康筆記/`
  - 量化策略、回測、因子、市場分析 → `量化研究/`
  - 工程、系統設計、架構、工具設定 → `工程筆記/`
  - 半導體、產業鏈、總經 → `產業研究/`
  - 不確定 → `Inbox/`（之後再手動歸類）

如果使用者明確指定資料夾，以使用者指定為準；沒指定就依上述規則自動判斷。

## 執行步驟

1. **判斷主題**：從對話中抓出這份筆記的核心主題與適合的標籤
2. **決定檔名**：用主題寫成繁體中文檔名（避免特殊字元 `\ / : * ? " < > |`），如有同名檔案則在結尾加 `-2`、`-3`
3. **決定子資料夾**：依上述對應規則或使用者指定
4. **產生 frontmatter**：
   ```yaml
   ---
   title: <筆記標題>
   created: <今天日期 YYYY-MM-DD>
   tags:
     - <tag1>
     - <tag2>
   source: Claude Code 對話彙整
   ---
   ```
5. **整理內文**：
   - 用 `##` 分章節，最上層用一個 `#` 標題
   - 重點用粗體、清單、表格呈現
   - 結尾放「相關筆記」區塊，列 2–3 個 `[[wiki-link]]`（可指向尚不存在的筆記，這在 Obsidian 是合法用法）
6. **寫入檔案**：用 Write tool 寫到 `C:\Users\User\Documents\Obsidian Vault\<子資料夾>\<檔名>.md`
   - Write tool 會自動建立缺失的父資料夾
7. **回報**：告知使用者完整路徑，並提供 `obsidian://open?vault=Obsidian%20Vault&file=<URL-encoded-path>` 連結讓使用者可以一鍵在 Obsidian 開啟（vault 名稱含空格要 encode 成 `%20`，子資料夾用 `%2F` 分隔）

## 注意事項

- 檔名與內文一律繁體中文（除非使用者指定英文）
- 不要重複寫入相同主題的筆記；若偵測到已有相近檔名，先告知使用者並詢問要覆蓋還是建新版本
- 若使用者只給一個關鍵字（例如「把剛剛那段存起來」），就把當前對話最近一段技術/知識內容彙整即可，不要追問太多
- Windows 上若要寫到 `~/.claude/commands/` 或 `~/.claude/skills/`，記得轉成 CRLF 換行（用 Write tool 預設是 LF，需用 PowerShell 後處理）
