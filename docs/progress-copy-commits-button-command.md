# 進度：新增 /copy-commits-button 全域 slash command

## 目標

在 `gs-claude-config`（= `~/.claude` 的 chezmoi 來源）新增一個 **system-level global agent command `/copy-commits-button`**：在任一帶 dashboard 的 repo 內觸發時，**在 dashboard 的（每個 repo）panel 中注入一個「📋 複製今日 commits」按鈕**，按一下就把當日該 repo 的 commits（含 safe-yolo `Mn:` 鏈合併、分類、簡述）以 **markdown 風格**寫進剪貼簿，方便使用者貼到工作群組訊息。完成後安裝到 user-scope（全域）。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/copy-commits-button` skill | `docs/progress-copy-commits-button-command.md`、`skills/copy-commits-button/SKILL.md` |
| **M2** | 驗證全域註冊 + 收尾 | frontmatter 解析通過、出現在 skill 清單、進度檔收尾、最終報告 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /copy-commits-button

- 建立本進度檔。
- 新增 `skills/copy-commits-button/SKILL.md`：frontmatter + 9 段流程：解析參數 → 偵測 dashboard 載體（含 autogo 專案特記）→ 收集今日 commits（共用 `/git-tag` 的 `Mn:` chain 合併規則：N 重設切新 group、skip 不獨立）→ markdown 格式 3 種風格（GitHub / Slack mrkdwn / Plain，含 emoji 對應）→ 後端 endpoint（FastAPI 範例 + 安全：白名單 + 拒絕 path traversal）→ 前端按鈕注入 3 種 placement（new-panel / each-panel / toolbar）+ Streamlit 變體 + HTTPS clipboard fallback → 寫檔（區塊標記保留人工內容）→ 驗證（Playwright 讀 `clipboard.readText` 比對）→ 完成回報；含不要做的事、邊界情況、跨 skill 協作、全域註冊。
- 關鍵設計：
  1. **與 `/git-tag` 共享 `Mn:` 鏈合併規則**，輸出的 milestone 分組與 tag 對得起來。
  2. **資安**：endpoint 只認 `--repos` 白名單、拒絕 `..`、不暴露 body / 檔案內容、預設只自己 commits、絕不自動帶 `@here` / `@channel`。
  3. **HTTPS clipboard 限制**：偵測非 secure context 時自動降回 `<textarea>` + `execCommand('copy')` fallback，並提示改 HTTPS。
  4. **保留既有 UI**：只**新增** panel / 按鈕，不改既有 endpoint / panel；標記區塊讓下次重跑只更新自家內容。
  5. **三種 placement** 涵蓋常見配置：新建集中面板 / 每 repo 既有 panel 加按鈕 / 全域 toolbar。
- 兩檔正規化為 CRLF。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`，remote `origin` = github.com/gsinvest017-ai/gs-claude-config.git。
- 本任務**只 commit 到本機 `main`，不 push**。
- Rollback：`git -C C:\Users\User\gs-claude-config log --oneline` 找 `Mn:` commit，`git reset --hard <hash>` 回退。
- 整個撤掉：刪 `skills/copy-commits-button/`、本進度檔，再 `git checkout -- .`。
- 新 skill 通常即時出現在 available-skills 清單；若沒有，開新的 Claude Code session 即可。
