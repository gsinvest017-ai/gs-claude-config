# Night-Shift Cron — 變更總覽 + 設定步驟

> 給日後新機器設定、或想了解整套機制如何運作的快速參考。
> 詳細工作日誌請看 [`progress-night-shift-cron.md`](./progress-night-shift-cron.md)。
> README 的 [Night Shift 段落](../README.md#night-shift--unattended-safe-yolo-via-cron) 是面向使用者的完整使用說明（含 env vars 表、disable、safety notes）。

---

## 一句話講清楚

把這個 repo 已經提供的 `~/.claude/` 全域配置 + 新加的 `scripts/`，組合成一條 user-level cron job：
**00:00 自動對 `targets.conf` 列的每個 repo 開 `claude/nightly-<DATE>` 分支跑 `/safe-yolo`，06:00 hard kill**。
不 push、不開 PR、不送訊息，所有 log 寫 `~/.claude/night-shift-logs/`。

---

## 新增 / 變更的檔案

| 路徑 | 類型 | 角色 |
|------|------|------|
| `scripts/night-shift.sh` | 新增 (exec) | **Per-repo 執行器**。負責 git 安全檢查（拒 dirty tree）、開 `claude/nightly-YYYY-MM-DD` 分支、收集 prompt 來源（TODO/refactor/issue/progress 文件，或 `gh issue list` fallback）、用 stdin 把 `/safe-yolo <prompt>` 餵給 `claude -p --dangerously-skip-permissions`，寫 log 到 `~/.claude/night-shift-logs/<repo>-<ts>.log`。支援 `DRY_RUN=1`。 |
| `scripts/night-shift-runner.sh` | 新增 (exec) | **Cron 進入點 / dispatcher**。讀 `scripts/targets.conf` 解析每行（支援 `path` 或 `path\|prompt-file`、`#` 註解），用 deadline epoch 動態分配 per-repo 預算（剩餘秒數 − 60s，上限 2h），不存在的 path skip 不中斷。`exit 124` 視為正常 timeout。 |
| `scripts/install-cron.sh` | 新增 (exec) | 把一個 marker-fenced block 寫進 user crontab：`0 0 * * * NIGHT_SHIFT_WINDOW_HOURS=6 timeout … 6h <runner>`。Idempotent：用 `>>> gs-claude-config night-shift <<<` / `<<< … >>>` 標記，重跑會替換不會疊加。自動帶入 `$HOME/.local/bin` 與最新 nvm node 到 PATH（解決 cron 預設 PATH 找不到 `claude` 與 node 的問題）。可用 `NIGHT_SHIFT_START_HOUR` / `NIGHT_SHIFT_WINDOW_HOURS` 覆寫。 |
| `scripts/uninstall-cron.sh` | 新增 (exec) | 依同一組 marker 把 block awk 掉，idempotent。 |
| `scripts/targets.conf.example` | 新增 | 給新機器抄的範本（comment-only）。 |
| `scripts/targets.conf` | 新增 (gitignored) | **每台機器各自維護**，已在 `.gitignore` 排除。 |
| `.gitignore` | 修改 | 加 `scripts/targets.conf`。 |
| `README.md` | 修改 | 新增 `## Night Shift` 章節，含完整 setup / customizing / disabling / safety notes / WSL2 caveat。 |
| `install.sh` | 修改 | 結尾加 4 行可選提示，指向 `scripts/install-cron.sh`。不強制裝。 |
| `docs/progress-night-shift-cron.md` | 新增 | `/safe-yolo` 兩輪工作日誌（M1–M9）。 |
| `docs/night-shift-setup.md` | 新增 | 本檔。 |

執行檔權限：`scripts/*.sh` 都已 `chmod +x`。

---

## 流程一覽

```
                         ┌──────────────────────────────────────┐
   crontab 0 0 * * * ──▶│ timeout 6h night-shift-runner.sh     │
                         └────────────────┬─────────────────────┘
                                          │ 讀 targets.conf
                                          ▼
              ┌────────────────────────────────────────────────┐
              │ for each repo in targets.conf (有預算就繼續):    │
              │   night-shift.sh <repo> [<prompt-file>]        │
              │     1. 拒 dirty working tree                    │
              │     2. git checkout -b claude/nightly-<DATE>    │
              │     3. 蒐集 prompt (自動掃 or 顯式指定)          │
              │     4. echo prompt | timeout 2h claude -p …    │
              │     5. 沒新 commit 就刪空分支                    │
              │     6. log to ~/.claude/night-shift-logs/      │
              └────────────────────────────────────────────────┘
                                          │
                                          ▼
                              06:00 timeout → SIGTERM → 30s 後 SIGKILL
```

關鍵設計取捨：

- **不 pull、不 push**：cron 不需要碰 remote/auth，所有產出留在本機分支等使用者 review
- **每個 milestone commit 一次**（由 `/safe-yolo` skill 本身強制）：6h 中斷也不會丟掉中間進度
- **per-repo budget 動態算**：`min(剩餘秒數 − 60, 7200)`，單一 repo 卡死不會吃掉整夜
- **dirty tree skip 不 stash**：絕不動使用者未 commit 的工作

---

## 在新機器設定（完整步驟）

### 0. 前置條件

- Linux / WSL2（Mac 沒驗證過，cron daemon 那段要改 `launchd`）
- Claude Code CLI 已安裝且 `command -v claude` 找得到（通常在 `~/.local/bin/claude`）
- WSL2 上 `service cron status` 應為 `active`；若不是：
  ```bash
  sudo service cron start
  # 確保開機自啟動：
  sudo sh -c 'echo -e "[boot]\nsystemd=true" >> /etc/wsl.conf'   # 若沒有
  # 然後在 PowerShell 跑：wsl --shutdown，下次開 WSL 就會自動拉起
  ```

### 1. Clone + 全域配置

```bash
git clone https://github.com/gsinvest017-ai/gs-claude-config.git ~/gs-claude-config
cd ~/gs-claude-config
./install.sh
```

`install.sh` 會：
- symlink `commands/`、`skills/`、`CLAUDE.md` 進 `~/.claude/`
- 若 `~/.claude/settings.json` 不存在，從 `settings.template.json` 渲染一份
- 若 `~/quant-research-skill` 不存在，自動 clone（部分 skill 是相對 symlink 過去）

### 2. 寫 `targets.conf`

```bash
cp scripts/targets.conf.example scripts/targets.conf
$EDITOR scripts/targets.conf
```

每行一個 repo 絕對路徑。挑選原則：

1. **近期有活動**：`git -C <repo> log -1 --format='%cr'` 在一週內最佳
2. **有可吃的 prompt 文件**（auto-discover 範圍）：
   - `TODO.md`（top-level）
   - `docs/TODO.md` / `docs/todo.md`
   - `docs/refactor*.md` / `docs/REFACTOR*.md`
   - `docs/issue*.md` / `docs/ISSUE*.md`
   - `docs/progress-*.md`
3. 若 prompt 文件在自動範圍外，加 `|<path>` 顯式指定，例如：
   ```
   /home/me/tutorial|future-option-rule/docs/progress-tailscale-sharing.md
   ```
4. 若都沒有，`gh issue list` 會被當 fallback 來源（需 `gh auth login`）

範例（本機 2026-05-12 的設定）：

```
/home/kevin/gs-strategy
/home/kevin/autogo
/home/kevin/TQuant-Lab
```

### 3. 跑 DRY_RUN 驗一遍

不會真的呼叫 claude，但會把 prompt 組好印出來、確認每個 target 都解析正常：

```bash
DRY_RUN=1 NIGHT_SHIFT_WINDOW_HOURS=6 ./scripts/night-shift-runner.sh 2>&1 | tail -30
```

預期看到 `summary: total=N processed=N skipped_budget=0 overall_rc=0`。

> ⚠️ 早期版本的 `night-shift.sh` DRY_RUN 會留下空分支；commit `e5d22b9` 之後已修，DRY_RUN 跑完自己會 `git checkout -` + 刪空分支。

### 4. 安裝 cron

```bash
./scripts/install-cron.sh
crontab -l                 # 確認 >>> gs-claude-config night-shift <<< block 存在
```

預設 00:00 啟動、6h 窗口。要改：

```bash
# 23:00 啟動、7h 窗口
NIGHT_SHIFT_START_HOUR=23 NIGHT_SHIFT_WINDOW_HOURS=7 ./scripts/install-cron.sh
```

### 5. 隔天早上 review

```bash
# 看 dispatcher 總覽
ls -lt ~/.claude/night-shift-logs/_runner-*.log | head -3
cat ~/.claude/night-shift-logs/_runner-$(date +%Y-%m-%d)*.log | tail -50

# 看每個 repo 開的夜班分支
for d in $(grep -v '^#' ~/gs-claude-config/scripts/targets.conf | cut -d'|' -f1); do
    echo "=== $d ==="
    git -C "$d" log --oneline -10 claude/nightly-* 2>/dev/null
done
```

滿意的 commit 自己 `git cherry-pick` 或 `git merge claude/nightly-YYYY-MM-DD` 進主分支。
不要的就 `git branch -D claude/nightly-YYYY-MM-DD` 丟掉。

---

## 停用 / 故障排除

### 暫時停掉今晚

把 `scripts/targets.conf` 整個註解掉。Cron 仍會 fire 但 runner 立刻 exit。

### 永久停用

```bash
./scripts/uninstall-cron.sh
```

### Cron 沒 fire（最常見 WSL2 問題）

```bash
service cron status        # 應為 active
# 若不是，且重開機後也不會自動：檢查 /etc/wsl.conf 是否有 [boot] systemd=true
cat /etc/wsl.conf
journalctl -u cron --since today | tail   # systemd 環境下看 cron daemon log
```

### Claude binary 找不到（log 顯示 `command not found: claude`）

`install-cron.sh` 寫入的 `PATH=` 行只在 install 當下偵測一次。換 node 版本或裝路徑後重跑：

```bash
./scripts/install-cron.sh   # 會覆蓋舊 block，重新偵測 PATH
```

### 想清掉所有夜班開過的分支

```bash
for d in $(grep -v '^#' ~/gs-claude-config/scripts/targets.conf | cut -d'|' -f1); do
    git -C "$d" branch --list 'claude/nightly-*' | xargs -r -n1 git -C "$d" branch -D
done
```

---

## 安全提醒

- **`--dangerously-skip-permissions` 是開的**：夜班內 claude 可以無提示執行任何工具。`--add-dir <repo>` 限制檔案系統存取在該 repo 內，dirty tree check 防止覆寫工作中變更。
- **不會 push、不會發 PR、不會送訊息**：所有產出都是本機分支，最壞情況早上一堆垃圾本機分支 `git branch -D` 即可。
- **訂閱配額**：每晚會吃 Claude Pro/Max 配額。3 個 target × 6h 通常會撞 5h rolling rate limit，per-repo `timeout` cap 會吸收這個情況。
- **WSL2 cron daemon 不會自動 enable**：本指南假設你已經設好 `systemd=true`；否則重開機後 cron 不會跑。
