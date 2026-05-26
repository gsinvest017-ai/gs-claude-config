---
description: 程式語言家教 — 分析 repo 抽出該語言特有語法 / 機制 / idiom，建知識銀行，定期 Windows 彈窗抽考。用法：/prog-lang-tutor [analyze|review|schedule|unschedule|list|inspect] [repo-path|slug] [interval]
---

# /prog-lang-tutor — 程式語言家教

啟動程式語言家教 skill，依 `~/.claude/skills/prog-lang-tutor/SKILL.md` 完整 SOP 執行。

**使用者輸入**：$ARGUMENTS

---

## 執行步驟

### Step 1：解析 $ARGUMENTS

`$ARGUMENTS` 可能是空字串或多個 token。容許的詞：

- **mode**：`analyze` / `review` / `schedule` / `unschedule` / `list` / `inspect`
- **repo**：絕對路徑（`C:\...` 或 `/c/...`）或 `data/` 底下已存在的 slug
- **interval**（僅 schedule 用）：`15m` / `30m` / `1h` / `2h` / `4h`
- **flag**：`--force`（覆寫已存在的 knowledge.json）

順序不限。例：
- `/prog-lang-tutor` → 預設 analyze 當前 cwd
- `/prog-lang-tutor analyze C:\Users\User\autogo`
- `/prog-lang-tutor schedule 30m autogo`
- `/prog-lang-tutor review autogo`
- `/prog-lang-tutor list`
- `/prog-lang-tutor unschedule autogo`

未指定 mode → 預設 `analyze`、target 為當前 cwd。

### Step 2：載入 SKILL.md

完整讀取 `C:\Users\User\.claude\skills\prog-lang-tutor\SKILL.md`，依 Phase 0 路由到對應 sub-mode（analyze / review / schedule / unschedule / list / inspect）。

### Step 3：執行 PowerShell helper（必要時）

SKILL.md 的 Phase 1 / 3 會呼叫：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\save-knowledge.ps1" -RepoPath <...> -Language <...> -KnowledgeJsonPath <...>
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\schedule-review.ps1" -RepoSlug <slug> -IntervalMinutes <N>
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\unschedule-review.ps1" [-RepoSlug <slug>]
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\popup-review.ps1" -RepoSlug <slug>
```

用 Bash tool 或 PowerShell tool 呼叫；失敗時印出 stderr 並停下來問使用者。

### Step 4：Session 結束

`analyze` 結束 → 主動建議 `/prog-lang-tutor schedule 30m <slug>` 開啟複習。
`review` 結束 → 印摘要、最弱類別、建議下次重點。

---

## 注意事項

- 不要靠記憶判斷 repo 路徑是否存在；先 `Test-Path` 或 `ls`。
- 不要分析 generated code、vendor、node_modules。
- popup 視窗在 Claude Code session 之外彈出（由 Windows Task Scheduler 觸發），是純 PowerShell WPF；使用者答題在那邊不會回到 Claude session（除非他 copy 知識點過來叫 `/prog-lang-tutor review`）。
- 排程間隔最短 15 分鐘，避免被噴。
