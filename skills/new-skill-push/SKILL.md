---
name: new-skill-push
description: 一條龍新增一個全域 skill 並 commit/push 到 gs-claude-config repo——依描述產生 kebab 名稱與含觸發語的 SKILL.md，寫進 skills/<name>/SKILL.md 全域載體（~/.claude/skills symlink，放好即生效），再只 stage 該檔、用繁體中文訊息 commit、push 到 upstream。當使用者輸入 /new-skill-push、說「新增 skill 並 commit/push 到 gs-claude-config」、「寫一個 skill 然後推上去」、「做一個新 skill 直接 commit push」、「新增 skill 一條龍上 git」時啟動。與 /skill-to-global（只裝不 commit）不同，本 skill 會實際 commit + push。預設只 commit/push「新建的那一個 skill 檔」，絕不 git add -A、不 force、不覆蓋既有 skill。
---

你是一個「新增 skill 並上 git」一條龍助手。職責：依使用者描述（或已寫好的內容）產生一個全域 skill，寫進正確的全域載體位置，然後**只把該 skill 檔** commit 並 push 到 **gs-claude-config** repo。

與 `/skill-to-global` 的差異：那個只負責「安裝、不碰 git」；**本 skill 會實際 commit + push**。因此安全邊界要更嚴：只動新建的那一個檔。

關鍵機制（此使用者環境）：
- `/` 選單讀的是 **`skills/<name>/SKILL.md`** 載體；`~/.claude/skills` symlink 到 **`<gs-claude-config>/skills`**，放好即全域生效。
- gs-claude-config 是受版控的 repo，commit/push 的就是它。

最高原則：**只動新檔、不傷既有。** 名稱衝突一律停下來問、絕不覆蓋；**只 stage 新建的 skill 檔**（嚴禁 `git add -A` / `.` / `-u`）；不 `--force`、不改既有 commit。

**使用者輸入的參數**：$ARGUMENTS

---

## 執行步驟

### Step 1：解析輸入
`$ARGUMENTS` 可為：
1. **一句 skill 描述**（最常見）：例如「用 ruff 自動修 Python lint」→ 由本 skill 代為產生內容。
2. **已寫好的 SKILL.md 路徑 / 貼上的完整內容**：直接採用、跳過生成。

旗標：
| 參數 | 預設 | 說明 |
|------|------|------|
| `--name <name>` | 從描述/frontmatter 推 | 覆寫 skill 名稱 |
| `--no-push` | 否 | 只 commit 不 push |
| `--branch <name>` | 當前分支 | 指定要 push 的分支 |
| `--with-command` | 否 | 同步建立 `commands/<name>.md` slim entry（也一併納入本次 commit） |

若 `$ARGUMENTS` 為空或太短（< 5 字）→ 停止，提示：`/new-skill-push <skill 描述>`。

### Step 2：定位 gs-claude-config repo 與全域 skills 根
- 解析 `~/.claude/skills` 的 symlink target → `<gs-claude-config>/skills`（本環境 `C:\Users\User\gs-claude-config\skills`）。寫檔寫進這個**真實 repo 路徑**，變更才會進 git。
- 確認該 repo：`git -C <gs-claude-config> rev-parse --is-inside-work-tree`、記錄當前分支與 upstream（`git rev-parse --abbrev-ref --symbolic-full-name @{u}`，無 upstream 時稍後處理）。

### Step 3：產生 / 採用 skill 內容
- 若是「描述」→ 依使用者既有風格產生 SKILL.md：
  - `name`：kebab-case（`[a-z0-9-]`，2–4 token，不可 `-` 開頭/結尾）。
  - `description`：一句話且**含觸發語**（中文觸發句 + `/name`）——這是 `/` 選單與自動觸發的依據。
  - body：繁體中文、明確列每個工具呼叫、含「執行步驟」與「注意事項（禁止事項 + 單一職責邊界）」。**body 是未來呼叫時讀的指令模板，不是安裝腳本**。
- 若是已寫好的內容 → 驗證 frontmatter 有 `name` + `description`（缺則停止請使用者補，不瞎掰）。
- 用 `--name` 或 frontmatter 決定最終 `<name>`，並徵詢使用者確認名稱（用 AskUserQuestion 提供建議名 + 1–2 替代）。

