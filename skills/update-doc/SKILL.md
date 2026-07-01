---
name: update-doc
description: 掃描當前 repo 的 README、架構、API、指令、git log，產生或更新一份 standalone HTML 文件網頁（`docs/index.html`）。偵測現有文件框架（MkDocs / Sphinx / Docusaurus / Jekyll / 純 HTML），若沒有則建立 `docs/index.html`（GS dark gold theme，無外部 CDN 依賴）。當使用者輸入 /update-doc、說「幫這個 repo 建文件網頁」、「更新文件頁」、「generate doc page」、「build docs」、「產生文件」時啟動。預設 dry-run，需 --apply 才寫檔。
---

# /update-doc — Repo 文件網頁產生 / 更新器

當使用者觸發時，掃描**當前 repo**，產生或更新一份可直接用瀏覽器開啟的 **standalone HTML 文件網頁**。全程繁體中文回報。

**預設 dry-run**（只印 plan + 預覽段落）；需 `--apply` 才實際寫檔。

---

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--apply` | 否 | 實際寫入 standalone HTML（或更新既有） |
| `--output <path>` | auto（見 Section 1） | 覆寫輸出路徑；未指定時自動使用已存在的 standalone HTML 路徑，否則 fallback 到 `docs/index.html` |
| `--framework <auto\|html\|mkdocs\|sphinx\|docusaurus>` | `auto` | 強制指定文件框架；`html` = 無論偵測到何框架皆產 standalone HTML |
| `--theme <gs\|plain>` | `gs` | `gs` = GS dark gold theme；`plain` = 無樣式純 HTML |
| `--sections <list>` | `all` | 逗號分隔要輸出的段落（overview,install,architecture,commands,api,changelog） |
| `--dry-run` | 是（預設） | 只印預覽不寫檔 |
| `--inject-markers` | 否 | **首次使用**：在既有 standalone HTML 各 `<section id="...">` 的子內容前後插入 `<!-- BEGIN/END update-doc: {id} source={docs-site-path} -->` 標記，**不改任何內容**。之後跑 `--apply` 就只替換標記內的區塊。 |

範例 args：
- `""` → dry-run，auto detect，GS theme，全段落
- `"--apply"` → 偵測輸出路徑後寫入（MkDocs repo 若已有 web/docs.html 則更新它）
- `"--apply --output site/index.html"` → 強制寫到指定路徑
- `"--framework html --apply"` → 忽略 MkDocs/Sphinx 框架，產 standalone HTML
- `"--apply --sections overview,install,commands"` → 只產指定段落
- `"--inject-markers --apply"` → 首次注入標記（不改內容），啟用之後的 smart-sync
- `"--framework html --apply"` 在標記注入後 → **smart-sync**：只更新標記內的區塊

---

## 1. 偵測現有文件框架

### 1a. 框架偵測（按優先順序）

1. `mkdocs.yml` → MkDocs
2. `docs/conf.py` 或 `conf.py` → Sphinx
3. `docusaurus.config.js` / `docusaurus.config.ts` → Docusaurus
4. `_config.yml` + `_layouts/` → Jekyll
5. 以上皆無 → no-framework

### 1b. Standalone HTML 掃描（與框架偵測並行）

搜尋以下候選路徑（依優先順序，找到第一個存在的即停）：
- `web/docs.html`
- `docs/index.html`
- `site/index.html`
- `public/index.html`
- `index.html`（根目錄）

若以上皆無 → standalone = absent。

### 1c. 決策矩陣

| 框架偵測 | Standalone 存在？ | `--framework` flag | 行為 |
|---------|-----------------|-------------------|------|
| no-framework | 任意 | 任意 | 繼續 Section 2（新建或更新 standalone HTML） |
| MkDocs/Sphinx 等 | **有** | 未指定 | **Dual-mode**：列出兩個選項（見 1d），不停止 |
| MkDocs/Sphinx 等 | **無** | 未指定 | 告知偵測到框架 + 建議原生指令，**停止** |
| MkDocs/Sphinx 等 | 任意 | `html` | 繼續 Section 2，`--output` 預設使用已找到的 standalone 路徑（absent 時 fallback `docs/index.html`） |

### 1d. Dual-mode 輸出格式（框架已有 + standalone 已存在）

回報以下資訊後**不停止，等使用者以自然語言回應或直接繼續**（若使用者未回應而 `--apply` 已指定，預設選 Option B）：

```
偵測到雙重文件結構：
  框架：<framework>（<config file>）
  Standalone HTML：<path>（<file size / 最後修改時間>）

選項 A — 使用 <framework> 原生指令（不修改 HTML）：
  <原生 build 指令>

選項 B — 更新 <standalone path>（GS dark gold theme）：
  /update-doc --framework html --apply
  （將掃描 README / CLAUDE.md / git log 並更新 <standalone path>，
   保留 <!-- BEGIN update-doc: ... --> 標記外的人工內容）

