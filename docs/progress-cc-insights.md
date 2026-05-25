# Progress — cc-insights skill

## 目標
新增 `/cc-insights` skill，掃 `~/.claude/projects/<sanitized-cwd>/*.jsonl` 抽出對下一個開發任務有用的 pattern：工具使用頻率、檔案熱點、Bash 指令熱度、重複錯誤、token hotspots。每個 section 由 Claude 額外加上具體可執行的改進建議（補 CLAUDE.md、寫 hook、加 allowlist、拆 subagent）。

## 計畫 milestones
- **M1** — 探索環境 + 建立 skill 骨架（SKILL.md + 目錄）
- **M2** — 寫主腳本 `scripts/Invoke-CCInsights.ps1`（5 個 section、6 個參數）
- **M3** — 對真實 JSONL smoke test（驗證 schema 假設）
- **M4** — 收尾：CRLF 換行、寫進度檔、commit

## 進度日誌

### M1 — 環境探索 + skeleton
- `~/.claude/skills/` symlink → `C:\Users\User\gs-claude-config\skills\`（chezmoi-managed git repo）
- 範本：看 `save-to-obsidian/SKILL.md`、`language-tutor/`（後者有 PROGRESS.md + 額外 script 的先例）
- JSONL schema 確認：
  - 頂層 `type`: `user` / `assistant` / `attachment` / `permission-mode` / `file-history-snapshot`
  - `assistant.message.usage.{input_tokens,output_tokens,cache_read_input_tokens,cache_creation_input_tokens}` 存 token 用量
  - `assistant.message.content[]` items 的 `type`: `thinking` / `text` / `tool_use`（後者帶 `name`、`input`）
  - `user.message.content` 若為 array → 內含 `tool_result`，error 用 `is_error:true` 標記，`content` 可為 string 或 `[{type:text,text:...}]`
  - 每條 message 都帶 `cwd`、`sessionId`、`gitBranch`、`timestamp`
- 產出：`skills/cc-insights/SKILL.md`（trigger phrases、5 個 action mapping）

### M2 — 主腳本
- `scripts/Invoke-CCInsights.ps1`，PS 7.0+
- 參數：`-Days` (7)、`-Top` (20)、`-Section` (all/tools/files/bash/errors/tokens)、`-ProjectFilter`、`-OutFile`、`-ProjectsRoot`
- 五個聚合器：`$toolCounts`、`$filePaths`（read/edit/write 分開計）、`$bashCmds`（trim + 截 200 chars）、`$errorPatterns`（whitespace 壓縮 + 截 120 chars 當 signature）、`$sessionStats`（per-session 加總 token）
- Read/Edit/Write/MultiEdit/NotebookEdit 都會落 file heatmap
- 表格用 markdown，pipe `|` 在 Bash 指令/error signature 內會 escape

### M3 — smoke test
- 跑 `Invoke-CCInsights.ps1 -Days 7 -Top 10`
- 結果：32 sessions / 11129 messages，5 個 section 全部產出有意義資料
- 真實 actionable insights 抽到的例子：
  - "File has not been read yet" tool error 出現 **11 次** → 可寫 PreToolUse hook 阻止 / 加進 CLAUDE.md
  - 1 個 autogo session output tokens 達 **1.38M** → 該類重構任務需拆 subagent
  - `git log --oneline -3/-4/-5/-6` 反覆出現 → 直接加進 `permissions.allow`
  - `autogo/web/static/dashboard.js`、`autogo/web/app.py` 各被編輯 40+ 次 → 該補進 autogo CLAUDE.md key files
- 已知小瑕疵：error signature 偶有殘留 ANSI escape codes（`[90m` 等），不影響排序，可在後續迭代清理

### M4 — 收尾
- 兩個 skill 檔轉成 CRLF（SKILL.md 65 CRLF；ps1 252 CRLF）
- 寫此進度檔 `docs/progress-cc-insights.md`
- commit 到 gs-claude-config（chezmoi source）

## Commit 範圍
- 新檔：
  - `skills/cc-insights/SKILL.md`
  - `skills/cc-insights/scripts/Invoke-CCInsights.ps1`
  - `docs/progress-cc-insights.md`

## Fallback / rollback 指引
- 整個 skill 自包含於 `skills/cc-insights/` — 直接 `Remove-Item -Recurse` 即可移除
- 不改動任何全域設定（settings.json 等）
- 不依賴外部套件，只用 PS 7 內建 cmdlets

## 後續可做（不在本次範圍）
1. 清理 error signature 的 ANSI escape codes，提升可讀性
2. 加入 trend 維度（同樣 metric 對比上週 vs 本週）
3. 把 8 個 section 拆成 sub-skill 讓 Claude 按需呼叫，降低主 prompt token
4. 加 `-Json` 旗標讓輸出可餵給其他工具（例如直接生成 settings.json patch）
5. 串接 `/fewer-permission-prompts` — cc-insights 抽到的高頻 Bash 自動 propose 給 allowlist

---

## v2：repo-scoped + 表面看不到的 info（後續迭代）

### 目標
使用者反饋：「希望 cc-insights 能更專門萃取『跟目前 repo 相關但 CLI 表面看不到』的資訊」。
新增三個 section 主打 context recovery：過往 user prompts、subagent 報告 preview、git-uncommitted 檔案。

### Milestones

#### v2-M1 — `-Repo` 旗標 + auto-detect git root
- commit `18da56a`
- 加 `-Repo <path|auto>`：auto 會 `git -C $PWD rev-parse --show-toplevel`，找不到就退回 PWD
- 訊息迴圈內依 `msg.cwd` prefix 過濾（case-insensitive、容忍尾端斜線）
- header 顯示 active repo
- ValidateSet 加入 `prompts` / `subagents` / `untracked` 占位

#### v2-M2 — prompts section
- commit `f709c2f`
- 把 `type=user` 且 `content` 為 string 的 message 收集成 prompt log
- 過濾 `<command-message>` / `<local-command-stdout>` 包裝
- 按 timestamp DESC 排序，輸出 top N（截斷 140 chars）
- 解決：「我上週在這 repo 試過什麼問題」context recovery

#### v2-M3 — subagents + untracked sections
- commit `74f7654`
- **subagents**：抽 tool_use name='Agent' 的 description / subagent_type / prompt 開頭；用 `tool_use_id` 對應後續的 tool_result，撈 200 chars preview。表面上 Claude 主對話只顯示「Agent({...}) (~Nk tokens)」這種折疊，subagent 的研究產出很容易遺失
- **untracked**：跑 `git -C $Repo status --porcelain`，cross-ref `$filePaths` heatmap。列出 Claude 動過但狀態是 `??` / `M` / `A` / `D` 的檔案。捕捉「改了一半沒 commit」的 WIP

#### v2-M4 — SKILL.md 更新、CRLF、progress 補記、final commit
- SKILL.md：description 擴寫提到 repo-scoped；觸發語句加入「這個 repo 之前做過什麼」「subagent 跑了什麼」「我有什麼沒 commit」；旗標表加 `-Repo`；section action 表擴成 8 列；新增執行步驟 2「判斷是否 repo-scoped」
- 本進度檔新增 v2 段
- final commit

### 真實 smoke test 結果（在本 conversation 跑的）
- `-Section subagents`：成功撈到 7ca37792 session 裡呼叫的 `claude-code-guide` agent（"Claude Code hidden log methods"），result preview 顯示 200 chars
- `-Section untracked -Repo gs-claude-config`：列出 `Invoke-CCInsights.ps1` 為 `M`（modified）—因為當時 v2-M3 的 edits 還沒 commit
- `-Repo C:\Users\User\autogo -Section tools -Days 30`：90 sessions / 18991 messages 正確 filter 到只剩 autogo 的活動

### Fallback / rollback 指引（v2）
- v2 的 3 個 commit 都是純加法（新欄位 / 新 section / 新旗標），未動到 v1 行為。要降版直接：
  - `git revert 74f7654 f709c2f 18da56a` 即可回到 v1（bc8e077）
- 完全移除 skill：`Remove-Item -Recurse skills/cc-insights/`，沒有任何全域副作用
