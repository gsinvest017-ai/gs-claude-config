---
name: apply-gs-templete
description: 從 C:\Users\User\gs-trading-portal（Genesis gold theme，dark warm-black + gold/champagne/copper/bronze accent + Inter / JetBrains Mono 字體）抽取整體配色與設計 tokens（:root CSS variables、漸層、邊框、卡片陰影、漸層品牌文字），apply 到當前 repo 的 dashboard UI，讓多個專案 dashboard 視覺風格一致。偵測 dashboard 載體（HTML / Streamlit / Gradio / Plotly Dash / React / Vue / Tailwind），產出 gs-theme.css 並在 HTML 注入或在 Streamlit 寫 .streamlit/config.toml 的 theme 區塊。當使用者輸入 /apply-gs-templete、說「套用 GS 配色」、「把 gs-trading-portal 樣式套到這個 repo」、「dashboard 換成 Genesis gold」、「統一專案視覺」、「apply gs template style」時啟動。預設 dry-run，需 --apply 才寫檔。
---

# /apply-gs-templete — 把 gs-trading-portal 的 GS theme apply 到當前 repo

當使用者觸發時，從 **`C:\Users\User\gs-trading-portal`**（Genesis gold theme 來源）讀取 `style.css` 與 `index.html`，抽取設計 tokens，apply 到**當前 repo** 的 dashboard。全程繁體中文回報。

**預設 dry-run**（只印偵測 + plan + 預覽即將寫出的 `gs-theme.css`）；需 `--apply` 才寫檔。

**核心原則**：**每次執行時即時抽取 tokens**——不在本 skill 內 hard-code 配色值，這樣 `gs-trading-portal` 更新主題時，重跑就會帶入新版。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--source <path>` | `C:\Users\User\gs-trading-portal` | template 來源 repo |
| `--target <path>` | 當前 repo | 套用目標 |
| `--scope <colors\|all\|tokens-only>` | `all` | colors=只動配色；tokens-only=只產生 CSS var 不改既有 selector；all=配色 + 字體 + 邊框 + 陰影 + 品牌文字效果 |
| `--mode <inject\|override\|fork>` | `inject` | inject=產生 `gs-theme.css` + link 進 HTML；override=改既有 CSS 內的 `:root` 值；fork=另存 `theme-gs.css` 但不改 HTML（手動 link） |
| `--include-3d` | 否 | 額外複製 `three-bg.js` + 對應 canvas 注入（背景互動 3D） |
| `--include-brand` | 否 | 連同品牌字（"G5" / "GS"）標記一起套；預設**不**動品牌文字以免誤用 |
| `--preserve <selectors>` | 無 | CSS selector 清單，不要被覆寫 |
| `--dry-run` | 否（預設行為） | 只印計畫與預覽，不寫檔 |
| `--apply` | 否 | 真的寫檔 |

範例 args：
- `""` → auto 偵測、dry-run plan
- `"--apply"` → 套用全套 GS theme
- `"--scope colors --apply"` → 只動配色，不動字體 / 邊框
- `"--source D:\design\gs-template-v2 --apply"` → 用另一份來源
- `"--mode override --apply"` → 直接改 target 既有 CSS 的 `:root`
- `"--include-3d --apply"` → 加上 Three.js 背景

## 1. 前置檢查 — 確認來源 GS template

預期 source 結構（從 `gs-trading-portal` 抽出的典型）：

```
<source>/
  style.css        ← 主 CSS，:root 內含 ~30 個 CSS custom properties
  index.html       ← 參考 HTML 結構（header / brand-title gradient / panel patterns）
  three-bg.js      ← 可選的 3D 背景
  app.js / scripts/
  assets/
