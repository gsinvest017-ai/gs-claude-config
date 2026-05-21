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

### M1 — progress 骨架（in progress）

建立本進度檔。下一步：撰寫 agent 定義。

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
