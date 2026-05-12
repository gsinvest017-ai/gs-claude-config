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

### M1 — Scaffolding（in progress）

開了 `feat/night-shift-cron` 分支，建立 `scripts/`、`docs/` 目錄。接下來補 `targets.conf.example` + `.gitignore`，commit 後進入 M2。
