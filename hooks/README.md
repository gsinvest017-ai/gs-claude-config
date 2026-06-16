# hooks/

機器層級的 Claude Code hook 腳本。`~/.claude/hooks/` 在每台機器上是**實體目錄**（混有機器專屬腳本），所以本目錄的可攜 hook 由 `install.ps1` / `install.sh` **逐檔複製**進去，而不是整夾 symlink（避免蓋掉本機腳本）。

兩支 hook 一組（缺一不可）：
- **`autopilot-arm.{ps1,sh}`** — `UserPromptSubmit` hook（matcher `^/autopilot`）。負責用 stdin 的**真實 session_id** 建/刪旗標。
- **`autopilot-continue.{ps1,sh}`** — `Stop` hook。每次 Claude 想結束回合時把回合擋回去。

## autopilot-arm.ps1 / .sh — 武裝（建旗標）

在使用者送出 `/autopilot ...` prompt、模型看到之前先觸發：
- `/autopilot on <task>` → 用 stdin 的真實 `session_id` 建 `state.json`、清 `done`，回一段 additionalContext 提示模型「已武裝、立即開始、別自己建檔」。
- `/autopilot off` → 刪 `state.json`(+`done`)。
- `/autopilot status` → 不動狀態。

> **為什麼需要它**：skill（模型）拿不到自己的 session_id，只有 hook 的 stdin 有。早期讓 skill 寫 `session_id:""`、由 Stop hook「首觸綁定」的做法在多 session 並存時會 race（任何先結束回合的 session 會搶走旗標）。改由 arm hook 在 `on` 當下蓋上正確 session_id，race 根除。

## autopilot-continue.ps1 / .sh — 硬性不停執行

`/autopilot` 的 Stop hook。autopilot 啟用中就回 `{"decision":"block","reason":...}` 把回合擋回去、餵下一步指令，直到完成或達上限。詳見 `skills/autopilot/SKILL.md`。

### 控制狀態（`~/.claude/.autopilot/`）
- `state.json` — `{ session_id, iterations, max_iterations, started, task }`（由 arm hook 建立）
- `done` — 完成 sentinel；模型完成且驗證通過後 touch，hook 看到就放行並清狀態。

### 安全閥（防呆，依序）
1. `stop_hook_active == true` → 放行（尊重 Claude Code 內建連續-block cap，不打架）
2. 無 `state.json` → 放行（**預設關閉**）
3. `state.session_id` ≠ 當前 session → 放行（旗標只對武裝它的那個 session 生效，不劫持別人）
4. `done` 存在 → 清狀態、放行
5. `iterations >= max_iterations`(預設 50) → 清狀態、強制停（stderr 提示）
6. 否則 → `iterations++`、block + reason

### 為什麼要提高 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`
Claude Code 內建「連續 block 上限 8 次」硬煞車。要讓 autopilot 跑滿 50 次續跑，`settings.json` 的 `env` 已把上限提到 `60`（略高於 50 留 buffer）。此 env 全域生效但無害：唯一會 block 的 hook 是 autopilot，且被旗標檔 gate，未啟用時沒有任何 hook 會 block。

## 安裝 / 合併到 settings.json

`install.ps1` / `install.sh` 會複製本目錄的 autopilot hooks 到 `~/.claude/hooks/`，並在**全新**渲染 `settings.json` 時注入 UserPromptSubmit + Stop hook + env。

若 `settings.json` 已存在（不會被覆蓋），手動把以下併入既有設定（`UserPromptSubmit` / `Stop` 都是陣列、可多筆並存——直接 append，不必動既有 hook 如通知/標題/autogo）：

```jsonc
{
  "env": { "CLAUDE_CODE_STOP_HOOK_BLOCK_CAP": "60" },
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "^/autopilot", "hooks": [
        { "type": "command",
          // Windows:
          "command": "pwsh -NoProfile -NonInteractive -File \"C:\\Users\\<you>\\.claude\\hooks\\autopilot-arm.ps1\"",
          // Linux/WSL: "command": "/home/<you>/.claude/hooks/autopilot-arm.sh",
          "timeout": 10 } ] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command",
          // Windows:
          "command": "pwsh -NoProfile -NonInteractive -File \"C:\\Users\\<you>\\.claude\\hooks\\autopilot-continue.ps1\"",
          // Linux/WSL: "command": "/home/<you>/.claude/hooks/autopilot-continue.sh",
          "timeout": 30 } ] }
    ]
  }
}
```
> ⚠️ 兩個 hook 缺一不可：少了 `UserPromptSubmit` arm hook，`/autopilot on` 不會建旗標、autopilot 不會啟動（fail-closed）。

## autonomy 三件套
- `skills/safe-yolo` — 純 prompt 軟模式（模型自願不停）
- `skills/autopilot` + 本 hook — 互動 session 內**硬強制**不停
- `scripts/night-shift.sh` — headless 跨-session 迴圈（外層 `claude -p`）
