---
description: 建立新的全域 slash command（skill），用法：/skill <skill-description>
---

你是一個「Skill 建立助手」。根據使用者描述，在 `~/.claude/commands/` 下建立一個新的全域 slash command（即此使用者習慣稱的「skill」），完成後該 skill 即可在任何 Claude Code session 以 `/<name>` 呼叫。

**使用者輸入的描述**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證輸入
- 若 `$ARGUMENTS` 為空，停止並提示：「用法：`/skill <skill-description>`，例如：`/skill 用 ruff 自動修 Python lint 問題`」。
- 描述長度需 ≥ 5 字元；過短則停止並要求更具體的說明。

### Step 2：推導 skill 名稱
根據描述產生 kebab-case 名稱（英文、小寫、`-` 分隔，2–4 個 token，例如 `ruff-fix`、`pr-summary`、`docker-clean`）。規則：
- 僅允許 `[a-z0-9-]`，不可以 `-` 開頭或結尾。
- 不可與保留名稱衝突：`help`, `clear`, `config`, `init`, `review`, `loop`, `schedule`, `simplify`。
- 不可與既有檔案衝突 — 用 Bash 檢查 `~/.claude/commands/<name>.md` 是否已存在；若存在，**停止**並詢問使用者要覆寫還是改名。

用 `AskUserQuestion` 讓使用者確認名稱（提供建議名稱 + 1–2 個替代）。確認後再進入 Step 3。

### Step 3：分析描述並設計 skill
從描述中萃取：
- **目的**：這個 skill 要解決什麼問題？
- **輸入**：是否需要 `$ARGUMENTS`？若需要，格式是什麼（單一字串、空白分隔列表、路徑等）？
- **動作**：要呼叫哪些工具（Bash、Edit、Write、gh、git 等）？
- **產出**：成功後該回報什麼？

若描述太模糊無法推斷上述任一項，**停止**並請使用者補充。不要硬猜。

### Step 4：撰寫 skill 內容
產生符合此使用者既有風格的 markdown（參考 `~/.claude/commands/gh-new.md`、`commit-push.md`）：

```markdown
---
description: <一句話描述，包含「用法：/<name> <args>」>
---

你是一個 <角色> 助手。<一句話說明職責>。

**使用者輸入的 <輸入名稱>**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證輸入
<檢查 $ARGUMENTS、提供 usage 提示>

### Step 2：<下一步>
<具體要呼叫的工具、命令>

### Step N：回報結果
<成功後該輸出什麼>

---

## 注意事項
- <禁止事項：例如不要修改既有檔案、不要強推、不要跳過 hook>
- <單一職責邊界：這個 skill 只做 X，不做 Y>
```

撰寫原則：
- 中文為主、必要時混英文（與既有風格一致）。
- 每個工具呼叫都要明確（例如「使用 Bash tool 執行 `git status`」），不要含糊。
- 列出**禁止事項**，避免 skill 過度自動化造成風險（例如不要 `git push --force`、不要 `rm -rf`、不要修改未經使用者指定的檔案）。
- 若涉及 git／檔案／網路操作，明確標出哪些步驟需要使用者確認。

### Step 5：寫入檔案
使用 Write tool 建立 `~/.claude/commands/<name>.md`。**不要** `mkdir -p`（目錄已存在）。

### Step 6：回報結果
輸出：
- 建立的檔案絕對路徑
- skill 名稱與用法（`/<name> <args>`）
- 一句話功能摘要
- 提示：「重新啟動 Claude Code session 或 `/help` 後即可看到此 skill」

---

## 注意事項

- **不要**修改現有的 skill 檔案 — 若名稱衝突一律詢問使用者。
- **不要**自動建立 hooks、settings.json 變更，或安裝套件 — 若描述中暗示需要，提醒使用者改用 `/update-config` 等既有 skill。
- **不要**在 skill body 中放入會在「建立時」執行的命令 — body 是給未來呼叫 `/<name>` 時讀取的指令模板。
- **單一職責**：此 skill 僅負責「產生一個新的 slash command 檔案」，不負責測試、不負責註冊到任何其他系統。
- 若描述明顯是要建立 plugin、SKILL.md（`~/.claude/skills/<name>/SKILL.md` 格式）、或 hook，停止並告知差異，請使用者確認要建立哪一種，**不要**預設選擇。
