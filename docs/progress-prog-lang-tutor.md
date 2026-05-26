# progress — /prog-lang-tutor

## 目標

打造一個全域可用的 Claude Code skill `/prog-lang-tutor`，提供：

1. **Repo 分析** — 掃描指定 repo，偵測主要程式語言，挖出該語言「重要 + 特有」的語法/機制（decorator、async/await、trait、generic、context manager、closure …），以及這個 repo 真實使用到的 idiom。
2. **知識銀行** — 每個 repo 一份 `knowledge.json`，存 N 個知識點（語法示例 + 出現位置 + 解釋 + 隨機抽考題）。
3. **定期彈出視窗複習** — 透過 Windows Task Scheduler + PowerShell `WPF MessageBox` 每隔使用者指定的時間（預設 30 min）彈出一個小視窗，隨機挑一個知識點考使用者，答完顯示解析。
4. **全域生效** — 透過 `gs-claude-config` 既有 symlink 機制（`skills/`、`commands/` → `~/.claude/`），install.ps1 跑過後立即可用。

## 計畫 milestone

| # | Title | 預期產出 |
|---|---|---|
| M1 | Skeleton + slim entry | `skills/prog-lang-tutor/SKILL.md`、`commands/prog-lang-tutor.md`、`docs/progress-prog-lang-tutor.md` |
| M2 | 分析 pipeline | SKILL.md 內含完整四階段分析 SOP；定義 `knowledge.json` schema；`scripts/save-knowledge.ps1` helper |
| M3 | 彈窗 + 排程 | `scripts/popup-review.ps1`、`scripts/schedule-review.ps1`、`scripts/unschedule-review.ps1`；Windows Task Scheduler 整合 |
| M4 | Smoke test + docs | 在 `gs-claude-config` 自己跑一次分析、產生 `knowledge.json`、手動觸發 popup 確認可彈出；更新 `CLAUDE.md` 索引 |

## 進度日誌

（每完成一個 milestone 追加 `## Mn — <title>` 段落）

## Fallback 指引

若需要從某個 milestone rollback：
- M1 之後：`git revert <M1-commit>` 可移除整個 skill。
- M3 之後：若 Windows Task Scheduler 排程沒清掉，手動 `schtasks /Delete /TN "ClaudeCode-ProgLangTutor-Review" /F`。
- 若 popup 一直跳很煩：先跑 `~/.claude/skills/prog-lang-tutor/scripts/unschedule-review.ps1` 把所有排程清掉。

知識銀行存在 `~/.claude/skills/prog-lang-tutor/data/<repo-slug>/knowledge.json`，可直接編輯或刪除。
