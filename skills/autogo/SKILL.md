---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話。當使用者輸入 /autogo、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」等情境時啟動。空 input 透過 Bash tool 顯示結構化 markdown table（tool block）；非空 input 用 hook 預注入的 markdown 走 FULL PATH 回答。
---

# /autogo

回答「使用者現在畫面上發生什麼」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 1 — 依 input 分支

### 1a. 空 `$ARGUMENTS` → **TOOL-USE PATH**

呼叫 Bash tool，**逐字**用以下 command 跟 description：

- command: `./.venv/Scripts/python.exe -m autogo_dash.context_structured`
- description: `autogo dashboard snapshot`

Bash 會印一個 markdown table（含 watcher 數、每視窗 row、Top OCR）到 stdout，那就是 user 看到的回覆內容（tool result block）。

**Bash 結束後不要再寫任何文字回覆**。不要加開場白、不要加分析、不要加 footer、不要 emoji 評論——`context_structured` 自己印的 markdown 已含 `_Refresh: /dash → 🎯 Watch selected_` footer。**Tool output IS your reply**。

### 1b. 非空 `$ARGUMENTS`（具體問題 / 指令式）→ **FULL PATH**

UserPromptSubmit hook 已經把完整 markdown（`# Autogo dashboard — Watch context @ ...` 區塊）與一行 `[autogo-response] ...` 壓縮回覆注進這個 turn 開頭。**用那段 markdown 內容**回答使用者的具體問題，繁中、開頭點 watcher 來源、引用必要的 OCR 文字、明顯漏字提示去 `/inspect`。

回答結尾**加 footer**：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

N、X 從 markdown `N window(s) watched` / `updated Xs ago` 解析。

### 1c. 沒看到 hook 注入 + Bash 也沒辦法跑 → **FALLBACK**

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli`。輸出含 `not responding` → 告訴 user 啟 dashboard，停。含 `0 window(s) watched` → 告訴 user 去 /dash 勾視窗，停。正常 markdown → 走 1b 流程。

## Step 2 — FULL PATH 解讀（TOOL-USE PATH 跳過）

- `## N. <APP_NAME> — "<title>"` = 視窗當下狀態
- `- updated Xs ago • N panels • M text blocks` = pipeline metadata
- 其餘 bullet = OCR / segment 結果（confidence 排序）

OCR **會錯字、漏字、繁簡混雜**：
- 不要捏造 context 沒有的資訊
- 引用要點出來源 watcher：「在你 watch 的 OUTLOOK.EXE 視窗看到…」
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要** 在 TOOL-USE PATH（1a）寫任何文字回覆 — tool output 就是 user 看到的全部，多寫一個字就違反設計（每多 100 chars LLM 多吐 ~1.2 秒）。
- ❌ **不要** 把原 markdown echo 給 user 看（dashboard 自己可以開）。
- ❌ **不要** 把 OCR 當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
