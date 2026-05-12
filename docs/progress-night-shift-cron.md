# Progress — Night-Shift Cron

> Branch: `feat/night-shift-cron`
> Started: 2026-05-12
> Driver: `/safe-yolo` — 不停下來確認方向

## 目標

讓使用者在 `gs-claude-config` 加入一組腳本與設定，使得任何一台 PC 只要 `git clone gs-claude-config && ./install.sh`，就能：

1. 透過系統 `cron` 在 00:00 自動啟動 Claude Code
2. 針對 `targets.conf` 列出的多個 repo，逐一進入該 repo
3. 在新開的 `claude/nightly-YYYY-MM-DD` 分支上，根據該 repo 的 TODO / refactor plan / issue report 文件，自動跑 `/safe-yolo` loop
4. 06:00 自動 hard-stop（無人值守時段結束）
5. 全程的 stdout/stderr 寫入 `~/.claude/night-shift-logs/<repo>-<date>.log`，並做基本 rotation

跨機器遷移時，只需要在新機器編輯 `~/gs-claude-config/scripts/targets.conf`（gitignored 的本機檔案）填入要被夜跑的 repo 路徑，再執行 `scripts/install-cron.sh` 即可。

## 計畫 Milestone

- **M1** — 建立分支、進度檔、scripts/docs 目錄、targets.conf.example。產出：本檔 + `.gitignore` 更新 + `targets.conf.example`。
- **M2** — `scripts/night-shift.sh`：per-repo 執行器。負責 git 操作（pull/開分支）、收集 prompt 來源（TODO/refactor/issue 檔）、呼叫 `claude -p --dangerously-skip-permissions` 跑 `/safe-yolo`、寫入 log。
- **M3** — `scripts/night-shift-runner.sh`：cron 入口。讀 `targets.conf`、依序對每個 repo 呼叫 `night-shift.sh`，套用 6 小時總預算（`timeout 6h`）。`scripts/install-cron.sh` + `scripts/uninstall-cron.sh`：寫入/移除 user crontab。
- **M4** — 整合 `install.sh`（安裝主流程提示有 night-shift 可選裝）+ 更新 `README.md`（新增「Night Shift」段落，解說設定、log 位置、停用方式、安全注意事項）。
- **M5** — Smoke test：`bash -n` syntax check、`shellcheck` 若有、DRY_RUN 模式跑一次驗證流程不會炸；最後 merge 回 main。

## 進度日誌

### M1 — Scaffolding（done, commit 5ecbf35）

開了 `feat/night-shift-cron` 分支，建立 `scripts/`、`docs/` 目錄、`scripts/targets.conf.example`，並把 `scripts/targets.conf` 加進 `.gitignore`。

### M2 — `scripts/night-shift.sh`（done）

Per-repo runner。重點設計：

- **安全網**：拒絕在 dirty working tree 上跑、要求是 git repo、找不到任何 prompt source 時自動退出並刪掉空分支
- **分支策略**：`claude/nightly-YYYY-MM-DD`，當天若已存在則 fallback 為 `claude/nightly-YYYY-MM-DD-HHMMSS`
- **Prompt 來源**：(a) `targets.conf` 內以 `|<file>` 顯式指定，(b) 否則自動掃 `TODO.md` / `docs/TODO.md` / `docs/refactor*.md` / `docs/issue*.md` / `docs/progress-*.md`（最多 8 個檔案，每檔 head 400 行），(c) 最後 fallback 用 `gh issue list` 抓 20 條 open issue
- **Claude 呼叫**：`timeout 2h`（per-repo，可用 `NIGHT_SHIFT_PER_REPO_TIMEOUT` 覆寫）+ `claude -p --dangerously-skip-permissions --permission-mode bypassPermissions --add-dir <repo> --model opus`，prompt 走 stdin（避免 shell quoting）
- **Log**：每次 invocation 一份 `~/.claude/night-shift-logs/<repo>-<YYYY-MM-DD-HHMMSS>.log`；script 一開頭就 `exec > >(tee -a "$LOG_FILE") 2>&1` 把所有輸出 mirror 過去
- **DRY_RUN**：`DRY_RUN=1` 會印出 prompt + 預定命令但不真的呼叫 claude

`bash -n` 語法檢查通過。下一步：M3 dispatcher + cron 安裝/解除腳本。

### M3 — Dispatcher + cron install/uninstall（done）