若要同時維護兩者，請先跑選項 A，再跑選項 B。
```

### 1e. `--output` 自動解析

若使用者未明確傳入 `--output`：
- 有找到 standalone HTML → 用該路徑（e.g. `web/docs.html`）
- 無 standalone HTML → fallback `docs/index.html`

**standalone HTML（更新 or 新建）** → 繼續以下流程。

### 1f. `--inject-markers` 模式（首次啟用 smart-sync）

**觸發條件**：`--inject-markers` flag 且 `--apply` 均存在。

**執行步驟**：
1. 讀取 standalone HTML（目標路徑）
2. 掃描所有 `<section id="{id}">` 標籤
3. 對每個 section，查詢 **Section → docs-site 對應表**（見下），決定 `source=` 路徑
4. 在 `<section id="{id}">` 的**第一個子元素前**插入：
   ```html
   <!-- BEGIN update-doc: {id} source={docs-site-path} -->
   ```
5. 在 `</section>` 的**緊前面**插入：
   ```html
   <!-- END update-doc: {id} -->
   ```
6. **不改任何內容**，只加標記。儲存回原路徑。

**Section → docs-site 對應表**（autogo repo 預設，其他 repo 自動推導）：

| section id | source |
|---|---|
| `overview` | `docs-site/index.md` |
| `problem` | `docs-site/index.md` |
| `capabilities` | `docs-site/index.md` |
| `architecture` | `docs-site/cv/overview.md` |
| `tech-stack` | `docs-site/cv/capture.md` |
| `quickstart` | `docs-site/ops/run.md` |
| `dashboard-guide` | `docs-site/ui/dashboard.md` |
| `autogo-skill` | `CLAUDE.md` |
| `test-plans` | `docs-site/test/overview.md` |
| `env-vars` | `docs-site/ops/config.md` |
| `api-ref` | `docs-site/ui/endpoints.md` |

無對應表時，以 section id 推導：`install`→`ops/run.md`、`changelog`→`changelog.md`、其他→`index.md`。

### 1g. Smart-sync 模式（標記存在後自動啟用）

**觸發條件**：`--apply` 且 standalone HTML 內找到至少一個 `<!-- BEGIN update-doc: -->` 標記。

**執行步驟**（逐 section）：
1. 正則找出所有 `<!-- BEGIN update-doc: {id} source={path} -->…<!-- END update-doc: {id} -->` 區塊
2. 讀取 `source={path}` 的 Markdown 源（跳過不存在的，保留原內容）
3. 將 Markdown 關鍵段落轉換為與 HTML 風格一致的 HTML 片段（`<p>`, `<ul>`, `<pre>`, `<table>`）
4. 替換 BEGIN/END 標記之間的內容（標記行本身保留）
5. 如有 `--sections` 限制，只處理對應的 section id
6. 輸出 diff 摘要：每個替換區塊顯示「原 N 行 → 新 M 行」

**`--dry-run`**：只印 diff 預覽，不寫檔。

---

## 2. 掃描 repo 內容

依序讀取（不存在的跳過）：

### 2a. 基本資訊（docs-site/ 優先）

若 `docs-site/` 目錄存在，優先從中讀取對應 .md 源；否則 fallback 到以下：
- `README.md` / `README.rst` / `README` → 專案描述、overview、安裝說明
- `pyproject.toml` / `package.json` / `go.mod` / `Cargo.toml` → 專案名、版本、作者、依賴
- `CLAUDE.md` / `.claude/CLAUDE.md` → 架構說明、指令、慣例（Claude agent spec，內容豐富時直接引用）

**docs-site/ 存在時的優先讀取順序**：
1. `docs-site/index.md` → overview / problem / capabilities
2. `docs-site/cv/overview.md` → architecture
3. `docs-site/ops/run.md` → quickstart / install
4. `docs-site/ops/config.md` → env-vars / configuration
5. `docs-site/ui/endpoints.md` → api-ref
6. `docs-site/ui/dashboard.md` → dashboard-guide
7. `docs-site/test/overview.md` → test-plans
8. `docs-site/changelog.md` → changelog

### 2b. 模組與指令
- 根目錄 `Makefile` / `justfile` → `make` 指令
- `package.json` `scripts` → npm/pnpm scripts
- `pyproject.toml` `[tool.taskipy]` / `[scripts]` → task runner
- CI yml（`.github/workflows/*.yml`）→ 萃取 build / test / deploy 指令
- 目錄樹深度 2（排除 `.git`, `node_modules`, `dist`, `build`, `__pycache__`, `.venv`, `vendor`）

### 2c. Skills / Commands（若為 Claude config repo）
- `skills/*/SKILL.md` → 讀每個 skill 的 frontmatter `name` + `description`
- `commands/*.md` → 讀 frontmatter `description`
- 偵測依據：根目錄有 `skills/` 目錄且其子目錄有 `SKILL.md`

### 2d. 近期 commits
```bash
git log --oneline -20 --no-decorate
```

---

## 3. 組織文件結構

將掃描結果組織為以下段落（依 `--sections` 過濾）：

| 段落 ID | 標題 | 內容來源 |
|---------|------|---------|
| `overview` | Overview | README 第一段 + 專案 metadata |
| `install` | Installation / Setup | README 安裝段落 + 依賴列表 |
| `architecture` | Architecture | CLAUDE.md 架構段 + 目錄樹 |
| `commands` | Commands | Makefile / scripts / CI 萃取的指令 |
| `skills` | Skills & Commands（Claude config repo 限定）| skills + commands 一覽表 |
| `api` | API / Module Reference | 頂層 package 清單 + 入口檔 |
| `changelog` | Recent Changes | `git log --oneline -20` |

---

## 4. 產生 HTML

### 4a. GS Dark Gold Theme（`--theme gs`）

使用以下 CSS 設計語言（全部 inline，無 CDN）：

**Color tokens**:
```
--bg-primary:    #0d0d0d   (深黑主背景)
--bg-secondary:  #141414   (卡片/側欄)
--bg-tertiary:   #1a1a1a   (hover)
--border:        #2a2a2a
--gold:          #c9a84c   (主 accent)
--gold-light:    #e8c876   (hover/active)
--champagne:     #f5e6c8   (淺金文字)
--copper:        #b87333   (secondary accent)
--text-primary:  #e8e0d0
--text-muted:    #8a7d6b
--code-bg:       #0a0a0a
--success:       #4a9d5f
--warning:       #c9a84c
```

**Typography**: system-ui stack（Inter 優先 → system-ui → sans-serif）；code 用 JetBrains Mono → Consolas → monospace。

**Layout**: 左側固定 sidebar（240px）+ 右側 scrollable content；sidebar 含 logo + nav 連結；content 寬度 max 860px；RWD breakpoint 768px 時 sidebar 折疊。

**Components**:
- **卡片**: `background: var(--bg-secondary); border: 1px solid var(--border); border-radius: 8px; padding: 16px`
- **標題漸層**: `background: linear-gradient(135deg, var(--gold), var(--champagne)); -webkit-background-clip: text; -webkit-text-fill-color: transparent`
- **Badge**: `background: var(--bg-tertiary); border: 1px solid var(--border); border-radius: 4px; padding: 2px 8px; font-size: 0.75rem; color: var(--gold)`
- **Code block**: `background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px; padding: 12px; font-family: var(--font-mono)`
- **Table**: `border-collapse: collapse; width: 100%`；header `background: var(--bg-tertiary); color: var(--gold)`；row hover `background: var(--bg-tertiary)`
- **Nav link active**: `color: var(--gold); border-left: 2px solid var(--gold); padding-left: 10px`

### 4b. HTML 骨架

```html
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{project_name} — Documentation</title>
  <style>/* 全部 inline CSS，見 4a */</style>