```

確認 `<source>/style.css` 存在；不存在 → 提示 `--source <path>` 重指。

## 2. 抽取設計 tokens（核心步驟）

從 `<source>/style.css` 解析出以下 token 群組：

### A. Palette（必抽）

掃 `:root { ... }` 區塊內所有 `--*` 變數。Genesis gold theme 預期會看到的群組：

- **Backgrounds**：`--bg-0` `--bg-1` `--bg-2` `--bg-card` `--bg-card-hover`（warm-black 序列）
- **Grid/lines**：`--grid` `--grid-strong` `--line` `--line-hi`（冷色 dim 灰，刻意低對比讓 gold 出色）
- **Foreground**：`--fg-0` `--fg-1` `--fg-2` `--fg-dim`（米色 / 香檳階）
- **Gold family**：`--gold` `--gold-light` `--gold-soft` `--champagne` `--champagne-soft` `--copper` `--copper-soft` `--bronze` `--bronze-soft` `--amber` `--amber-soft` `--rose`
- **Legacy aliases**：`--cyan` `--cyan-soft`（指向 gold；舊 code 相容用）
- **Fonts**：`--font-sans` `--font-mono`

提取方式（PowerShell / Python / 純文字解析皆可）：

```regex
:root\s*\{([\s\S]*?)\}
```

再對其內 `^\s*(--[a-z0-9-]+)\s*:\s*(.+?);` 全部抓出，組成 `name → value` 字典。

### B. Body background（必抽，畫面整體氣氛靠這個）

掃 `body { background: ... }` 取出 radial-gradient 疊層（Genesis 用兩道 radial-gradient + base 色），原樣搬到 target。

### C. Header / brand 漸層文字（可選，`--include-brand` 才套）

掃 `.brand-title` 與 `::after`：linear-gradient 文字 + `-webkit-background-clip: text` + glow text-shadow——這是 GS 的視覺簽名。**預設不套**避免別 repo 也叫 "GS"。

### D. 元件 token（`--scope all`）

掃幾個關鍵 selector 的樣式並抽出可重用的 declarations：
- `.app-header`：linear-gradient 背景 + `backdrop-filter: blur(8px)` + 下緣金色 gradient line
- `.tool-group` / `.panel`：`border: 1px solid var(--line); border-radius: 6px;` + 微透明 bg
- 卡片 hover：`background: var(--bg-card-hover)`
- 陰影慣例：`box-shadow: 0 8px 24px -16px rgba(0,0,0,0.85)`

把這些抽成 utility classes：`.gs-card` / `.gs-toolbar` / `.gs-header` …

## 3. 偵測 target dashboard 載體

掃 target repo（同 `/ui-compact` 的偵測邏輯）：

| 載體 | 偵測訊號 | 套用點 |
|------|---------|-------|
| **HTML 直發** | `dashboard.html` / `index.html` | 注入 `<link rel="stylesheet" href="gs-theme.css">`；無 `:root` 就新建；有就 merge |
| **Streamlit** | `*.py` + `import streamlit` | `.streamlit/config.toml` 寫 `[theme]` 區塊（base/dark + primaryColor + bg + secondaryBg + textColor 從 token 映射），再 `st.markdown` 注入完整 CSS 補強 |
| **Gradio** | `gr.Blocks(theme=...)` | 寫 `gr.themes.Base().set(...)` 並把 token 對應進去；或注入 custom CSS |
| **Plotly Dash** | `dash.Dash(...)` | 加 `external_stylesheets=["/assets/gs-theme.css"]` 並產生該檔 |
| **React / Vue** | `*.jsx` / `*.vue` | 產 `theme.css` 並 import 進 root；如有 styled-components / emotion → 另產 `theme.ts` |
| **Tailwind** | `tailwind.config.{js,ts}` + class pattern | 在 config 內 `theme.extend.colors` 加入抽出 palette，配色 class 即可用 `bg-gs-gold` 等；同時補 `gs-theme.css` for body bg + brand |

**autogo 專案特記**：`web/dashboard.html` 為入口，CSS 多在 inline 或 `web/static/`；採 `inject` mode 在 `<head>` 加 link 並產 `web/static/gs-theme.css`。

## 4. Plan / dry-run（預設）

印計畫表：

```
Source: C:\Users\User\gs-trading-portal
        ├ style.css : 抽到 30 個 CSS vars（bg/grid/fg/gold family/copper/champagne/bronze 等）
        ├ body 背景 : radial-gradient × 2 + var(--bg-0)
        └ 字體 : Inter (sans) / JetBrains Mono (mono)

Target: <repo>  (HTML dashboard at web/dashboard.html)

