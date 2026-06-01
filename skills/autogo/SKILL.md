---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話 context。當使用者輸入 /autogo、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」等情境時啟動。Dashboard 的 watcher pool 內容通常已由 UserPromptSubmit hook 在 prompt 注入；hook 失敗才 fallback 跑 `python -m autogo_dash.context_cli`。
---

# /autogo

回答「使用者現在畫面上發生什麼」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 1 — 認 context 形式

UserPromptSubmit hook 通常注入兩段東西在 turn 開頭：

1. 一行 `[autogo-summary] ...` — 壓縮摘要（給空 input 走 FAST PATH 用）
2. 完整 `# Autogo dashboard — Watch context @ ...` markdown（給具體問題 / 指令走 FULL PATH 用）

依下列規則分支：

### 1a. 空 `$ARGUMENTS` + 有 `[autogo-summary]` 行 → FAST PATH

**只**根據 summary 行寫一行繁中、body ≤ 100 chars，**不要**讀原 markdown、不要 Bash、不要詳細分析 OCR 雜訊。模板：

> 你在 **<APP>: "<title>"**（<X>s 前更新）。OCR top：`<a> / <b> / <c>`。<一句使用者最可能在做什麼>。

特例 summary：
- `[autogo-summary] down` → 「dashboard 沒回應。先跑 `./.venv/Scripts/python.exe -m uvicorn web.app:app --port 8765 --host 127.0.0.1`、開 /dash、勾視窗、按 🎯 Watch selected」，然後**停**。
- `[autogo-summary] no-watchers` → 「dashboard 在跑但沒 watcher。/dash 勾視窗、按 🎯 Watch selected」，然後**停**。

### 1b. 非空 `$ARGUMENTS`（具體問題 / 指令式）→ FULL PATH

走原本詳細流程：讀完整 markdown、依 watcher 引用、OCR 雜訊提醒、繁中回答。

### 1c. 沒看到 hook 注入（連 `[autogo-summary]` 都沒）→ Bash fallback

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli`。依輸出分支：
- `not responding` → 告訴 user 啟 dashboard，停。
- `0 window(s) watched` → 告訴 user 去 /dash 勾視窗，停。
- 正常 markdown → 進 Step 2 走 FULL PATH。

## Step 2 — FULL PATH 解讀（FAST PATH 跳過）

- `## N. <APP_NAME> — "<title>"` = 視窗當下狀態
- `- updated Xs ago • N panels • M text blocks` = pipeline metadata
- 其餘 bullet = OCR / segment 結果（confidence 排序）

OCR **會錯字、漏字、繁簡混雜**。回答時：
- 不要捏造 context 沒有的資訊（沒看到寄件人就別猜誰寄的）
- 引用要點出來源 watcher：「在你 watch 的 OUTLOOK.EXE 視窗看到…」
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認

## Step 3 — FULL PATH 回答（FAST PATH 跳過）

- 具體問題（"latest email?" / "summarize my browser"）→ 用 context 回答、開頭點 watcher 來源
- 指令式（"draft a reply" / "search for code"）→ 基於 context 協助；要更多細節讓 user 切視窗讓 watcher 抓新 frame

## Footer（FAST PATH 與 FULL PATH 都加）

回答結尾**永遠**附上一行：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

- FAST PATH：N 從 `[autogo-summary] Nw` 的 N 解析；X 從 `@Xs` 解析。
- FULL PATH：N 從 markdown `N window(s) watched` 解析；X 從 `updated Xs ago` 解析。

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要** 把整段 markdown echo 回給 user（他自己看 dashboard）。
- ❌ **不要** 把 OCR 當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
- ❌ **不要** 在 FAST PATH 路徑寫超過 ~100 chars body — 那違反整個 fast path 設計（LLM 多吐字 = 多等 1-3 秒）。