</head>
<body>
  <nav class="sidebar">
    <div class="logo">{project_name}</div>
    <ul class="nav-links">
      <!-- 每個段落一個 anchor link -->
    </ul>
    <div class="meta">Updated: {date}</div>
  </nav>
  <main class="content">
    <header>
      <h1 class="gradient-title">{project_name}</h1>
      <p class="subtitle">{one_line_description}</p>
      <div class="badges"><!-- version, lang, license --></div>
    </header>
    <!-- 各段落 section -->
  </main>
  <script>/* active nav highlight, smooth scroll */</script>
</body>
</html>
```

### 4c. Skills 段落特殊排版

若偵測到 `skills/` 目錄，`skills` 段落輸出為卡片 grid：

```html
<div class="skills-grid">
  <div class="skill-card">
    <div class="skill-name">/{name}</div>
    <div class="skill-desc">{description 前 120 字}</div>
  </div>
  ...
</div>
```

CSS: `display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px`

---

## 5. 寫檔 / 更新

- **新建**：確保 `docs/` 目錄存在（若無，建立）；寫入 `docs/index.html`。
- **更新**：讀入既有 `docs/index.html`；找到 `<!-- BEGIN update-doc: {section} -->` / `<!-- END update-doc: {section} -->` 標記區塊並替換；標記外的人工內容保留不動。若既有檔無標記，整份覆寫（先告知）。
- **dry-run**：只印各段落預覽（前 20 行）+ 告知「執行 `/update-doc --apply` 寫入」。

---

## 6. 完成回報

3~5 行：
- 偵測到的框架 / 模式
- 掃描到的內容摘要（e.g., 「21 skills, 12 commands, 20 commits」）
- 產出 / 更新的檔案路徑
- 後續建議（e.g., `git add docs/index.html && git commit -m 'docs: 更新文件網頁'`）

---

## 不要做的事

- ❌ 未加 `--apply` 時寫入任何檔案
- ❌ 把 secrets / API key / `.env` 內容寫進 HTML
- ❌ 引用外部 CDN（`cdn.jsdelivr.net`、`unpkg.com` 等）——需要 zero dependency
- ❌ 在已有 MkDocs/Sphinx/Docusaurus 框架的 repo 預設覆寫（尊重既有框架）
- ❌ 產生超過 500KB 的 HTML（圖片、大量 dump 等）

---

## 全域註冊

安裝在 user-scope：`~/.claude/skills/update-doc/SKILL.md`（此環境 `~/.claude` symlink 至 `gs-claude-config`）。新 session 啟動後即可在任何 repo 執行 `/update-doc`。
