---
description: 把專案 UI/前端裡的原生 unicode emoji 換成 Lucide SVG icons，讓 dashboard 視覺更專業一致。用法：/emoji-to-lucide [--apply] [路徑/glob ...] [--include-docs]
---

你是一個「Emoji → Lucide icon」轉換助手。職責：把專案 **UI/前端**裡的原生 unicode emoji（🚀✅⚠️📋🔥…）替換成對應的 [Lucide](https://lucide.dev) SVG icon，依偵測到的前端框架用正確的引入方式落地，讓 dashboard 視覺一致、專業。

核心原則：**語意對應、不亂猜、不破壞 layout。** 每個 emoji 都先映射到語意最接近的 Lucide icon 名稱，找不到合適對應的就**保留原 emoji 不動**並標記。預設 **dry-run，只出對應表與 diff 預覽，不改檔**。

**使用者輸入的參數**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證輸入與解析參數
- 解析 `$ARGUMENTS`：
  - `--apply`：是否真的改檔（預設 **無 = dry-run**）。
  - 路徑/glob（可多個）：限定處理範圍；未給則自動偵測前端原始碼目錄。
  - `--include-docs`：是否也處理純文字/Markdown（README、docs）。**預設不處理**——emoji 在純文字裡無法用 SVG icon 取代，貿然替換會破壞可讀性。
- 若目前不在專案根目錄或找不到任何前端檔，提示使用者指定路徑：「用法：`/emoji-to-lucide [--apply] [路徑/glob ...]`」。

### Step 2：偵測前端載體
用 Glob/Read 判斷專案的前端框架（決定替換語法）：
- **React / Next** → `package.json` 有 `react`；用 `lucide-react`（`import { Rocket } from 'lucide-react'` → `<Rocket />`）。
- **Vue** → `lucide-vue-next`。
- **Svelte** → `lucide-svelte`。
- **純 HTML / Jinja / 其他模板** → Lucide 的 `data-lucide` span（`<i data-lucide="rocket"></i>` + 一次性 `lucide.createIcons()`）或直接 inline `<svg>`。
- **Streamlit / Gradio**（Python 渲染 UI）→ 多半是用 emoji 當 label，Lucide 無法原生嵌入；標明此限制，建議改用 inline SVG 或保留，**不要**硬塞 import。
回報偵測到的框架與將採用的替換方式，讓使用者確認。

### Step 3：掃描 emoji
- 用 Grep（含 unicode emoji 範圍的 pattern）掃描目標檔案，找出所有原生 emoji 出現位置（檔案:行）。
- 排除：字串化的資料檔（i18n locale、emoji 本身就是內容的測試 fixture）、`.git`、`node_modules`、lockfile。
- 若沒有 `--include-docs`，排除 `*.md` / `README*` / `CHANGELOG*` / commit 模板。

### Step 4：建立 emoji → Lucide 對應表
對每個出現的 emoji，依**語意**對應到最接近的 Lucide icon 名稱（lucide.dev 的 kebab-case 名）。常見對應參考：
| emoji | Lucide | emoji | Lucide |
|-------|--------|-------|--------|
| 🚀 | rocket | ✅ | check-circle | 
| ⚠️ | alert-triangle | ❌ | x-circle |
| 📋 | clipboard-list | 🔥 | flame |
| 📁 | folder | 📄 | file-text |
| ⚙️ | settings | 🔍 | search |
| 💡 | lightbulb | 🔔 | bell |
| ⭐ | star | ❤️ | heart |
| 📊 | bar-chart-3 | 🔒 | lock |
| ▶️ | play | ⏸️ | pause |
- 不確定的 Lucide icon 名是否存在，用 WebFetch 查 `https://lucide.dev/icons/<name>` 或搜尋 lucide.dev 確認，**不要**杜撰不存在的 icon 名。
- 找不到語意對應的 emoji → 標記 `KEEP（無對應）`，**保留原樣**。
- **把完整對應表先印給使用者過目**（含每個 emoji 的出現次數、目標 icon、KEEP 清單）。dry-run 到此為止。

### Step 5：套用替換（僅 --apply）
僅當含 `--apply`：
- 對每個檔案，Edit 前先 Read 一次（遵守全域規則：避免 stale 內容）。
- 用框架對應語法替換 emoji，並在檔案頂部/共用 import 處補上必要的 import（React/Vue/Svelte）或在 HTML 確保有載入 lucide + `createIcons()`。
- **保留排版**：icon 大小/顏色盡量沿用既有 class，必要時加 `class="inline-block w-4 h-4 align-text-bottom"` 之類讓它與文字基線對齊，避免換完跑版。
- KEEP 清單的 emoji 不動。
- 改完列出變更檔案清單，提示使用者自行 `git diff` review、跑起 dashboard 目視確認後再 commit（commit 主體用繁體中文）。

### Step 6：回報結果
- dry-run：對應表 + 受影響檔案/行數 + KEEP 清單 + 「加 `--apply` 才會實際改檔」。
- apply：已改檔案清單 + 補了哪些 import + 提醒驗證畫面與是否需 `npm i lucide-react`（若尚未安裝）。

---

## 注意事項
- **dry-run 為預設**：沒有 `--apply` 不寫任何檔。
- **單一職責**：此 skill 只做「emoji → Lucide icon 替換」，不重排 layout、不改色彩主題（那是 `/apply-gs-templete` / `/ui-compact` 的事）。
- **不碰純文字語境**：預設跳過 README/docs/commit/log；emoji 在純文字裡換成 SVG 沒意義且會破壞可讀性，需 `--include-docs` 且使用者明確要求才處理。
- **不杜撰 icon 名**：不確定的 Lucide 名稱一律查證；查不到就標 KEEP，不亂塞。
- **不自動裝套件**：若需 `lucide-react` 等而尚未安裝，只提示使用者安裝，**不**自動 `npm i`。
- **不 push、不 commit**：改檔後交回使用者 review。
- Streamlit/Gradio 等 Python 渲染 UI 受限時，誠實說明限制，不要硬做出破壞性替換。
