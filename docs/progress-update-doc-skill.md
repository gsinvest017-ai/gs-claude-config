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

## M1 — Skill 檔案建立

- `skills/update-doc/SKILL.md` 建立（框架偵測 → repo 掃描 → GS dark gold HTML 規則完整定義）
- `commands/update-doc.md` 建立（slim slash command 入口）
- commit: `7ec6112`

## M2 — 掃描 gs-claude-config repo 內容

- README.md 全文讀取（overview、chezmoi 安裝流程、目錄結構、day-to-day workflow）
- 22 skills frontmatter 全部萃取（name + description）
- 16 commands description 全部萃取
- git log --oneline -20 取得（最近 20 commits）

## M3 — 產出 docs/index.html

- 產出 `docs/index.html`（GS dark gold theme，standalone，無外部 CDN）
- 內容：Overview、Installation（chezmoi + install script 兩路徑）、Architecture（目錄樹 + symlink 表）、Skills grid（22 cards）、Commands 表（16 rows）、Changelog（20 commits）
- Active nav highlight（IntersectionObserver JS）
- commit: 本次

## Fallback 指引

- rollback M1: `git revert HEAD` 可移除 SKILL.md + commands/update-doc.md
- rollback M3: `git revert HEAD` 移除 docs/index.html
- 手動測試 skill: 在任意 repo 新 session 輸入 `/update-doc --apply`
