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
