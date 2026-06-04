---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話 context。當使用者輸入 /autogo、`/autogo -w <window-alias>`、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」、「debug 一下 OCR / segment 結果」、「只看某個視窗的內容」等情境時啟動。空 input 直接 echo hook 預 render 的 markdown table 區塊；非空 input 用 hook 注入的完整 FrameOutput JSON 走 FULL PATH（含 bboxes / confidences / panel tree / timings_ms / cache_meta）回答。支援 `-w <alias>` 視窗過濾。
---

# /autogo

回答「使用者現在畫面上發生什麼」+「OCR/segment 結果的 debug/dev 問題」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 0 — `-w <alias>` 視窗過濾（hook 自動處理、skill 只需要認）

如果 `$ARGUMENTS` 含 `-w <alias1> [<alias2> ...]` 旗標，hook 已經把該選擇傳給 dashboard server、注入的 `[autogo-json]` 區塊**只含匹配的 watcher**（substring case-insensitive 對 `app_name` 或 `title`）。範例：

- `/autogo -w outlook` → 只看 OUTLOOK.EXE
- `/autogo -w autogo-cv` → 標題含 "autogo-cv" 的視窗
- `/autogo -w outlook chrome` → outlook + chrome 兩個視窗的 union

JSON 區塊內 `filter_aliases` 列出 user 給的所有 alias、`filter_unmatched` 列出沒匹配到任何 watcher 的 alias。**若 `filter_unmatched` 非空，回覆**開頭提醒 user**：「alias `xyz` 沒匹配到任何 watch 中的視窗，請去 /dash 確認該視窗是否已勾選」。

## Step 1 — 認 context 形式

UserPromptSubmit hook 通常注入以下**三個區塊**在 turn 開頭：

1. `[autogo-response]` 與 `[/autogo-response]` 之間的 markdown table — **空 input ECHO PATH 用**
2. `[autogo-json]` 與 `[/autogo-json]` 之間的**完整 FrameOutput JSON** — 含 per-watcher 的 `output.panels[]`（含 `panel_id` / `bbox` / `parent_id` / `panel_type` / `text_blocks[]`，每個 text_block 含 `bbox` / `text` / `confidence` / `font_size_est`）、`timings_ms`、`cache_meta`、`window_id` 等。**非空 input FULL PATH 用**。
3. `[autogo] context from ...` 一行 breadcrumb（不要 echo、不要解讀）

依下列規則分支：

### 1a. 空 `$ARGUMENTS` + 有 `[autogo-response]` 區塊 → **ECHO PATH**

**逐字 echo `[autogo-response]` 與 `[/autogo-response]` 之間的內容**（不含 sentinel）作為你完整的回覆。**不要**讀 `[autogo-json]` 區塊、**不要**加任何文字、不要 emoji 評論。Footer 已內含、不要再加。

### 1b. 非空 `$ARGUMENTS`（具體問題 / 指令 / debug query）→ **FULL PATH**

**讀 `[autogo-json]` 區塊**內的 JSON（這是完整 FrameOutput per watcher，含結構化資料）。具體可查的欄位：

- `watchers[].window_id` / `app` / `title` / `last_run_age_s` / `pipeline_ms` / `panels` / `text_blocks` — 視窗 + pipeline metadata
- `watchers[].output.panels[]` — 每個 panel 的 `panel_id` / `bbox: [x, y, w, h]` / `panel_type: title|content|sidebar|toolbar` / `parent_id`（panel 階層）
- `watchers[].output.panels[].text_blocks[]` — 每個 OCR block 的 `bbox` / `text` / `confidence` / `font_size_est`
- `watchers[].output.timings_ms` — `capture` / `list_windows` / `incremental` / `fuse` / `total`
- `watchers[].output.cache_meta` — `hit` / `changed_regions` / `phash_distance` / `fresh_blocks` / `cached_blocks` / `cache_size` / `ttl_remaining_ms`

**在輸出 OCR 詳細內容前，先做 cache_meta 無變化判斷：**

條件：watcher 的 `output.cache_meta.hit = true` 且 `phash_distance = 0`（或 `phash_distance` 欄位不存在）→ 該 watcher 標記為「無變化」。

- **所有 watcher 均無變化** → 回覆下列內容後**停止**，不輸出任何 OCR 詳細內容：

  > **畫面無變化（cached）**：N 個 watcher 均命中快取（phash_distance=0），畫面內容與上次相同。若要強制刷新，請在 dashboard 按「Full pipeline」或等下一次 watcher tick。

  接著加標準 footer 後結束。

- **部分 watcher 有變化** → 只對有變化（`hit=false` 或 `phash_distance > 0`）的 watcher 輸出完整 OCR 結果；無變化的 watcher 只附一行：`⬜ [app] title — 無變化（cached，phash_distance=0）`，不展開 text_blocks。

**變化偵測快捷路徑（`cache_meta` 缺失時）：**

若 `cache_meta` 欄位不存在（stub backend 常見），且問題是純粹的「有沒有変化」類查詢（不需要詳細 OCR 內容），使用快捷路徑而不是讀完整 JSON：

