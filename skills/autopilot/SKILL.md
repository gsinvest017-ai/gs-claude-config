---
name: autopilot
description: 硬性不停執行模式（hook 強制）。當使用者輸入 /autopilot on <任務>、說「全程不要停」、「連 yes/no 都不要問自己判斷」、「一路做到上線不要停下來」時啟動。透過 Stop hook 在每次回合結束時把 Claude 擋回去繼續做，直到任務完成（touch done sentinel）或達續跑上限。off / status 子指令管理開關。比 /safe-yolo 多一層 hook 層級的硬強制，不只是 prompt 約束。
---

# /autopilot — Stop-hook 硬性不停執行模式

`/autopilot` 是 `/safe-yolo` 的**硬強制版**。safe-yolo 靠 prompt 請模型不要停；autopilot 在 `~/.claude/settings.json` 的 Stop hook（`autopilot-continue.ps1` / `.sh`）每次回合結束時實際把回合擋回去，連使用者按 yes/no 的機會都不給，直到偵測到完成訊號或達上限。

控制狀態放在 `~/.claude/.autopilot/`：
- `state.json` — `{ session_id, iterations, max_iterations, started, task }`
- `done` — 完成 sentinel；**任務真的完成且驗證通過後才 touch**，hook 看到它就放行並清狀態。

## 子指令

### `/autopilot on <任務描述>`
1. 建立狀態目錄與旗標檔，`session_id` 先留空字串（hook 第一次觸發時會自動綁定當前 session）：

   **PowerShell（Windows）**
   ```powershell
   $d = "$env:USERPROFILE\.claude\.autopilot"
   New-Item -ItemType Directory -Force -Path $d | Out-Null
   Remove-Item "$d\done" -Force -ErrorAction SilentlyContinue
   @{ session_id=""; iterations=0; max_iterations=50; started=(Get-Date -Format o); task="<任務描述>" } |
     ConvertTo-Json -Compress | Set-Content "$d\state.json" -Encoding UTF8
   ```

   **Bash（WSL / Linux）**
   ```bash
   d="$HOME/.claude/.autopilot"; mkdir -p "$d"; rm -f "$d/done"
   printf '{"session_id":"","iterations":0,"max_iterations":50,"started":"%s","task":"%s"}' \
     "$(date -Iseconds)" "<任務描述>" > "$d/state.json"
   ```
2. 接著**立即開始執行任務**，全程套用下方「執行守則」。從這一刻起，每次你想結束回合都會被 hook 擋回來，所以**就當作不會停**，一路把任務推到完成。
3. 完成且測試/驗證通過後，**touch done sentinel** 再結束（見「如何收尾」）。

### `/autopilot off`
立刻中止：刪掉旗標檔。下一次回合結束就會正常停。
```powershell
Remove-Item "$env:USERPROFILE\.claude\.autopilot\state.json" -Force -ErrorAction SilentlyContinue   # Windows
```
```bash
rm -f "$HOME/.claude/.autopilot/state.json"   # WSL / Linux
```

### `/autopilot status`
印出旗標檔內容（目前第幾次 / 上限 / 任務），或回報「目前未啟用」。

## 執行守則（沿用 /safe-yolo）

1. **不要停下來問問題**。既然開了 autopilot，方向已授權。遇到分歧自行採用最合理的預設值繼續，把假設記進進度檔。**禁止使用 AskUserQuestion**，禁止用「要 A 還是 B？」結束回合。
2. **Milestone-based commit**：拆 2~5 個里程碑，每完成一個立刻 `git commit`（`Mn: <短描述>`，主體用繁體中文，subject ≤ 72 字）。
3. **進度 markdown**：在 `docs/progress-<task-slug>.md` 記錄目標、milestone、進度日誌（含 commit hash、決策）、fallback 指引；每個 milestone 更新並 commit。
4. **強制停下條件**（只有這些才停）：
   - 同一錯誤連續嘗試 3 次以上仍無解；
   - 操作不可逆且影響範圍超出 working directory（`git push --force`、刪 remote branch、發 PR、寄訊息等）；
   - 觸碰 `settings.json` 的 `permissions.deny` 範圍。
   碰到時先 commit 目前可工作狀態（標 WIP）、在進度檔記錄卡關點，**然後 `/autopilot off` 再停**（否則 hook 會把你擋回來）。

## 如何收尾（重要）

任務真的完成且測試/驗證通過後，**必須 touch done sentinel**，否則 hook 會一直把你擋回來直到撞上限：

```powershell
New-Item -ItemType File "$env:USERPROFILE\.claude\.autopilot\done" -Force | Out-Null   # Windows
```
```bash
touch "$HOME/.claude/.autopilot/done"   # WSL / Linux
```
然後用 3~5 行做最終報告（做了什麼、commit 範圍、進度檔位置、後續建議）即可結束。

## 安全機制（已內建於 hook，無需你處理）

- **預設關閉**：沒有 `state.json` 時 hook 一律放行，不影響其他 session。
- **session 綁定**：旗標只對啟用它的那個 session 生效，遺留旗標不會劫持別的 session。
- **續跑上限 50 次**：達上限自動強制停、清旗標，避免卡死任務無限燒 token。
- **與 Claude Code 內建 8-cap 協調**：hook 偵測 `stop_hook_active` 會讓步；settings 已把 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` 提高以容納 50 次續跑。

## 與其他模式的關係

- `/safe-yolo` — 純 prompt 軟模式（模型自願不停）。autopilot = safe-yolo + hook 硬強制。
- `scripts/night-shift.sh` — headless 跨-session 迴圈（外層 `claude -p`）。autopilot 管的是**互動 session 內**不停。
- 三者合起來＝完整 autonomy 三件套。

## 觸發範例

```
/autopilot on 把 strategies/ 接到 zipline-tej 期貨回測框架並跑通一次
/autopilot on 加 GitHub Actions CI 跑 pytest，綠燈為止
/autopilot status
/autopilot off
```
