---
name: autogo
description: 把 autogo dashboard 正在 watch 的視窗最新 OCR/segment 結果拉進對話 context。當使用者輸入 /autogo、說「我畫面上現在是什麼」、「outlook 有什麼新信」、「summarize my screen」等情境時啟動。空 input 直接 echo hook 預 render 的 markdown table 區塊；非空 input 用 hook 注入的原 markdown 走 FULL PATH。
---

# /autogo

回答「使用者現在畫面上發生什麼」。視窗 OCR / segment 由 autogo dashboard 在背景跑 pipeline，結果由 watcher pool 端點提供。

User input：`$ARGUMENTS`

## Step 1 — 認 context 形式

UserPromptSubmit hook 通常注入以下三個東西在 turn 開頭：

1. `[autogo-response]` 與 `[/autogo-response]` 之間的 markdown table 區塊（空 input ECHO PATH 用）
2. `[autogo] context from ...` 一行 breadcrumb（不要 echo、不要解讀）
3. 完整 `# Autogo dashboard — Watch context @ ...` markdown（非空 input FULL PATH 用）

依下列規則分支：

### 1a. 空 `$ARGUMENTS` + 有 `[autogo-response]` 區塊 → **ECHO PATH**

**逐字 echo `[autogo-response]` 與 `[/autogo-response]` 之間的內容**（不含這兩個 sentinel 標記本身）作為你完整的回覆。

EXAMPLE 輸入：
```
[autogo-response]
## autogo dashboard — 1 watcher(s)

| # | App | Title | Updated | Top OCR |
|---|-----|-------|---------|---------|
| 1 | WindowsTerminal.exe | autogo-cv | 1.77s ago | Status [1] · 19578cd · 2026-05-29 |

_Refresh: /dash → 🎯 Watch selected_
[/autogo-response]
```

你的整段回覆應為（**逐字**，含換行、不增不減、不要 sentinel）：

```
## autogo dashboard — 1 watcher(s)

| # | App | Title | Updated | Top OCR |
|---|-----|-------|---------|---------|
| 1 | WindowsTerminal.exe | autogo-cv | 1.77s ago | Status [1] · 19578cd · 2026-05-29 |

_Refresh: /dash → 🎯 Watch selected_
```

Footer 已在區塊內、不要再加。**不要**寫開場白、不要分析、不要 emoji 評論。**不要**讀區塊外的 `# Autogo dashboard ...` 原 markdown。

### 1b. 非空 `$ARGUMENTS`（具體問題 / 指令式）→ **FULL PATH**

**用區塊外的 `# Autogo dashboard — Watch context @ ...` 原 markdown** 內容回答使用者的具體問題，繁中、開頭點 watcher 來源、引用必要的 OCR 文字、明顯漏字提示去 `/inspect`。

回答結尾**加 footer**：

> _autogo context 來自 N 個 watcher（拉取時間 X 秒前）；若需更新請等下一次 watcher tick 或在 dashboard 重按一次 `🎯 Watch selected`。_

N、X 從 markdown `N window(s) watched` / `updated Xs ago` 解析。

### 1c. 沒看到 hook 注入（連 `[autogo-response]` 都沒）→ **Bash fallback**

從 autogo repo 根目錄跑 `./.venv/Scripts/python.exe -m autogo_dash.context_cli`。輸出含 `not responding` → 告訴 user 啟 dashboard，**停**。含 `0 window(s) watched` → 告訴 user 去 /dash 勾視窗，**停**。正常 markdown → 走 1b 流程。

## Step 2 — FULL PATH 解讀（ECHO PATH 跳過）

- `## N. <APP_NAME> — "<title>"` = 視窗當下狀態
- `- updated Xs ago • N panels • M text blocks` = pipeline metadata
- 其餘 bullet = OCR / segment 結果（confidence 排序）

OCR **會錯字、漏字、繁簡混雜**：
- 不要捏造 context 沒有的資訊
- 引用要點出來源 watcher：「在你 watch 的 OUTLOOK.EXE 視窗看到…」
- 明顯漏字 / 截斷時提示 user 去 dashboard `/inspect` 親眼確認

## 不要做的事

- ❌ **不要** curl `/api/dash/frame` 或 `/api/dash/ocr` — 繞過 watcher pool 與 context cap。
- ❌ **不要** 在 ECHO PATH 加任何文字（含開場白、解釋、footer、emoji 評論）— 整個回覆就是 sentinel 之間的內容，**一字不增不減**。違反 ECHO PATH 紀律 = 每多 100 chars LLM 多吐 ~1.2 秒。
- ❌ **不要** echo `[autogo-response]` / `[/autogo-response]` sentinel 本身 — 那是給 skill 切範圍用的標記、user 不需要看。
- ❌ **不要** 把原 markdown echo 給 user 看（dashboard 自己可以開）。
- ❌ **不要** 把 OCR 當 deterministic source of truth 下重大決策（請 user 在 `/inspect` 親眼確認）。