1. 在對話 context 中記住上次觀測的「key display values」（例如計算機顯示的數字、主要顯示欄位內容）。
2. 用 Grep tool 在 persisted 檔中搜尋這些關鍵值（例如 `grep "1024|1280"` 確認計算機數字）。
3. 若 Grep 找到且值相同 → 回覆「畫面無變化」，**停止**，不讀完整 JSON。
4. 若 Grep 找不到或值不同 → 改用完整讀取流程（Read persisted 檔 → parse calc.exe 段）。

此快捷路徑節省 Read + parse 兩個 tool call（對 60–100KB 檔案效果明顯）。只適用於「有沒有変化」這類簡單比較，複雜 debug 查詢仍走完整 JSON 路徑。

**filter 透明度：**

回答前先確認 `filter_aliases` 欄位：
- `filter_aliases: []`（空）→ 本次 `-w` 過濾**未生效**（hook 未傳 alias），回應中注記「⚠️ `-w <alias>` 過濾未套用，以下顯示的是所有 watcher 的結果」
- `filter_unmatched` 非空 → 開頭提醒（見 Step 0）

**Stub backend 偵測：**

若任何 watcher 的 text_block 內容含 `seed=0`、`StubCapture` 或 `(mock OCR` → 在回應開頭加一行：
> ⚠️ **Stub backend**：畫面內容為固定 stub 資料，不反映真實視窗狀態。

**通用「畫面上有什麼」快捷路徑：**

查詢意圖是「描述/摘要螢幕內容」（如「畫面上有什麼」「這個視窗顯示什麼」），且 JSON 大於 10KB（persisted 檔）時：先用 persisted 檔前 2KB preview 確認主要 panel 與 text block，只有需要 bbox 精度或完整 text 時才 Read 完整檔案。

**空間排序原則：**

描述畫面內容時按 panel 的 **y 座標由上到下**排列（不照 JSON 陣列順序），讓 user 看到的是自然的「頂部→中部→底部」空間布局。同一 y 層若有多個 panel，按 x 座標由左到右排列。

**OCR 可疑 token 行內標記：**

引用 OCR 文字時若同一 text_block 的 confidence < 0.92，在文字後加 `⁽?⁾` 提示。例：「`2.技術機⁽?⁾`」而不是等到 footer 才統一提醒。

用這些**結構化資料**回答 user 問題（例如「Status [1] block 的 confidence 多少」「最大的 panel bbox 是哪個」「pipeline 慢在哪一步」）、繁中、開頭點 watcher 來源。Footer 加：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

N 從 JSON `watchers` 陣列長度；X 從 `watchers[0].last_run_age_s` 取（或從 `[autogo-response]` 區塊內 table 的 `Updated` 欄）。

### 1c. 沒看到 hook 注入（連 `[autogo-response]` 都沒）→ **Bash fallback**

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli --format=full`。輸出含 `not responding` → 告訴 user 啟 dashboard，**停**。`"watchers": []` → 告訴 user 去 /dash 勾視窗，**停**。正常 JSON → 走 1b 流程（手動 parse）。

## OCR 雜訊提醒（FULL PATH 用）

OCR 結果**會錯字、漏字、繁簡混雜**：
- 不要捏造 context 沒有的資訊（沒看到寄件人就別猜誰寄的）
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認
- 引用文字內容時 quote 原樣（包括雜訊），不要自動「修正」回正確字

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要** 在 ECHO PATH 加任何文字（含開場白、解釋、footer、emoji 評論）— 整個回覆就是 sentinel 之間的內容，**一字不增不減**。
- ❌ **不要** echo `[autogo-response]` / `[autogo-json]` / `[/autogo-json]` sentinel 本身、也不要 echo 整段 JSON 給 user（JSON 是給你 introspect 用的、user 自己會去 dashboard Copy JSON）。
- ❌ **不要** 把 OCR 文字當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
- ❌ **不要** 在 FULL PATH 引用 `confidence` 數字後就拍胸脯「這個 95% 對」—— confidence 是模型自評、不等於正確率。需要 deterministic 時請 user 在 `/inspect` 對。

## 搭配 /loop 做定期監控

`/autogo` 本身是一次性 pull；若要**定期把畫面更新推進 Claude context**，搭配 `/loop` 使用：

```
/loop 1m /autogo -w <alias> 有沒有什麼變化
```

- `/loop` 每 N 分鐘重新觸發一次 `/autogo`；hook 會拉新一輪快照注入 context
- 搭配 cache_meta 無變化判斷：若畫面沒動，Claude 只回「畫面無變化（cached）」，不浪費 context
- Watcher 的 tick interval（畫面擷取頻率）是在 dashboard UI 的 `interval(s)` 欄位設定，與 `/loop` 間隔獨立——建議 `/loop` 間隔 ≥ watcher tick interval，避免每次都拉到同一張快照
- ⚠️ **最小間隔為 1 分鐘**：cron 粒度限制，`30s` 會自動進位為 `1m`。若需真正 30 秒觸發，改用 `/loop`（無 interval）並讓 Claude 以 ScheduleWakeup 自迴圈

**常用場景範例：**

| 指令 | 說明 |
|------|------|
| `/loop 1m /autogo -w outlook 有新信嗎` | 每分鐘檢查一次 Outlook，有新信才說 |
| `/loop 1m /autogo -w mock-calc 數字變了嗎` | 每分鐘看 Calculator 顯示值是否改變 |
| `/loop 5m /autogo -w autogo 說明 pipeline 狀態` | 每 5 分鐘回報 autogo dashboard pipeline 進度 |
