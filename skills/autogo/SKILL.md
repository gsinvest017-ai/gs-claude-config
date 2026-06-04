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

Hook 注入**四個區塊**：

1. `[autogo-response]…[/autogo-response]` — markdown 表格（ECHO PATH 用）
2. `[autogo-meta]…[/autogo-meta]` — 預計算路由 signals（見下方路由表）
3. `[autogo-json]…[/autogo-json]` — 完整 FrameOutput JSON（FULL PATH 用）
4. `[autogo] context from ...` — breadcrumb（忽略）

---

### 1a. 空 `$ARGUMENTS` → **ECHO PATH**

逐字 echo `[autogo-response]` 與 `[/autogo-response]` 之間的內容，**一字不增不減**，不加文字、不加 footer。

---

### 1b. 非空 `$ARGUMENTS` → **先讀 `[autogo-meta]`，再路由**

`[autogo-meta]` 格式：
```
filter_applied: true|false
filter_unmatched: []
stub: true|false
cache_hit_all: true|false
```

**路由決策表（依序靜默執行；不要把路由過程、tool call 前旁白、內部推理輸出給 user；第一個命中即 STOP）：**

| 條件 | 回應 |
|------|------|
| `filter_unmatched` 非空陣列 | 開頭提醒「alias `X` 沒匹配到任何 watch 中的視窗」，**STOP** |
| `filter_applied: false` 且 `$ARGUMENTS` 含 `-w` | **在最終回應開頭**加一次 `⚠️ -w 過濾未套用（filter_aliases 空）`（不在之後重複） |
| `stub: true` 且問題是通用描述（「畫面上有什麼」「這個視窗顯示什麼」） | 回覆「⚠️ Stub backend：固定 stub 資料，不反映真實視窗。若要看真實畫面請安裝 PaddleOCR 並設 `AUTOGO_DASH_BACKEND=windows`。」加標準 footer，**STOP** |
| `stub: true`（非通用描述） | 前置加 `⚠️ Stub backend：畫面內容為固定 stub 資料` |
| `cache_hit_all: true` | 回覆「**畫面無變化（cached）**：N 個 watcher 均命中快取，若要刷新請按 Full pipeline 或等下一次 tick」，加標準 footer，**STOP** |
| 問題是「有沒有変化」類（無需 OCR 詳細） | 靜默 Grep persisted 檔的已知 key values；相同→「畫面無變化」**STOP**；不同→繼續 FULL |

以上均未 STOP → 走 **FULL PATH**：讀 `[autogo-json]` 回答問題。

**FULL PATH 可查欄位：**
- `watchers[].window_id/app/title/last_run_age_s/pipeline_ms/panels/text_blocks`
- `watchers[].output.panels[].{panel_id, bbox[x,y,w,h], panel_type, text_blocks[]}`
- `watchers[].output.panels[].text_blocks[].{bbox, text, confidence, font_size_est}`
- `watchers[].output.timings_ms` / `cache_meta`

**描述畫面時的規則：**
- 按 panel **y 座標由上到下**排列（不照 JSON 陣列順序）；同 y 層按 x 由左到右
- 使用 **bullet list 分段**，不要用 Markdown 表格（空 cell 視覺雜亂）
- confidence < 0.92 的 text_block，文字後加 `⁽?⁾` 行內標記
- JSON > 10KB（persisted 檔）且為通用描述查詢 → 先用 2KB preview，只有需要 bbox 精度時才 Read 完整
- **text_blocks 總數 > 20** → 僅輸出結構摘要（有幾個區域、每區大意各一行），不逐一列舉所有 OCR token；若 user 需要細節可追問特定區域

回應開頭點 watcher 來源，footer 加：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

---

### 1c. 沒看到 hook 注入（連 `[autogo-response]` 都沒）→ **Bash fallback**

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli --format=full`。輸出含 `not responding` → 告訴 user 啟 dashboard，**停**。`"watchers": []` → 告訴 user 去 /dash 勾視窗，**停**。正常 JSON → 走 1b 流程（手動 parse）。

## OCR 雜訊提醒（FULL PATH 用）

OCR 結果**會錯字、漏字、繁簡混雜**：
- 不要捏造 context 沒有的資訊（沒看到寄件人就別猜誰寄的）
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認
- 引用文字內容時 quote 原樣（包括雜訊），不要自動「修正」回正確字

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要**把路由決策過程或 tool call 前旁白（如「先 Grep...」「stub: false，這是真實 OCR！」）輸出給 user——meta 路由是完全靜默的內部判斷，user 只看最終回應。
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
