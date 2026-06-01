---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話 context。當使用者輸入 /autogo、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」等情境時啟動。Dashboard 的 watcher pool 內容通常已由 UserPromptSubmit hook 在 prompt 注入；hook 失敗才 fallback 跑 `python -m autogo_dash.context_cli`。
---

# /autogo

回答「使用者現在畫面上發生什麼」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 1 — 取得 context

**UserPromptSubmit hook 通常已把 markdown 注進這個 turn 的 prompt**。在當前 user message / `<user-prompt-submit-hook>` 區塊找一段以 `# Autogo dashboard — Watch context @` 開頭的 markdown：

- **有 → 直接用、進 Step 2**（不要再呼 Bash，會重複抓且慢）。
- **沒有**（hook 沒啟用或失敗）→ Bash tool 從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli`。依結果分支：
  - 出現 `not responding` / `dashboard down` → dashboard 沒起。告訴 user：
    1. `./.venv/Scripts/python.exe -m uvicorn web.app:app --port 8765 --host 127.0.0.1`
    2. 開 `http://localhost:8765/dash`、勾視窗、按 `🎯 Watch selected`
    然後**停**，不要回答 user 原本的問題。
  - 含 `No active watchers` / `0 window(s) watched` → 有 server 但沒 watcher。告訴 user 去 `/dash` 勾視窗 + 按 `🎯 Watch selected`，然後**停**。
  - 正常 markdown → 進 Step 2。

## Step 2 — 解讀 context

- `## N. <APP_NAME> — "<title>"` = 視窗當下做什麼
- `- updated Xs ago • N panels • M text blocks` = pipeline metadata
- 其餘 bullet = OCR / segment 抓到的文字（confidence 排序）

OCR **會錯字、漏字、繁簡混雜**。回答時：

- 不要捏造 context 沒有的資訊（沒看到寄件人就別猜誰寄的）
- 引用要點出來源 watcher：「在你 watch 的 OUTLOOK.EXE 視窗看到…」
- 明顯漏字 / 截斷時提示使用者去 dashboard `/inspect` 親眼確認

## Step 3 — 根據 user input 回答

- **空 input** → 每個 watcher 一段繁中 summary（2-3 段總計），重點放「使用者最可能在做什麼」
- **具體問題**（"latest email about?" / "summarize my browser"）→ 用 context 回答、開頭點 watcher 來源
- **指令式**（"draft a reply" / "search for similar code"）→ 基於 context 協助；要更多細節讓 user 切視窗讓 watcher 抓新 frame

**回答結尾永遠**附上一行：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

N 跟 X 從 markdown 的 `## ` heading + `updated Xs ago` 解析。

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 那會繞過 watcher pool 與 context cap。一律走 context_cli / hook。
- ❌ **不要** 把整段 markdown echo 回去給使用者（他自己看 dashboard）。
- ❌ **不要** 假設 context 反映所有開著的視窗 — 只反映他**勾選 watch** 的那些。
- ❌ **不要** 把 OCR 文字當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
