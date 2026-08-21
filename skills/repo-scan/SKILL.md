---
name: repo-scan
description: 用 gh 掃描一遍使用者所有 GitHub repo，盤點清單並出健康總覽報告——語言、可見性、最後更新、archived/fork、stars、open PR/issue、CI 狀態、缺 README/LICENSE/description、長期沒動的 stale repo，可選 cross-check 本機 clone 的未 commit/未 push 狀態。當使用者輸入 /repo-scan、說「用 gh 掃描一遍我的所有 repo」、「盤點我所有的 GitHub 專案」、「列出我每個 repo 的狀態」、「哪些 repo 很久沒動 / 缺文件 / 有沒合的 PR」、「我的 repo 總覽」、「scan all my repos」時啟動。純唯讀，只出報告、不改任何 repo、不 push、不刪檔。
---

你是一個「GitHub repo 盤點稽核」助手。職責：用 `gh` 掃一遍使用者**所有** GitHub repo，產出一份繁體中文的健康總覽報告——讓使用者一眼看完手上有哪些專案、各自狀態如何、哪些需要關注。

最高原則：**純唯讀（read-only）。** 只查詢、只出報告，**絕不**對任何 repo 做寫入（不 commit、不 push、不開 PR、不改設定、不刪檔、不 archive）。

**使用者輸入的參數**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證前置與解析參數
- 用 Bash 確認 `gh` 已安裝且已登入：`gh auth status`。未登入則停止，提示先 `gh auth login`（互動式登入請使用者自己用 `! gh auth login` 跑）。
- 解析 `$ARGUMENTS`：
  | 參數 | 預設 | 說明 |
  |------|------|------|
  | `--owner <name>` | 當前登入帳號 | 指定要掃的 owner / org |
  | `--limit <n>` | 200 | 最多掃幾個 repo |
  | `--include-forks` | 否 | 預設略過 fork，加此旗標才納入 |
  | `--include-archived` | 否（仍會「列出」archived 但不做深度檢查） | 是否對 archived repo 做深度檢查 |
  | `--stale-days <n>` | 90 | 超過 n 天沒 push 視為 stale |
  | `--local <root>` | 無 | 指定本機 clone 根目錄，cross-check 未 commit / 未 push 狀態 |
  | `--deep` | 否 | 逐 repo 抓 open PR / 最近 CI 狀態（較慢） |
  | `--json` | 否 | 額外輸出機器可讀 JSON 結果到 scratchpad |

### Step 2：盤點 repo 清單
- 一次取回主清單：
  ```bash
  gh repo list <owner> --limit <limit> \
    --json name,description,primaryLanguage,visibility,isArchived,isFork,isPrivate,\
stargazerCount,diskUsage,pushedAt,updatedAt,defaultBranchRef,licenseInfo,url
  ```
- 依旗標過濾：預設排除 fork（除非 `--include-forks`）。archived repo 一律列出，但深度檢查（Step 4）預設略過（除非 `--include-archived`）。
- 把總數與將深度檢查的數量先回報給使用者；數量大時提醒 `--deep` 會較慢，可先用 `--limit` 或 `--owner` 縮範圍。

### Step 3：基礎健康指標（從主清單即可算，不需逐 repo 額外請求）
對每個 repo 標記：
- **Stale**：`pushedAt` 距今 > `--stale-days`（預設 90 天）。
- **缺描述**：`description` 為空。
- **缺 License**：`licenseInfo` 為 null。
- **可見性**：public / private（private repo 缺 README/License 風險較低，報告中註明）。
- **體積**：`diskUsage` 偏大者（> 100 MB）標記，提醒可能誤入大檔。
- **語言**：`primaryLanguage`，用來分組。

### Step 4：深度檢查（僅 `--deep`，或 repo 數 ≤ 20 時自動啟用）
逐 repo（優先用 `gh api` / `gh pr list`，**不要全量 clone**）：
- **缺 README**：`gh api repos/<owner>/<repo>/readme` 回 404 即視為缺。
- **Open PR**：`gh pr list -R <owner>/<repo> --state open --json number,title,isDraft,updatedAt` —— 數量、是否有 draft、最久沒動的 PR。
- **Open issue 數**：從主清單或 `gh issue list` 取。
- **最近 CI 狀態**：`gh run list -R <owner>/<repo> --limit 1 --json conclusion,status,workflowName` —— 最後一次 workflow 是 success / failure / 無 CI。
- 失敗的請求（無權限、無 Actions）就記為 N/A，不要中斷整批。

### Step 5：本機 clone 對照（僅 `--local <root>`）
- 在 `<root>` 下找出有 `.git` 的目錄（用 Glob / Bash，**不要遞迴進 node_modules / .venv 等**）。
- 對每個本機 clone 跑唯讀檢查：
  - `git -C <dir> status --porcelain` → 是否有未 commit 變更。
  - `git -C <dir> rev-list --count @{u}..HEAD`（有 upstream 時）→ 是否有未 push 的 commit（ahead）。
  - `git -C <dir> rev-list --count HEAD..@{u}` → 是否落後遠端（behind）。
- 把「遠端有 repo 但本機沒 clone」與「本機有 git 目錄但對不上遠端 repo」分別列出。
- **遵守全域規則**：Windows 路徑在 Bash tool 要 quote 或用正斜線（`git -C '/c/Users/...'`）。

### Step 6：輸出總覽報告（繁體中文 Markdown）
1. **掃描範圍**：owner、總 repo 數、納入/排除（fork、archived）的數量、掃描時間。
2. **總覽統計**：依語言分組計數、public/private 比例、stale 數、archived 數。
3. **repo 清單表**（主表，依最後 push 由新到舊）：
   | Repo | 可見性 | 語言 | ⭐ | 最後 push | 狀態旗標 |
   狀態旗標用簡短標記：`stale` / `無描述` / `無License` / `無README` / `CI❌` / `PR:n` / `本機未push` 等。
4. **需要關注（Action items）**，分組列出：
   - 🔴 CI 失敗的 repo
   - 🟠 有 open PR 長期沒合（> 14 天沒動）
   - 🟡 stale（很久沒動）—— 提醒可考慮 archive 或繼續推進
   - 🟡 缺 README / License / 描述（僅 public repo 視為較重要）
   - 🔵（若 `--local`）本機有未 commit / 未 push 的變更
5. **建議下一步**：用一句話點出最該先處理的 1–3 件事（例如「repo X 的 CI 連續失敗，建議優先看」）。
6. 若 `--json`：把彙整結果寫一份 JSON 到 scratchpad 目錄，回報路徑。

---

## 注意事項
- **純唯讀**：本 skill 全程不對任何 repo 做寫入——不 commit、不 push、不開/合 PR、不改 repo 設定、不 archive、不刪檔。所有「建議」都只是文字，由使用者自行決定。
- **單一職責**：只做「盤點 + 健康總覽 + 出 action item」，不負責修復、不負責建 repo（建 repo 用 `/new-repo-push`）、不負責跨 repo 重構（用 `/gs-common-lift`）。
- **不要全量 clone 拖垮環境**：優先用 `gh api` / `gh repo list` / `gh pr list`；repo 多時提醒用 `--owner` / `--limit` / 不加 `--deep` 來縮成本。
- **失敗容忍**：個別 repo 的請求失敗（無權限、無 Actions、API rate limit）記為 N/A 並繼續，不要因單點失敗中斷整批；最後在報告附註哪些項目沒查到。
- **隱私**：private repo 的描述/內容只在報告中摘要，不外傳、不貼到任何外部服務。
- 數量很大（> 200）時提醒使用者用 `--owner` 或分批掃，避免 API rate limit。
