---
name: cc-insights
description: 從 ~/.claude/projects/ 底下的 session JSONL 挖出對開發任務有幫助的 pattern。當使用者輸入 /cc-insights、說「分析我的 claude 使用紀錄」、「我最常用什麼工具」、「我最近常踩什麼坑」、「找出 token 黑洞」、「掃 session log 出 insights」時啟動。輸出五個 section：tool 頻率、檔案熱點、Bash 指令清單、重複錯誤、token hotspots，並依資料給出具體可執行的改進建議（補 CLAUDE.md / 寫 hook / 加 allowlist / 拆 subagent）。
---

# /cc-insights — 從 session log 挖開發 insight

把 `~/.claude/projects/<sanitized-cwd>/*.jsonl` 當資料來源，撈出對使用者「下一個開發任務」最有幫助的 pattern，並轉成可執行的改進建議。**不是**單純 dump 數據——每個 section 都要附「下一步建議」。

## 觸發

- `/cc-insights`（無參數 → 預設掃過去 7 天）
- `/cc-insights --days 30`、`/cc-insights --top 30`
- `/cc-insights --section errors`（只跑單一 section：`tools` / `files` / `bash` / `errors` / `tokens` / `all`）
- `/cc-insights --project gs-strategy`（只看特定 cwd 子字串）
- 自然語句觸發（同 description 列出的關鍵字）

## 執行步驟

1. **解析參數**：把使用者輸入的旗標轉成 PowerShell 參數。預設 `--days 7 --top 20 --section all`。

2. **呼叫主腳本**：用 PowerShell tool 執行：
   ```powershell
   & "C:\Users\User\gs-claude-config\skills\cc-insights\scripts\Invoke-CCInsights.ps1" `
       -Days <N> -Top <N> -Section <name> -ProjectFilter "<substr>"
   ```
   腳本回傳一份 Markdown 報告（已含 5 個 section 的表格）。

3. **加上「下一步建議」**：腳本只給原始 pattern，**你要再加一段** "## 建議 / 下一步可做"，依當下 data 給 3~5 條具體 action。範例：
   - 看到 `Bash` 計數超過其他工具 3 倍 → 建議：找出最常見 Bash 指令包成 skill，或加進 `permissions.allow`
   - 看到某檔案出現 >10 次 → 建議：把該檔案路徑加到該專案 CLAUDE.md 的「key files」段
   - 重複錯誤超過 3 次 → 建議：寫成 CLAUDE.md 規則或 PreToolUse hook 防止再發生
   - 某 session token > 100k → 建議：該類任務改用 subagent 隔離 context
   - 某 Bash 指令在 allowlist 之外被反覆執行 → 建議：跑 `/fewer-permission-prompts`

4. **回報**：直接把 markdown 結果輸出給使用者，**不要**另存檔（除非使用者明確要求 `--out-file`）。若使用者要存到 Obsidian，引導他接著用 `/save-to-obsidian`。

## 主腳本提供的旗標

| 旗標 | 預設 | 說明 |
|---|---|---|
| `-Days` | 7 | 只掃這幾天內 modified 的 JSONL |
| `-Top` | 20 | 每個排行榜取前幾名 |
| `-Section` | `all` | `tools` / `files` / `bash` / `errors` / `tokens` / `all` |
| `-ProjectFilter` | `''` | cwd 子字串過濾（例：`gs-strategy`） |
| `-OutFile` | `''` | 若指定則寫檔案（同時印到 stdout） |
| `-ProjectsRoot` | `~/.claude/projects` | session JSONL 根目錄 |

## 五個 section 對應的可執行 action

| Section | 看到什麼 → 做什麼 |
|---|---|
| **tools** | Bash 佔比過高 → 包 skill / 加 allow；Grep 比例極低 → 提醒善用 Grep 而非整檔 cat；Agent 多 → 確認 subagent context 隔離有用到 |
| **files** | Top 檔案 → 寫進該專案 CLAUDE.md key files 區；同檔被反覆讀 → 補 import path 或 entry doc |
| **bash** | 反覆出現的指令 → `permissions.allow` 或 `/fewer-permission-prompts`；複雜 pipeline → 包成 `.ps1` 或 skill |
| **errors** | 同一錯誤 >3 次 → CLAUDE.md 規則 / PreToolUse hook；某工具錯誤率高 → 看是不是該換工具或補包裝 |
| **tokens** | 單 session > 100k → 拆 subagent；cache hit 低 → 留意 prompt 結構；某 cwd 整體高 → 考慮拆專案 |

## 注意事項

- 腳本是 read-only：只讀 JSONL，不會改 settings.json / 不會 commit。
- JSONL 檔可能很大（單檔 MB 級），預設 `-Days 7` 就好；要全量掃才用 `-Days 365`。
- 若 schema 變動（Claude Code 升級）腳本可能撈不到欄位 → 直接看 `scripts/Invoke-CCInsights.ps1` 內的 `$msg.message.content` 取用路徑修正。
- 不要把報告自動存到任何地方；除非使用者說「存到 Obsidian」或指定 `--out-file`。
- 報告中所有路徑都用絕對路徑，方便使用者直接複製。
