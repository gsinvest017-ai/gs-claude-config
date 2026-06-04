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
| `--apply` | 否 | 實際寫入 `docs/index.html`（或更新既有） |
| `--output <path>` | `docs/index.html` | 覆寫輸出路徑 |
| `--framework <auto\|html\|mkdocs\|sphinx\|docusaurus>` | `auto` | 強制指定文件框架 |
| `--theme <gs\|plain>` | `gs` | `gs` = GS dark gold theme；`plain` = 無樣式純 HTML |
| `--sections <list>` | `all` | 逗號分隔要輸出的段落（overview,install,architecture,commands,api,changelog） |
| `--dry-run` | 是（預設） | 只印預覽不寫檔 |

範例 args：
- `""` → dry-run，auto detect，GS theme，全段落
- `"--apply"` → 寫入 `docs/index.html`
- `"--apply --output site/index.html"` → 寫到指定路徑
- `"--apply --sections overview,install,commands"` → 只產指定段落

---

## 1. 偵測現有文件框架

按優先順序偵測：

1. `mkdocs.yml` → MkDocs
2. `docs/conf.py` 或 `conf.py` → Sphinx
3. `docusaurus.config.js` / `docusaurus.config.ts` → Docusaurus
4. `_config.yml` + `_layouts/` → Jekyll
5. `docs/index.html` 已存在 → 更新模式（standalone HTML）
6. 以上皆無 → 建立模式（新建 standalone HTML）

**MkDocs / Sphinx / Docusaurus / Jekyll** 已有框架 → 告知使用者「偵測到 `<framework>`，建議用該框架原生指令建文件；若仍要產 standalone HTML 請加 `--framework html`」，並停止（除非有 `--framework html`）。

**standalone HTML（更新 or 新建）** → 繼續以下流程。

---

## 2. 掃描 repo 內容

依序讀取（不存在的跳過）：

### 2a. 基本資訊
- `README.md` / `README.rst` / `README` → 專案描述、overview、安裝說明
- `pyproject.toml` / `package.json` / `go.mod` / `Cargo.toml` → 專案名、版本、作者、依賴
- `CLAUDE.md` / `.claude/CLAUDE.md` → 架構說明、指令、慣例（Claude agent spec，內容豐富時直接引用）

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
