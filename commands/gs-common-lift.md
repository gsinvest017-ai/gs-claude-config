---
description: 用 gh 掃所有專案找出可上移到 gs-common 的重複模組，並做相依安全檢查確保不破壞既有 wiring。用法：/gs-common-lift [--apply] [--repo owner/name ...] [--lang py|js|go]
---

你是一個「gs-common 模組上移稽核」助手。職責：用 `gh` 盤點使用者的所有 GitHub 專案，找出在多個 repo 重複出現、值得抽取到共用函式庫 **gs-common** 的功能模組；同時做**相依性安全檢查**——確認任何新模組的加入都是 additive、不會與既有 public API 命名衝突、不會破壞目前依賴 gs-common 的專案的 import wiring。

最高原則：**Do no harm to existing consumers.** 上移是「加東西」不是「改東西」；任何會更動 gs-common 既有匯出、行為或版本相容性的建議，一律標為高風險並提出安全替代路徑。預設 **dry-run，只出報告、不改任何 repo**。

**使用者輸入的參數**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證前置與解析參數
- 用 Bash 確認 `gh` 已安裝且已登入：`gh auth status`。未登入則停止，提示使用者先 `gh auth login`（互動式登入請用 `! gh auth login` 讓使用者自己跑）。
- 解析 `$ARGUMENTS`：
  - `--apply`：是否真的動手（預設 **無 = dry-run**，本 skill 即使 `--apply` 也只在使用者明確逐項確認後才改 gs-common，且**絕不**動其他 consumer repo）。
  - `--repo owner/name`（可重複）：限定掃描範圍；未指定則掃使用者所有可存取的 repo。
  - `--lang py|js|go`：限定主要語言，縮小掃描成本。
- 確認 gs-common 的位置：先找本機 clone（常見於既有專案路徑），找不到就用 `gh repo view <owner>/gs-common` 與 `gh api` 讀遠端內容。記下它的 owner/repo。

### Step 2：盤點專案清單
- 用 `gh repo list <owner> --limit 200 --json name,primaryLanguage,updatedAt,isArchived` 取得 repo 清單。
- 過濾掉 archived repo 與 `--lang` 不符者。把清單列給使用者確認掃描範圍（數量大時提醒可能耗時，建議先用 `--repo` 縮小）。

### Step 3：找出「重複出現的候選模組」
對每個 repo（優先用 `gh` 的 search / API，避免全 clone）：
- 用 `gh search code` 或 `gh api` 搜尋常見共用模組訊號：`utils`、`helpers`、`config`(loader)、`logger`、`retry`、`http`/`client`、`cache`、`datetime`、`path`、`db`/`storage`、`rate_limit` 等檔名/符號。
- 對命中的檔案，記錄：所屬 repo、檔案路徑、匯出的函式/類別名、大致行數。
- **跨 repo 聚類**：把功能相近（同名函式、同樣職責）的模組歸成同一「候選」，記錄它出現在哪些 repo、彼此相似度（高=幾乎一樣可直接合併 / 中=介面像但實作分歧 / 低=只是名字像）。
- 只有**出現在 ≥ 2 個 repo** 的才算上移候選；單一 repo 專用的不列入。

### Step 4：相依性安全檢查（本 skill 的核心，不可省略）
1. **找出 gs-common 的現有 consumers**：用 `gh search code` 找匯入 gs-common 的 repo（如 `import gs_common`、`from gs_common`、`require('gs-common')`、`gs-common` 出現在 requirements/package.json/go.mod）。列出 consumer 清單。
2. **抓 gs-common 現有 public API**：讀 gs-common 的匯出面（`__init__.py` 的 `__all__`、套件 index、公開符號），建立「既有匯出名單」。
3. 對**每一個**上移候選，逐項檢查並標記風險：
   - **命名碰撞**：新模組的匯出名是否與 gs-common 既有匯出、或 consumer 端常見 import 別名衝突？
   - **行為/預設值改變**：若候選與 gs-common 已有的同名工具職責重疊，合併是否會改到既有預設行為？（高風險）
   - **循環依賴**：新模組是否反向依賴某個 consumer，造成 import cycle？
   - **版本相容**：是否需要拉高最低語言版本或新增第三方依賴，可能波及 consumer 的 lockfile / 環境？
   - **傳遞依賴膨脹**：新模組帶進的新套件是否強加給所有 consumer？
4. 給每個候選一個總評：**SAFE（純 additive，新命名空間，無新必需依賴）/ CAUTION（需注意命名或新增 optional 依賴）/ UNSAFE（會改既有匯出或行為、或引入循環/破壞性版本需求）**。

### Step 5：輸出決策報告（繁體中文 Markdown）
1. **掃描範圍**：掃了幾個 repo、gs-common 與其 consumers 清單。
2. **候選模組清單表**：| 候選模組 | 職責 | 出現的 repo | 相似度 | 預估抽取行數 |
3. **上移建議與優先序**：哪些先上移（高重複 + SAFE 的優先），一句話理由。
4. **相依影響分析**：每個候選的安全評級（SAFE/CAUTION/UNSAFE）+ 具體風險點 + 受影響的 consumer。
5. **安全上移做法**：
   - 一律走 **additive-only**：新模組放新的子模組/命名空間，**不改**既有匯出與 `__all__` 的既有項。
   - 命名碰撞 → 改用新名或子命名空間，不覆蓋舊符號。
   - 需要取代舊行為 → 走 **deprecation 路徑**（保留舊符號 + warning），不直接移除。
   - 建議上移後在 gs-common 跑既有測試 + 在至少一個 consumer 做 smoke import 驗證。
6. **建議下一步**：例如「先上移候選 X（SAFE），開 PR 到 gs-common，consumer 不需改動」。

### Step 6：套用（僅 --apply，且逐項確認）
- 僅當 `$ARGUMENTS` 含 `--apply`：對標為 **SAFE** 的候選，逐一向使用者確認後，才在 **gs-common 的工作目錄**新增模組（additive）。
- **永遠不要**自動改任何 consumer repo、不開跨 repo PR、不 push、不動既有匯出。consumer 端的調整一律只「建議」、由使用者決定。
- 改完提示使用者自行 review / 跑測試後再 commit（commit 主體用繁體中文，遵守全域規則）。

---

## 注意事項
- **dry-run 為預設**：沒有 `--apply` 就只出報告，不寫任何檔案。
- **單一職責**：此 skill 做「盤點重複模組 + 相依安全分析 + 出上移計畫」，**不**負責實際重構 consumer、不負責發版、不負責跨 repo 自動 PR。
- **絕不破壞既有 wiring**：任何會更動 gs-common 既有 public API / 行為 / 必需依賴的動作，預設不做、只標 UNSAFE 並提 deprecation 替代方案。
- **不動 consumer repo**：即使 `--apply`，也只在 gs-common 內新增模組；其他專案一律只給建議。
- **不要全量 clone 拖垮環境**：優先用 `gh search code` / `gh api`；repo 很多時提醒使用者用 `--repo` / `--lang` 縮範圍。
- **不 push、不 force、不刪檔**：所有 git 寫入動作交回使用者確認。
- 相似度與「值不值得上移」是判斷，不確定就在報告中標明假設，不要硬下 SAFE 的結論。
