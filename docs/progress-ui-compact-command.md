# 進度：新增 /ui-compact 全域 slash command

## 目標

在 `gs-claude-config`（= `~/.claude` 的 chezmoi 來源）新增一個 **system-level global agent command `/ui-compact`**：在任一專案 repo 內觸發時，偵測 dashboard UI 載體（HTML、Streamlit、Gradio、Dash、React/Vue…），分析現況高度，套用一組由輕到重的 compaction 策略（縮 padding / 字體、grid 重排、圖表降高、合併標題列…），讓**所有 panels 在預設 viewport 內無需下捲即可看完**。完成後安裝到 user-scope（全域）。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/ui-compact` skill | `docs/progress-ui-compact-command.md`、`skills/ui-compact/SKILL.md` |
| **M2** | 驗證全域註冊 + 收尾 | frontmatter 解析通過、出現在 skill 清單、進度檔收尾、最終報告 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /ui-compact

- 建立本進度檔。
- 新增 `skills/ui-compact/SKILL.md`：frontmatter + 8 段流程：解析參數 → 偵測載體（HTML / Streamlit / Gradio / Dash / React / Vue / Tailwind / Bootstrap，含 autogo 專案特記）→ baseline 量測（優先用 Chrome DevTools / Playwright MCP 抓 scrollHeight + 截圖，否則靜態估算）→ **10 個 compaction 策略代號表 B/C/D/E/G/I/K/J/A/F**（含偵測訊號、套用方式、風險）→ plan/diff preview → apply（加 compacted 標記）→ 驗證（重量 scrollHeight 與 innerHeight 比較）→ 完成回報；含不要做的事、邊界情況、跨 skill 協作、全域註冊。
- 關鍵設計：
  1. **預設 dry-run + 需 `--apply`**，避免無意中改檔。
  2. **「縮到能容納」不是「藏起來」**：摺疊（策略 F）是最後手段、需 `--allow-collapse` 明示。
  3. **策略由低風險到重塑排序**：先字體 / padding / 圖表高度 / Tailwind class，必要才 grid 重排，最後才摺疊。
  4. **不動 a11y / data / responsive**：明確禁止砍對比、focus、最小字體；桌面變動用 media query 包。
  5. **整合 Chrome DevTools / Playwright MCP** 作為量測後端（前後 scrollHeight 對照 + 截圖）。
- 兩檔正規化為 CRLF。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`，remote `origin` = github.com/gsinvest017-ai/gs-claude-config.git。
- 本任務**只 commit 到本機 `main`，不 push**。
- Rollback：`git -C C:\Users\User\gs-claude-config log --oneline` 找 `Mn:` commit，`git reset --hard <hash>` 回退。
- 整個撤掉：刪 `skills/ui-compact/`、本進度檔，再 `git checkout -- .`。
- 新 skill 通常即時出現在 available-skills 清單；若沒有，開新的 Claude Code session 即可。