- `scripts/night-shift-runner.sh`：cron 進入點。讀 `targets.conf` 解析每行（支援 `path|prompt-file`、`#` 註解、空白行），用 `deadline_epoch` 自我計時：每次迭代前算剩餘秒數，<120s 就跳過剩下的 repo。Per-repo timeout 動態取「剩餘 - 60s」與 7200s 之較小者，確保單一 repo 不會吃掉整個窗口。Runner 自己的 log 寫到 `~/.claude/night-shift-logs/_runner-<ts>.log`。Exit code 忽略 124（GNU timeout 觸發）視為正常。
- `scripts/install-cron.sh`：在 user crontab 用 `>>> gs-claude-config night-shift <<<` 標記區塊 splice 進去，重跑會替換不會重複。設 `PATH` 包含 `$HOME/.local/bin`（claude 在那裡）+ 若偵測到 nvm 加上最新 node。cron 行格式：`0 0 * * * NIGHT_SHIFT_WINDOW_HOURS=6 timeout --signal=TERM --kill-after=120s 6h <runner>`，雙保險 hard kill。
- `scripts/uninstall-cron.sh`：依同一組 marker 把 block awk 掉，idempotent。

`NIGHT_SHIFT_START_HOUR` / `NIGHT_SHIFT_WINDOW_HOURS` 兩個 env var 可在 install 階段覆寫起始時間與窗口長度。

下一步：M4 串到 README + install.sh。

### M4 — README + install.sh hint（done）

- README 加入完整 `## Night Shift` 區段：what it is / setup（3 步驟）/ what happens each night / logs / customizing（env var 表 + 範例）/ disabling / safety notes（含 WSL2 cron 啟動提醒）/ migration
- 同時更新 repo 結構樹，把 `scripts/` 與 `docs/` 列入
- `install.sh` 結尾加 4 行 hint 指向 `scripts/install-cron.sh`，不強制裝（純可選）

下一步：M5 smoke test。

### M5 — Smoke test + final（done）

**1. `bash -n` 全部 4 個 shell 檔通過。** shellcheck 系統沒裝，跳過。

**2. `night-shift.sh` DRY_RUN 測試：** 在 `/tmp/night-shift-smoke-*` 建一個 git repo + TODO.md，跑 `DRY_RUN=1 ./scripts/night-shift.sh <repo>`：
- 分支 `claude/nightly-2026-05-12` 正確建立
- Prompt 組裝為 25 行 / 1294 bytes，正確以 `/safe-yolo` 開頭，把 TODO.md 內容嵌進「任務來源」區塊
- 預計命令印出：`timeout --signal=TERM --kill-after=30s 2h /home/kevin/.local/bin/claude -p --dangerously-skip-permissions --permission-mode bypassPermissions --add-dir <repo> --model opus --output-format text`
- DRY_RUN 路徑短路，未呼叫 claude
- Log 寫入 `~/.claude/night-shift-logs/<basename>-<ts>.log`

**3. `night-shift-runner.sh` DRY_RUN 測試：** 寫一個 `scripts/targets.conf` 列 3 個 target（2 個 tmp 有效 repo + 1 個 `/tmp/does-not-exist`），其中第二個用 `|TODO.md` 顯式指定 prompt 檔。`DRY_RUN=1 NIGHT_SHIFT_WINDOW_HOURS=1 ./scripts/night-shift-runner.sh`：
- targets.conf 正確解析（3 條，包含註解略過、`|` 切分）
- Per-repo 預算動態算出 3540s（= 3600 - 60）
- 不存在的 path 走 `skip` 路徑，不中斷整體流程
- Summary：`total=3 processed=2 skipped_budget=0 overall_rc=0`
- targets.conf 因 .gitignore 不會被 commit，測試結束 `git status` 乾淨

**4. install-cron.sh 沒有實際在這台機器執行**（避免污染本機 crontab）。其 awk splice 邏輯與 uninstall-cron.sh 對稱，idempotent 性質靠 marker block 保證；如果出問題重跑會替換、不會疊。

### 已知留待後續處理（不影響本 PR）

- WSL2 上 cron daemon 預設不會自動 enable，README 已提醒。
- Log rotation 沒做，README 給了 `find -mtime +14 -delete` 範例讓使用者自行排程。
- 沒有失敗 retry / 通知整合（Slack / email），目前都靠看 log。

### 完成清單

| 檔案 | 狀態 |
|------|------|
| `scripts/night-shift.sh` | ✅ |
| `scripts/night-shift-runner.sh` | ✅ |
| `scripts/install-cron.sh` | ✅ |
| `scripts/uninstall-cron.sh` | ✅ |
| `scripts/targets.conf.example` | ✅ |
| `.gitignore`（排除 `scripts/targets.conf`） | ✅ |
| `README.md` Night Shift 區段 | ✅ |
| `install.sh` 可選提示 | ✅ |
| 本進度檔 | ✅ |

下一步（人類動作）：
1. 在這台機器：`cp scripts/targets.conf.example scripts/targets.conf` → 填要被夜跑的 repo → `scripts/install-cron.sh`
2. 在新機器：`git clone` + `install.sh` + 同上 2 步即可
3. 視需要 push `feat/night-shift-cron` 到 origin 並合進 main（不在這個 yolo run 範圍）