計畫變動（--apply 才會做）：
  [1] 新增 web/static/gs-theme.css  (產出，~120 行)
       /* applied by /apply-gs-templete 2026-05-28 */
       :root { --bg-0: #07060a; ... }
       body  { font-family: var(--font-sans); background: ... }
       .gs-card { ... }  .gs-toolbar { ... }
  [2] web/dashboard.html  在 <head> 注入 <link rel="stylesheet" href="static/gs-theme.css">
  [3] 寫 backup：.claude/local/apply-gs-templete.json（記錄改了哪些檔，供 --revert）

不會動 :
  - target 內 .js 邏輯 / API 呼叫 / 商業邏輯
  - target 既有 logo / assets
  - 標 --preserve 的 selector
```

無 `--apply` → 結束。

## 5. 套用（僅當 `--apply`）

依 `--mode`：

### `inject`（預設）
- 在 target 適當目錄產 `gs-theme.css`（HTML repo 通常 `<root>/` 或 `static/`；Streamlit 不適用，走下面變體）
- 在 target HTML `<head>` 內注入 `<link rel="stylesheet" href="gs-theme.css">`，放在既有 CSS 之**後**（CSS cascade 讓 GS 蓋掉舊值）
- 用註解標籤包：

```html
<!-- BEGIN apply-gs-templete -->
<link rel="stylesheet" href="gs-theme.css">
<!-- END apply-gs-templete -->
```

### `override`
- 找 target 內既有 `:root { ... }`，把抽出來的 vars merge 進去（同名覆寫、原無的新增）
- 風險高，但對既有架構動最少；適合 target 已用 CSS vars 的情況

### `fork`
- 產 `theme-gs.css`，不改 HTML
- 提示使用者自行 link / 套用

### Streamlit 變體
- 寫 `.streamlit/config.toml`：

```toml
# BEGIN apply-gs-templete
[theme]
base = "dark"
primaryColor = "#d4af37"          # var(--gold)
backgroundColor = "#07060a"       # var(--bg-0)
secondaryBackgroundColor = "#161210"  # var(--bg-card)
textColor = "#f0e8d6"             # var(--fg-0)
font = "sans serif"
# END apply-gs-templete
```

- 並在 app 啟動處 `st.markdown(open('gs-theme.css').read(), unsafe_allow_html=True)` 補強完整 token

### 共通
- backup metadata 寫 `.claude/local/apply-gs-templete.json`（記錄 target 改動位置 + 原始 :root，供 `--revert`）
- 在 CSS 檔頂端加 `/* applied by /apply-gs-templete YYYY-MM-DD, source: <source-path> */`
- `--include-3d` → 複製 `<source>/three-bg.js` 到 target，並在 HTML body 末注入 `<canvas id="three-bg"></canvas><script src="three-bg.js"></script>`

## 6. 驗證

- 檢查產出 `gs-theme.css` 文法（無 `}` 缺失，CSS var count > 20）
- HTML 注入是否成功（`<link>` 在 `<head>`、用標籤包圍）
- 若 Chrome DevTools / Playwright MCP 可用 → navigate target dashboard、截圖前後存 `docs/apply-gs-templete-<date>-{before,after}.png`、`evaluate_script` 比對 `getComputedStyle(document.body).backgroundColor` 變化
- 列出未動到的舊樣式（提示可能需手動 sweep）

## 7. 完成回報

3~5 行：
1. source 路徑 + 抽到幾個 token
2. target 載體 + 寫出 / 修改的檔
3. 套用 mode + 是否含 3D
4. 預覽方式（開 `dashboard.html` / 跑 `streamlit run`）
5. 後續：跑 `/ui-compact` 確認排版仍 fit；下次主題更新只要重跑本指令

## 不要做的事

- ❌ 沒 `--apply` 就寫檔
- ❌ 把 GS theme 的**配色值 hard-code 在本 skill**——每次都要從 source 抽，主題才能 live
- ❌ 連同 source 的 logo / 品牌資產 / `--include-brand` 才該動的元素一起套（預設不套，避免命名衝突）
- ❌ 動 target 的 JS 邏輯 / API / data 流——只動 layout 樣式 / 視覺
- ❌ 砍 a11y：對比度、focus ring、`prefers-reduced-motion`、最小字體（>= 12px）不准砍
- ❌ 動 vendored（`node_modules` / `vendor` / `dist`）
- ❌ 砍既有 dark / light mode 切換邏輯（若 target 有）；GS theme 整合到 dark 一支即可

## 邊界情況

- **Source 無 CSS vars / 直接寫 hex**（極不可能於 gs-trading-portal）→ 退而求其次，掃所有 `color:` / `background:`，聚類找代表色
- **Target 用 Tailwind**：CSS vars 仍可用，但理想是把抽出 palette 寫進 `tailwind.config.js` `theme.extend.colors.gs.*`，配色 utility class 才能用
- **Target 已被本 skill apply 過**（看到 `BEGIN apply-gs-templete` 標籤）→ 預設**只更新標籤內**，不重複注入；除非 `--mode override`
- **GS palette 與 target 既有主題衝突**（如 target 已有 `--gold` 但定義成綠色）→ 在 dry-run 時印警告，建議改 `--mode fork` 或 `--preserve`
- **大量 inline `style=""`** in target HTML → 本 skill 不會自動掃 inline style；提示使用者後續手動或用 `/ui-compact` 重構
- **目標含多個 dashboard**（monorepo） → 用 `--target` 限定到子目錄

## 與其他 skill 協作

- **`/ui-compact`**：套完 GS theme 後跑 ui-compact 確認沒撐破 viewport
- **`/copy-commits-button`**：新增的 panel 自動繼承 GS theme（`.gs-card` class）
- **`/one-button-launch`**：dashboard 沒 launcher 時先用它起服務驗證視覺
- **`/platform-compatible`**：產出的 `gs-theme.css` 換行設 LF（`.gitattributes *.css text eol=lf`）

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/apply-gs-templete/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入（本 session 即時生效）。
