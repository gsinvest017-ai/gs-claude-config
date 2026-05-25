---
name: cc-insights
description: 從 ~/.claude/projects/ 底下的 session JSONL 挖出對開發任務有幫助的 pattern，包含 CLI 表面看不到的 repo-scoped 資訊（過往 prompts、subagent 報告、git-uncommitted 檔案）。當使用者輸入 /cc-insights、說「分析我的 claude 使用紀錄」、「我最常用什麼工具」、「我最近常踩什麼坑」、「找出 token 黑洞」、「掃 session log 出 insights」、「這個 repo 我之前做過什麼」、「subagent 跑出來的結果」、「我有什麼沒 commit 的修改」時啟動。輸出 8 個 section：tool 頻率、檔案熱點、Bash 指令清單、重複錯誤、token hotspots、recent prompts、subagent calls、git-untracked，並依資料給出具體可執行的改進建議。
---

# /cc-insights — 從 session log 挖開發 insight

把 `~/.claude/projects/<sanitized-cwd>/*.jsonl` 當資料來源，撈出對使用者「下一個開發任務」最有幫助的 pattern，並轉成可執行的改進建議。**不是**單純 dump 數據——每個 section 都要附「下一步建議」。

設計重點：**把 CLI 表面看不到的東西撈出來**——過往對話 prompts、subagent 跑出來的研究結果、Claude 編輯過但還沒 commit 的檔案，這些一旦關掉視窗就很難回想。

## 觸發

- `/cc-insights`（無參數 → 預設掃過去 7 天、全 section）
- `/cc-insights --days 30`、`/cc-insights --top 30`
- `/cc-insights --section <name>` — 單一 section：`tools` / `files` / `bash` / `errors` / `tokens` / `prompts` / `subagents` / `untracked` / `all`
- `/cc-insights --project gs-strategy` — cwd 目錄名稱子字串過濾
- `/cc-insights --repo auto` — 自動偵測使用者當前 cwd 的 git 根，作為 repo filter（會啟用 untracked section）
- `/cc-insights --repo C:\Users\User\autogo` — 明確指定 repo 路徑
- 自然語句觸發（同 description 列出的關鍵字）

## 執行步驟

1. **解析參數**：把使用者輸入的旗標轉成 PowerShell 參數。預設 `--days 7 --top 20 --section all`。

2. **判斷是否要 repo-scoped**：使用者若提到「這個 repo」「目前 repo」「我有什麼沒 commit」「subagent 跑了什麼」等與 repo 強相關的語境 → 自動加上 `-Repo auto`（讓腳本去找 git 根）。若使用者要求看「全部」「整體」「跨專案」就不加。

3. **呼叫主腳本**：用 PowerShell tool 執行：
   ```powershell
   & "C:\Users\User\gs-claude-config\skills\cc-insights\scripts\Invoke-CCInsights.ps1" `
       -Days <N> -Top <N> -Section <name> -ProjectFilter "<substr>" -Repo "<path-or-auto>"
   ```
   腳本回傳一份 Markdown 報告。

4. **加上「下一步建議」**：腳本只給原始 pattern，**你要再加一段** "## 建議 / 下一步可做"，依當下 data 給 3~5 條具體 action（範例見下方 mapping 表）。

5. **回報**：直接把 markdown 結果輸出給使用者，**不要**另存檔（除非使用者明確要求 `--out-file`）。若使用者要存到 Obsidian，引導他接著用 `/save-to-obsidian`。

## 主腳本提供的旗標

| 旗標 | 預設 | 說明 |
|---|---|---|
| `-Days` | 7 | 只掃這幾天內 modified 的 JSONL |
| `-Top` | 20 | 每個排行榜取前幾名 |
| `-Section` | `all` | `tools` / `files` / `bash` / `errors` / `tokens` / `prompts` / `subagents` / `untracked` / `all` |
| `-ProjectFilter` | `''` | cwd 目錄名子字串過濾（例：`gs-strategy`） |
| `-Repo` | `''` | repo 路徑（絕對路徑）或 `auto`（從 PWD 解析 git 根）。設了之後依 cwd prefix 過濾 |
| `-OutFile` | `''` | 若指定則寫檔案（同時印到 stdout） |
| `-ProjectsRoot` | `~/.claude/projects` | session JSONL 根目錄 |

## 八個 section 對應的可執行 action

| Section | 撈什麼 | 看到什麼 → 做什麼 |
|---|---|---|
| **tools** | tool_use 名稱頻率 | Bash 佔比過高 → 包 skill / 加 allow；Grep 比例極低 → 提醒先 Grep 再 Read；Agent 多 → 確認 subagent context 隔離有用 |
| **files** | Read/Edit/Write 各別計數 | Top 檔案 → 寫進該 repo CLAUDE.md key files；同檔反覆讀 → 補 import path 或 entry doc |
| **bash** | Bash 指令字串頻率 | 反覆出現 → `permissions.allow` 或 `/fewer-permission-prompts`；複雜 pipeline → 包成 `.ps1` |
| **errors** | tool_result.is_error 簽名 | 同一錯誤 >3 次 → CLAUDE.md 規則 / PreToolUse hook |
| **tokens** | per-session input+output token | 單 session > 100k → 拆 subagent；cache hit 低 → 留意 prompt 結構 |
| **prompts** | 最近 user prompts（string content） | 看到上週試過但沒收尾的問題 → 接著做完；重複問同個東西 → 答案寫進 CLAUDE.md |
| **subagents** | Agent tool_use + 對應 tool_result preview | subagent 跑出來的研究 → 重要的存到 Obsidian / CLAUDE.md，免得下次再花一次 |
| **untracked** | file heatmap × `git status --porcelain` | Claude 改過但 `??`/`M` 的檔案 → commit 或 stash，避免遺失工作 |

## 注意事項

- 腳本是 read-only：只讀 JSONL + `git status`/`git rev-parse`，不會改 settings.json、不會 commit。
- JSONL 檔可能很大（單檔 MB 級），預設 `-Days 7` 就好；要全量掃才用 `-Days 365`。
- `untracked` section 需要 `-Repo`，否則會輸出提示。`-Repo auto` 會在 `Get-Location` 路徑跑 `git rev-parse --show-toplevel`，若不是 git 根就退回 PWD。
- 若 schema 變動（Claude Code 升級）腳本可能撈不到欄位 → 直接看 `scripts/Invoke-CCInsights.ps1` 內 `$msg.message.content` 與 `$msg.message.usage` 的取用路徑修正。
- 不要把報告自動存到任何地方；除非使用者說「存到 Obsidian」或指定 `--out-file`。
- 報告中所有路徑都用絕對路徑，方便使用者直接複製。
