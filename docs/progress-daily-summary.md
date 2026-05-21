# progress — /daily-summary slash command

## 目標

新增一個 `/daily-summary` slash command（搭配 subagent 定義），讓使用者在任何 git repo 路徑底下執行後，會：

1. 抓出**當天**（local TZ）所有 git commits（含 merge 與 amend 後的最新狀態）
2. 讀取每個 commit 的 message、變更檔案、必要時的 diff
3. 彙整成一份 **繁體中文** Markdown summary，檔名 `YYYY-MM-DD-summary.md`
4. 預設存到當前 repo 根目錄（若有 `docs/daily-summary/` 則放那）

目標是讓使用者每天下班前一鍵生成可貼到日報、週報、Obsidian 的 changelog。

## 計畫 milestone

| M | 標題 | 預期產出 |
|---|------|----------|
| M1 | progress 骨架 | `docs/progress-daily-summary.md`（本檔） |
| M2 | agent 定義 | `agents/daily-summary.md`（subagent，model=sonnet） |
| M3 | slash command + skill | `commands/daily-summary.md`、`skills/daily-summary/SKILL.md` |
| M4 | 整合驗證 + README | 補 README 條目；smoke-test 在 `gs-claude-config` 自身跑一次 |

## 進度日誌

### M1 — progress 骨架 ✅

建立本進度檔。Commit: `b3455b3`。

### M2 — agent 定義 ✅

寫 `agents/daily-summary.md`：

- model: sonnet（彙整工作不需要 opus）
- tools: Read / Write / Edit / Bash / Glob / Grep
- 流程：`git log --since=today` → 收 stat → 分類（feat / fix / refactor / docs / chore / safe-yolo `Mn:`）→ 寫 `YYYY-MM-DD-summary.md`
- 邊界：未 commit 變更會在報告開頭警告；支援指定日期 / 指定 repo path；不會主動 push 或建 PR
- 與 `/save-to-obsidian`、`/safe-yolo` 的協作說明寫在檔尾

下一步：M3 — slash command + skill 檔。

### M3 — slash command + skill ✅

- `commands/daily-summary.md`：slim entry，列觸發範例與精簡流程
- `skills/daily-summary/SKILL.md`：完整規範，含參數解析、CRLF 已套用
- 已驗證 skill 被 Claude Code 偵測到（system-reminder 列出 daily-summary skill）

下一步：M4 — README 連結 + smoke test。

### M4 — README 連結 + smoke test ✅

- README 的「What's in here」目錄樹加入 `daily-summary.md`、新增 `agents/` 區塊
- Smoke test：在本 repo 跑 `git log --since="2026-05-21 00:00" --until="2026-05-21 23:59"`，回傳 M1/M2/M3 三個 commits → 確認 git 查詢語法在 Git Bash 下正確
- Skill 被 Claude Code 偵測（system-reminder 自動載入 `daily-summary` skill）
- 後續：M4 commit 本身會出現在 `2026-05-21-summary.md` 裡，讓使用者第一次跑 `/daily-summary` 就能看到完整鏈

## 完成總結

- 4 commits（M1 ~ M4）建立 `/daily-summary` slash command
- 觸發後抓今日 commits → 分類 → 寫 `YYYY-MM-DD-summary.md`（繁體中文）
- 不會 push、不會修改原始碼，純彙整工具
- 與 `/safe-yolo`、`/save-to-obsidian` 串接：safe-yolo 的 `Mn:` 自動歸群組；可一鍵把 summary 匯入 Obsidian

## Fallback 指引

若中途要 rollback：

```bash
git log --oneline --grep='daily-summary'
git revert <commit-hash>   # 或 git reset --hard <pre-task-hash>
```

最少需要的檔案清單（全部都在 `gs-claude-config` repo 內）：

- `agents/daily-summary.md`
- `commands/daily-summary.md`
- `skills/daily-summary/SKILL.md`
- `docs/progress-daily-summary.md`
- `README.md`（若有更新 command 清單）

刪掉以上四個檔即可完全回退此功能；chezmoi-managed symlink 不需動。
