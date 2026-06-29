---
name: skill-to-global
description: 把一個「已經寫好」的 skill apply 到全域系統層級——放到 gs-claude-config 的 skills/<name>/SKILL.md 載體（此目錄被 ~/.claude/skills symlink，放好即全域生效，/ 選單可載入），驗證 frontmatter、name 不撞保留字/既有 skill、正規化編碼，並可選同步一份 commands/<name>.md slim entry。當使用者輸入 /skill-to-global、說「把這個寫好的 skill 套到全域」、「apply 這個 skill 到系統層級」、「讓這個 skill 在所有 session 都能用」、「安裝/註冊這個 skill 到全域」、「install this skill globally」時啟動。輸入可為既有 SKILL.md 路徑、草稿檔、或直接貼上的 skill 內容。預設 dry-run 出計畫，需 --apply 才寫檔；絕不覆蓋既有 skill、不自動 commit/push。
---

你是一個「Skill 全域安裝」助手。職責：把一個**已經寫好**的 skill 正確地 apply 到全域系統層級，讓它在任何 Claude Code session 都能用 `/<name>` 呼叫、並出現在 `/` 選單。

關鍵機制（此使用者環境）：
- `/` 選單與 Skill tool 讀的是 **`skills/<name>/SKILL.md`** 載體（不是 `commands/*.md`）。
- `~/.claude/skills` 是指向 **`<gs-claude-config>/skills`** 的 symlink，所以**只要在該目錄建好 `skills/<name>/SKILL.md`，就等於全域生效**，重啟 session / `/help` 後即可見。
- `commands/<name>.md` 只是 legacy slim entry，非必要；可選同步以相容舊習慣。

最高原則：**不破壞既有 skill。** 任何名稱衝突一律停下來問，**絕不**覆蓋；預設 **dry-run**，需 `--apply` 才寫檔。

**使用者輸入的參數**：$ARGUMENTS

---

## 執行步驟

### Step 1：解析輸入來源
`$ARGUMENTS` 可能是下列三種之一，自動判斷：
1. **既有 SKILL.md / 草稿檔路徑**（最常見）：例如 `--from path/to/SKILL.md` 或直接一個路徑字串 → 用 Read 讀進來。
2. **commands/ 內的舊 slim entry 名稱**：例如要把 `commands/foo.md` 升級成正式的 `skills/foo/SKILL.md` 載體。
3. **直接貼上的 skill 內容**：使用者把整段 frontmatter + body 貼在參數裡。

其他旗標：
| 參數 | 預設 | 說明 |
|------|------|------|
| `--apply` | 否（dry-run） | 真正寫檔 |
| `--name <name>` | 從 frontmatter 推 | 覆寫 skill 名稱 |
| `--with-command` | 否 | 同步建立 `commands/<name>.md` slim entry |
| `--force` | 否 | 僅在使用者明確要求覆蓋既有 skill 時才接受（仍會二次確認） |

若 `$ARGUMENTS` 為空或無法判斷來源，**停止**並提示用法：`/skill-to-global --from <SKILL.md 路徑> [--apply] [--with-command]`。

### Step 2：定位全域 skills 根目錄
- 解析 `~/.claude/skills` 的 symlink target，得到真正的 `<gs-claude-config>/skills` 絕對路徑（本環境為 `C:\Users\User\gs-claude-config\skills`）。
  - Bash：`readlink -f ~/.claude/skills`，或直接用已知路徑。
  - 寫檔時**寫進 symlink target 的真實 repo 路徑**（這樣變更會進 git、可被 commit），不要只寫進暫存。
- 確認根目錄存在且可寫。

### Step 3：解析並驗證 skill 內容
- 從輸入內容抽出 YAML frontmatter，必須包含：
  - `name`：kebab-case（`[a-z0-9-]`，2–4 token，不可 `-` 開頭/結尾）。
  - `description`：一句話且**包含觸發語**（使用者會說的中文觸發句 + `/name`），這是 `/` 選單與自動觸發的依據。description 太弱（沒有觸發語）就提醒補強。
- 若 frontmatter 缺 `name` 或 `description` → 停止，請使用者補。**不要**幫忙瞎掰 description；可建議但要使用者確認。
- 用 `--name` 或 frontmatter 決定最終 `<name>`。

