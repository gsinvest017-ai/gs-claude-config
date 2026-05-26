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

### M1 — Skeleton + slim entry

- 建立 `skills/prog-lang-tutor/SKILL.md`（六種 sub-mode：analyze / review / schedule / unschedule / list / inspect；含 per-language 知識點 taxonomy）
- 建立 `commands/prog-lang-tutor.md` slim entry，args 容許 mode / repo / interval / `--force`
- 建立 `docs/progress-prog-lang-tutor.md`
- 因 `gs-claude-config/skills/` 已 symlink 到 `~/.claude/skills/`，新增即全域可用，下次 session 啟動時 `/prog-lang-tutor` 直接出現在 skills list
- Commit: `d698ff3`

### M2 — Persistence helper

- 寫 `scripts/save-knowledge.ps1`：
  - `-RepoPath` 自動 derive slug（leaf, lowercase, spaces→`_`）
  - 驗證輸入 JSON 有 `knowledge_points` array 才寫
  - Stamp `repo_path` / `repo_slug` / `language` / `analyzed_at` (ISO 8601 UTC)
  - 預設不覆寫；要覆寫加 `-Force`
  - 輸出 UTF-8 no-BOM 到 `data/<slug>/knowledge.json`
- Commit: `d3cc8e1`

### M3 — Popup + scheduler

- `scripts/popup-review.ps1`：
  - WinForms 視窗：topic header + question label + monospace code box + answer box（隱藏直到「Show Answer」）
  - 三個按鈕：Show Answer / Got it / Skip
  - 挑題策略：oldest `last_reviewed` → 最少 `reviewed_count` → random
  - Skip 或從未按 Show Answer → 不更新 reviewed_count（避免「按 X 關掉」也計入）
  - `-DryRun` 純 headless：印選到的知識點 metadata、不開 UI
- `scripts/schedule-review.ps1`：
  - 用 `Register-ScheduledTask` (modern API)；避開 `schtasks.exe` 的 quoting 地獄
  - Trigger：`-Once -At now+1m -RepetitionInterval N min -RepetitionDuration 365d`
  - Principal：`LogonType=Interactive`、`RunLevel=Limited`（不需 admin、popup 會跑在使用者 desktop）
  - Settings：`AllowStartIfOnBatteries`、`MultipleInstances=IgnoreNew`、`ExecutionTimeLimit=10m`
  - 守則：`IntervalMinutes < 15` 直接拒絕（防擾人）；> 1439 也拒
- `scripts/unschedule-review.ps1`：傳 `-RepoSlug` 移除單一；不傳則清掉所有 `ClaudeCode-ProgLangTutor-Review-*`
- 四個 script 全 `Parser::ParseFile` 通過
- Commit: `a7e24ac`

### M4 — Smoke test + docs

- 手寫 4 點 PowerShell 知識銀行（splatting / `[CmdletBinding()]` / `$ErrorActionPreference='Stop'` / here-string）放到 `$env:TEMP\smoke-knowledge.json`
- `save-knowledge.ps1` 跑成功 → 寫入 `data/gs-claude-config/knowledge.json`，4 points 正確 stamp
- `popup-review.ps1 -DryRun` 跑成功 → 挑出 `ps-cmdletbinding-001`（4 points 都同分 last_reviewed=null、reviewed_count=0，random tiebreaker）
- `schedule-review.ps1` 跑成功 → Task 進 `Ready` state、`LogonType=Interactive`、Next run = +1m
- `unschedule-review.ps1` 立刻清掉 task（避免真的彈窗打擾使用者）
- 加 `data/.gitignore`：runtime knowledge bank 不入版控，只保留 `.gitignore` 與 `README.md`
- 加 `data/README.md`：schema 文件 + 手動編輯指引 + 刪除指令範例

## 最終狀態

```
skills/prog-lang-tutor/
├── SKILL.md
├── scripts/
│   ├── save-knowledge.ps1
│   ├── popup-review.ps1
│   ├── schedule-review.ps1
│   └── unschedule-review.ps1
└── data/
    ├── .gitignore   # runtime banks 不入版控
    └── README.md    # schema 文件

commands/prog-lang-tutor.md   # slim entry
```

使用方法（任何 repo 內）：

```bash
/prog-lang-tutor                          # 分析當前 cwd
/prog-lang-tutor analyze C:\path\to\repo
/prog-lang-tutor schedule 30m <slug>      # 每 30 min popup
/prog-lang-tutor review <slug>            # 在對話內抽考
/prog-lang-tutor unschedule <slug>
/prog-lang-tutor list
```

## Fallback 指引

若需要從某個 milestone rollback：
- M1 之後：`git revert <M1-commit>` 可移除整個 skill。
- M3 之後：若 Windows Task Scheduler 排程沒清掉，手動 `schtasks /Delete /TN "ClaudeCode-ProgLangTutor-Review" /F`。
- 若 popup 一直跳很煩：先跑 `~/.claude/skills/prog-lang-tutor/scripts/unschedule-review.ps1` 把所有排程清掉。

知識銀行存在 `~/.claude/skills/prog-lang-tutor/data/<repo-slug>/knowledge.json`，可直接編輯或刪除。
