---
name: ui-compact
description: 把當前專案的 dashboard UI layout 壓得更 compact，讓所有 panel 在預設 viewport 內無需下捲就能一眼看完。偵測 dashboard 載體（HTML / Streamlit / Gradio / Plotly Dash / React / Vue / Tailwind / Bootstrap），由低風險到重塑的順序套用 compaction 策略（縮 padding / 字體 / 行高、降圖表高度、合併標題與控制列、grid 重排、必要時摺疊次要面板），可選用 Chrome DevTools / Playwright 量測 scrollHeight 驗證。當使用者輸入 /ui-compact、說「dashboard 太長要下捲」、「把 UI 壓縮 / 壓扁」、「panels 一頁看完」、「縮 padding / 字體 / gap」、「one-screen dashboard」、「no-scroll layout」時啟動。預設 dry-run，需 --apply 才改檔。
---

# /ui-compact — Dashboard UI 一頁無捲動壓縮器

當使用者觸發時，偵測**當前 repo** 的 dashboard UI 載體，量測現況高度，套用一組由輕到重的 compaction 策略，使**所有 panel 在目標 viewport 內無需 vertical scroll** 即可看完。全程繁體中文回報。

**預設 dry-run**（只印 plan + diff preview）；需 `--apply` 才實際改檔。**目標是「縮到能容納」不是「藏起來」**——摺疊 / accordion 是最後手段，需明示 `--allow-collapse`。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--target <auto\|html\|streamlit\|gradio\|dash\|react\|vue>` | `auto` | 指定 dashboard 載體 |
| `--file <path>` | 無 | 直接指定 dashboard 入口檔（auto 找不到時用） |
| `--viewport <WxH>` | `1920x1080` | 目標 viewport；no-scroll 以此為準 |
| `--measure` | 否 | 用 Chrome DevTools / Playwright MCP 量測前後 `scrollHeight` |
| `--strategies <list>` | `auto` | 限定要套用的策略代號（見 §3，逗號分隔） |
| `--preserve <selectors>` | 無 | CSS selector / 元件名清單，**不要**壓縮的面板 |
| `--allow-collapse` | 否 | 必要時把次要 panel 包成 accordion / tabs |
| `--apply` | 否 | 真的改檔（否則只 dry-run + diff preview） |

範例 args：
- `""` → auto 偵測、量測（若工具可用）、dry-run plan
- `"--apply"` → 套用 auto 選出的策略
- `"--file web/dashboard.html --viewport 1440x900 --apply"` → 指定檔與 viewport 並套用
- `"--strategies C,D,K --apply"` → 只動字體 + 圖表高度 + Tailwind class
- `"--allow-collapse --apply"` → 允許把次要面板摺疊

## 1. 前置檢查 — 偵測 dashboard 載體

掃描下列訊號（`--target auto`）：

| 載體 | 偵測訊號 |
|------|---------|
| **HTML 直發** | `dashboard.html` / `index.html` 含明顯 grid/flex layout、`<div class="panel">` 等 |
| **Streamlit** | `*.py` 含 `import streamlit`、`st.set_page_config`、`st.columns`、`st.tabs` |
| **Gradio** | `gr.Blocks`、`gr.Row`、`gr.Column` |
| **Plotly Dash** | `from dash import`、`html.Div`、`dcc.Graph` |
| **React / Vue** | `*.jsx` / `*.tsx` / `*.vue` 含 dashboard 元件 |
| **Tailwind / Bootstrap** | class pattern：`grid grid-cols-*`、`flex`、`row col-*`、`p-*`、`gap-*` |

報告找到的檔案；找不到 → 提示「請用 `--file <path>` 指定入口檔」並停止。

**autogo 專案特記**：若偵測到 `web/dashboard.html` + `web/static/dashboard.js` + `web/app.py` → 直接視為 HTML 載體入口為 `web/dashboard.html`。

## 2. 量測現況（baseline）

優先順序：
1. **`--measure` 且有 Chrome DevTools / Playwright MCP**：
   - 起 dashboard（或要求使用者先跑起來；提示用 `/run` 或 `/one-button-launch`）
   - `new_page` → `resize_page <viewport>` → `navigate_page` → `evaluate_script` 取 `document.documentElement.scrollHeight`、`window.innerHeight`
   - 量每個主要 panel 的 `getBoundingClientRect()`（標 `data-panel` 屬性或用啟發式 selector）
   - 截圖存 `docs/ui-compact-<YYYY-MM-DD>-before.png`
2. **靜態估算**（無瀏覽器工具時）：解析 CSS / inline styles / Tailwind class，估每塊高度 + padding + margin + gap

輸出 baseline 表：

| Panel / Selector | 高度估值 | 占 viewport 比例 | 在 fold 下？ |

## 3. Compaction 策略（由輕到重）

每個策略含**代號 / 偵測訊號 / 套用方式 / 風險**。`--strategies auto` 預設依序勾選**命中**的低風險項。

| 代號 | 策略 | 偵測 | 套用 | 風險 |
|------|------|------|------|------|
| **B** | 縮 padding / margin / gap | panel `padding`、`margin`、`gap` ≥ 12px | 砍 30~50%（1rem→0.5rem、gap 16→8） | 低 |
| **C** | 縮字體 / 行高 | body ≥ 14px、line-height ≥ 1.6 | body 14→13；h1/h2 縮 10~20%；lh 1.6→1.4 | 低（注意 a11y 對比與最小字體 12px 下限） |
| **D** | 圖表降高 | plotly / matplotlib container `height` ≥ 350 | 350→240~280，保 `responsive:true` | 低 |
| **E** | 合併標題列 + 控制列 | 兩列獨立 toolbar | flex 同列、靠右擺控制 | 低 |
| **G** | 隱藏冗餘 | 重複 logo / footer / hero spacer | display:none 或刪 | 低 |
| **I** | KPI 卡片化 | 一卡一行的數字 | grid 多欄密度高的卡片 | 中 |
| **K** | Tailwind / Bootstrap class 收緊 | `py-6`/`gap-6`/`text-lg`/`min-h-screen` | → `py-2` / `gap-2` / `text-base` / `min-h-0` | 低 |
| **J** | Streamlit 專屬 | 預設 narrow layout、未設定 column 比例 | `st.set_page_config(layout="wide")`、column 寬度比、`st.expander(expanded=True)` 加 `gap="small"` | 低 |
| **A** | 全頁佈局重排為 grid | 直線堆疊 column | `display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:8px` | 中（窄面板擠的風險） |
| **F** | 摺疊次要面板 | 仍溢出且 `--allow-collapse` | 次要 panel 包 `<details>` / accordion / tabs | **高**（違背「不下捲也能看完」初衷）—— **僅當其他全做完仍溢出且使用者明示允許** |

**優先順序**：先 C/B/D/K/J/G/E（低風險、語意保留）→ 必要才 A（layout 重塑）→ 最後 F（必須 `--allow-collapse`）。

## 4. Plan / Diff Preview（dry-run 預設）

對每個將動的檔案：
- 列出將套用的策略代號
- 印 unified diff 摘要（前後對照）
- 估算每項省下的垂直 px
- 累計預估：baseline scrollHeight → predicted height（vs viewport 高度）

若 baseline 已 ≤ viewport → 報告「已經 compact，無顯著壓縮空間」並退出（除非使用者明示要再壓）。

無 `--apply` → 結束於此，回報「Dry-run 完成；確認無誤請加 `--apply` 重跑」。

## 5. 套用修改（僅當 `--apply`）

- 依策略順序逐項套用，每個檔案改完印 diff 摘要
- 在被修改檔頂端 / 對應段落加標記：`<!-- compacted by /ui-compact YYYY-MM-DD -->`（或對應語言註解），方便下次增量比對
- **Streamlit / Python** 優先改 layout 參數（`st.set_page_config`、column 比例、`gap`）而非 monkey-patch CSS；CSS 走 `st.markdown(unsafe_allow_html=True)` 是 fallback
- **Tailwind / Bootstrap** 直接替換 class，不寫 inline style
- 不改 data / 商業邏輯，只動 layout / 樣式

## 6. 驗證

- **有量測工具**：重新 navigate / reload，取新的 `scrollHeight` 與 `innerHeight`：
  - 達標：`scrollHeight ≤ innerHeight` → 報告 ✅「在 `<viewport>` 下無需下捲」
  - 未達：印剩餘溢出 px 數，建議下一輪策略（如加 `--strategies A` 重排、或最後手段 `--allow-collapse`）
  - 截圖存 `docs/ui-compact-<date>-after.png`
- **無量測工具**：列出已套用的策略 + 估算累計省下的 px，提示使用者手動驗證

## 7. 完成回報

3~5 行：
1. 偵測到的載體 + 入口檔
2. 套用了哪些策略、改了幾個檔
3. baseline → 結果 scrollHeight（若有量測），或預估壓縮量
4. 是否達標（無需下捲）；若未達，建議下一步
5. 截圖路徑（若有）

## 不要做的事

- ❌ 沒 `--apply` 就改檔
- ❌ 為了塞下硬隱藏 panel（除非 `--allow-collapse`）；目標是縮小不是藏起來
- ❌ 動 data 邏輯、API 呼叫、商業邏輯——只動 layout / 樣式
- ❌ 砍 a11y：文字對比、focus ring、`aria-*`、最小字體 < 12px 都不准動
- ❌ 搞壞 responsive：mobile / 窄螢幕不該被連帶壓爛，桌面變動用 `@media (min-width: ...)` 包
- ❌ 覆蓋使用者主題 CSS：以 override class 或新增 selector 為主
- ❌ 在 `--preserve` 名單裡的 panel 動手腳

## 邊界情況

- **找不到 dashboard** → 提示 `--file <path>` 指定
- **已經很 compact**（baseline 已 ≤ viewport） → 報告「無顯著壓縮空間」並退出
- **內容真的太多**（panel 數量 × 最小可讀高度仍 > viewport） → fallback 建議分頁 / tabs / virtualised list，並提示 `--allow-collapse`
- **多螢幕 / 視訊牆 / kiosk** → 用 `--viewport` 指定實際解析度（例如 `3840x2160`）
- **使用者只想看一個檔但 repo 多個 dashboard** → 用 `--file` 限定範圍
- **跑量測時 dashboard 未啟動** → 先提示用 `/run` 或 `/one-button-launch` 起服務

## 與其他 skill 協作

- **`/one-button-launch`**：量測前先把 dashboard 起起來
- **`/run`** / **`/verify`**：套用後跑起來目視確認
- **`/platform-compatible`**：CSS 修改後可順手檢查 cross-browser
- **Chrome DevTools / Playwright MCP**：本 skill `--measure` 的後端，做截圖 + scrollHeight 量測
- **`/safe-yolo`**：動多檔時包成 milestone

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/ui-compact/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入。
