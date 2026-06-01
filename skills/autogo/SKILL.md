---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話 context。當使用者輸入 /autogo、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」等情境時啟動。Dashboard 的 watcher pool 內容通常已由 UserPromptSubmit hook 在 prompt 注入；hook 失敗才 fallback 跑 `python -m autogo_dash.context_cli`。
---

# /autogo

回答「使用者現在畫面上發生什麼」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 1 — 認 context 形式

UserPromptSubmit hook 通常注入兩段東西在 turn 開頭：

1. 一行 `[autogo-response] ...` — **完整 pre-rendered 繁中回覆**（給空 input 走 ECHO PATH 用）
2. 完整 `# Autogo dashboard — Watch context @ ...` markdown（給具體問題 / 指令走 FULL PATH 用）

依下列規則分支：

### 1a. 空 `$ARGUMENTS` + 有 `[autogo-response]` 行 → **ECHO PATH**

**逐字 echo 那一行（去掉開頭的 `[autogo-response] ` prefix）作為你完整的回覆**。**不要**加任何分析、推測、footer、開場白、註解。**不要**讀原 markdown。**不要**思考。EXAMPLE 輸入：

> `[autogo-response] **WindowsTerminal.exe: "autogo-cv"** (1.77s 前) · OCR: \`Status [1] / 19578cd\` · _1w · /dash 重按 🎯 更新_`

你的整段回覆應為（**逐字**，不增不減）：

> **WindowsTerminal.exe: "autogo-cv"** (1.77s 前) · OCR: `Status [1] / 19578cd` · _1w · /dash 重按 🎯 更新_

Footer 已在 response 行內、不要另加。**整個回覆就一行、就這樣**。

### 1b. 非空 `$ARGUMENTS`（具體問題 / 指令式）→ FULL PATH

走原本詳細流程：讀完整 markdown、依 watcher 引用、OCR 雜訊提醒、繁中回答；結尾**另加** footer：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

N、X 從 markdown `N window(s) watched` / `updated Xs ago` 解析。

### 1c. 沒看到 hook 注入（連 `[autogo-response]` 都沒）→ Bash fallback

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli`。依輸出分支：
- `not responding` → 告訴 user 啟 dashboard，**停**。
- `0 window(s) watched` → 告訴 user 去 /dash 勾視窗，**停**。
- 正常 markdown → 走 Step 2 / 3（FULL PATH）。

## Step 2 — FULL PATH 解讀（ECHO PATH 跳過）

- `## N. <APP_NAME> — "<title>"` = 視窗當下狀態
- `- updated Xs ago • N panels • M text blocks` = pipeline metadata
- 其餘 bullet = OCR / segment 結果（confidence 排序）

OCR **會錯字、漏字、繁簡混雜**。回答時：
- 不要捏造 context 沒有的資訊（沒看到寄件人就別猜誰寄的）
- 引用要點出來源 watcher：「在你 watch 的 OUTLOOK.EXE 視窗看到…」
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認

## Step 3 — FULL PATH 回答（ECHO PATH 跳過）

- 具體問題（"latest email?" / "summarize my browser"）→ 用 context 回答、開頭點 watcher 來源
- 指令式（"draft a reply" / "search for code"）→ 基於 context 協助；要更多細節讓 user 切視窗讓 watcher 抓新 frame

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要** 把原 markdown echo 給 user（他自己看 dashboard）。
- ❌ **不要** 把 OCR 當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
- ❌ **不要** 在 ECHO PATH 加任何文字（包含解釋、開場白、footer、emoji 評論等）— 整個回覆就是 response 行的內容，**一字不增不減**。違反 ECHO PATH 紀律 = 每多 100 chars LLM 多吐 ~1.2 秒。
