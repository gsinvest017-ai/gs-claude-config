# /update-doc Skill 建立 + 首次執行進度

## 目標

建立全域 `/update-doc` slash command skill，功能為：掃描當前 repo 的 README、所有 skills/commands、設定檔、git log，產生或更新 `docs/index.html`（GS dark gold theme，standalone，無外部依賴）。並在 gs-claude-config 上首次執行，產出實際的 `docs/index.html`。

## 計畫 Milestone

| # | 標題 | 預期產出 |
|---|------|---------|
| M1 | Skill 檔案建立 | `skills/update-doc/SKILL.md` + `commands/update-doc.md` |
| M2 | 掃描 repo 內容 | 整理出 skills 清單、commands 清單、README 摘要、近期 commits |
| M3 | 產出 docs/index.html | GS gold theme HTML，含 Skills 一覽、安裝說明、近期 commits；commit 所有 |

## 進度日誌

<!-- M1 以下追加 -->

## Fallback 指引

- rollback M1: `git revert HEAD` 可移除 SKILL.md + commands/update-doc.md
- rollback M3: `git revert HEAD` 移除 docs/index.html
- 手動測試 skill: 在任意 repo 新 session 輸入 `/update-doc --apply`