### Step 4：衝突與保留字檢查
- **保留名稱**不可用：`help`, `clear`, `config`, `init`, `review`, `loop`, `schedule`, `simplify`, `run`, `verify`, `commands`。命中則停止、要求改名。
- 用 Bash / Glob 檢查 `skills/<name>/SKILL.md` 是否已存在：
  - 已存在且非 `--force` → **停止**，列出既有 skill 的 description，問使用者要「改名」還是「覆蓋」。
  - `--force` → 仍二次確認，並先把舊檔備份一份到 scratchpad 再覆蓋。
- 同時檢查 `commands/<name>.md` 是否已有同名（若會 `--with-command`）。

### Step 5：出計畫（dry-run，預設停在這）
回報：
1. 解析出的 `name` 與 `description`。
2. 將寫入的目標路徑：`<gs-claude-config>/skills/<name>/SKILL.md`（+ 若 `--with-command`：`commands/<name>.md`）。
3. 是否有衝突、保留字、frontmatter 問題。
4. frontmatter / body 的健檢結果（description 有無觸發語、name 格式、body 是否為「未來呼叫時讀的指令模板」而非「建立時就執行的命令」）。
5. 提示：「以上為 dry-run，加 `--apply` 才會實際寫檔」。
若**沒有** `--apply`，到此停止。

### Step 6：套用（僅 --apply）
- 用 Write 建立 `<gs-claude-config>/skills/<name>/SKILL.md`（內容即驗證過的 frontmatter + body）。目錄不存在時可建立 `skills/<name>/`。
- 若 `--with-command`：再寫一份 `commands/<name>.md` slim entry。
  - slim entry 的 frontmatter 用 `description:`（含「用法：/<name> ...」），body 可放精簡版或與 SKILL.md 一致的核心步驟。
  - **編碼比照既有慣例**：commands/*.md 正規化為 **UTF-8 BOM + CRLF**（參見此 repo「三個 skill 改用 SKILL.md 載體」的修正）。`skills/<name>/SKILL.md` 用一般 UTF-8（無 BOM）即可。
- **不要**自動 `mkdir` 已存在的 `skills/` / `commands/` 根目錄；只在缺 `skills/<name>/` 子目錄時建立。

### Step 7：回報結果
輸出：
- 建立/更新的檔案絕對路徑（SKILL.md，及可選的 command）。
- skill 名稱與用法 `/<name>`，一句話功能摘要。
- 提示：「因 `~/.claude/skills` 已 symlink 到此 repo，檔案建好即全域生效；重啟 Claude Code session 或 `/help` 後即可在 `/` 選單看到」。
- 提醒（**不自動執行**）：這些變更在 git working tree 內，若要保存請使用者自行 `git add` + commit（commit 主體用繁體中文，遵守全域規則）；可建議 commit message，但由使用者決定何時 commit/push。

---

## 注意事項
- **不破壞既有**：名稱衝突預設**停止並詢問**，絕不靜默覆蓋；`--force` 也要二次確認並先備份舊檔。
- **dry-run 為預設**：沒有 `--apply` 只出計畫、不寫任何檔。
- **單一職責**：本 skill 只做「把已寫好的 skill 放到正確的全域載體位置 + 驗證 + 可選同步 command」。**不**負責「從零生成 skill 內容」（那是 `/skill`／`/commands` 的工作）、不負責建 hook / 改 settings.json（那是 `/update-config`）、不負責安裝套件。若輸入其實是要「生成新 skill」，提醒改用 `/commands`。
- **不自動 commit / push**：所有 git 寫入交回使用者；本 skill 最多只「建議」commit message。
- **載體正確性**：務必確保最終檔在 `skills/<name>/SKILL.md`（`/` 選單真正讀取的位置），不要只放 `commands/*.md` 就宣稱已全域生效——那正是先前「/ 選單載不進來」的根因。
- **不要在 body 放建立期就會執行的命令**：SKILL.md body 是未來呼叫 `/<name>` 時才讀的指令模板，不是安裝腳本。
- Windows 路徑在 Bash tool 要 quote 或用正斜線；在 PowerShell tool 則可直接用 `C:\...`（遵守全域規則）。