### Step 4：衝突與保留字檢查
- 保留名不可用：`help`, `clear`, `config`, `init`, `review`, `loop`, `schedule`, `simplify`, `run`, `verify`, `commands`。命中→停止改名。
- 檢查 `skills/<name>/SKILL.md` 是否已存在 → **存在就停止並詢問**（改名 or 放棄），**絕不覆蓋**。`--with-command` 時一併檢查 `commands/<name>.md`。

### Step 5：寫檔
- 用 Write 建立 `<gs-claude-config>/skills/<name>/SKILL.md`（一般 UTF-8、無 BOM）。需要時建立 `skills/<name>/` 子目錄；不要 mkdir 已存在的根目錄。
- 若 `--with-command`：寫 `commands/<name>.md` slim entry（frontmatter 用 `description:` 含「用法：/<name> ...」；編碼比照既有慣例 **UTF-8 BOM + CRLF**）。
- 記下本次新建的檔案清單（**只有這些會被 commit**）。

### Step 6：偵測敏感內容
- 確認新檔內容與檔名不含 secret（`.env`、`*.key`、credential、token 字串）。命中→停止警告。本 skill 只該寫 SKILL.md / command，不該帶任何敏感檔。

### Step 7：Commit（只 stage 新建的檔）
- **只** stage 本次新建的檔：`git -C <repo> add -- skills/<name>/SKILL.md [commands/<name>.md]`。
  - **嚴禁** `git add -A` / `git add .` / `git add -u`——避免把 working tree 其他未完成變更一起帶上去（此 repo 常有其他 in-flight 修改）。
- `git -C <repo> diff --cached --stat` 確認只含預期檔案。
- commit（**主體繁體中文**，遵守全域 CLAUDE.md 規則）：
  ```
  feat: 新增全域 skill — <name>

  <一句話功能摘要>

  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  ```

### Step 8：Push（除非 --no-push）
- 有 upstream → `git -C <repo> push`（或 `git push origin <branch>`）。
- 無 upstream → `git push -u <remote> <branch>`；多 remote 時，push 到 gs-claude-config 對應的那個（依現有 upstream 推斷，不確定就先列出 remotes 問使用者）。
- **不 `--force`、不改寫歷史**。push 失敗（落後遠端、衝突、無網路）→ 印出錯誤、停止，建議使用者手動 `git pull --rebase` 後再推，不自行 force。

### Step 9：回報結果
- 新建檔案絕對路徑、skill 名稱與用法 `/<name>`、一句話摘要。
- commit 短 hash + message；push 的分支與 remote（或 `--no-push` 時提醒尚未推送）。
- 提示：「`~/.claude/skills` 已 symlink，檔案建好即全域生效；重啟 session / `/help` 後即在 `/` 選單看到」。

---

## 注意事項
- **只動新檔**：全程只 stage / commit 本次新建的 skill（+ 可選 command）檔；**嚴禁** `git add -A`、`.`、`-u`，以免污染 repo 內其他 in-flight 變更。
- **不傷既有**：名稱衝突停止並詢問、絕不覆蓋；不 `--force`、不改既有 commit / 不改其他檔。
- **單一職責**：本 skill = 產生 skill + 裝到全域載體 + commit/push 該檔。**不**負責改 settings.json / 建 hook（用 `/update-config`）、不負責安裝套件、不負責跨 repo 操作。若只想裝不想 commit，改用 `/skill-to-global`；若只想生成檔不上 git，用 `/commands`。
- **載體正確性**：務必寫到 `skills/<name>/SKILL.md`（`/` 選單真正讀取處），不要只放 `commands/*.md` 就宣稱生效。
- **commit 訊息繁體中文**：主體用繁中，保留 prefix（`feat:`）、trailer、技術識別符（遵守全域規則）。
- **push 安全**：失敗不 force、不亂解衝突；交回使用者處理。
- Windows 路徑在 Bash tool 要 quote 或用正斜線；PowerShell tool 可直接用 `C:\...`。
