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

### 回歸測試（改這兩支 hook 前後都要跑）

```powershell
pwsh ~\.claude\tests\autopilot-stress.ps1          # 全實作、完整 50 輪上限壓測
pwsh ~\.claude\tests\autopilot-stress.ps1 -Quick   # 5 輪快篩
```

`tests/autopilot-stress.ps1` 把真正的 hook 當子程序跑、餵合成 stdin payload，並把
`USERPROFILE`/`HOME` 指到 temp 沙盒，**不會動到跑測試那個 session 的 autopilot 狀態**。
同一份案例表跑 `ps1` / `sh` / `mjs` 三個實作以抓實作漂移（`.sh` 需 jq，缺了會報 SKIP）。

> **SOP**：改 repo → 跑 harness → 複製到 `~/.claude/hooks/`（install 是逐檔複製，不是
> symlink，不同步等於沒修）→ 再跑一次 harness。已知限制與踩過的坑見
> `docs/progress-autopilot-stress.md`。

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

## 全域啟用（讓所有 Claude session 都能用 autopilot）

`~/.claude/settings.json` 是 **user-scope 全域設定**，改它＝對所有專案／所有 session 生效。要真正「全程不停、連 yes/no 都不按」，需要**三層**都到位：

| 層 | 設定 | 作用 |
|---|---|---|
| 權限層 | `permissions.defaultMode = "bypassPermissions"` | 不再跳任何權限 yes/no |
| 武裝層 | `UserPromptSubmit` 註冊 `^/autopilot` → `autopilot-arm.ps1`/`.sh` | `/autopilot on` 用真實 session_id 建旗標 |
| 回合層 | `Stop` 註冊 `autopilot-continue.ps1`/`.sh` + `env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP = "60"` | 擋住回合結束、容納 50 次續跑 |

新機器最省事：`install.ps1` / `install.sh` 在**全新**渲染 settings.json 時會自動注入武裝層＋回合層（見上方佔位符）。**權限層 `defaultMode` 不會自動開**（安全考量），要全域免確認得自己加 `"defaultMode": "bypassPermissions"`。

既有 settings.json（不會被覆蓋）就照上一節的片段手動 append 三層；改完**重啟 Claude Code**（`defaultMode` 需重啟，hook 會熱載入）。驗證：
```powershell
(Get-Content $env:USERPROFILE\.claude\settings.json -Raw | ConvertFrom-Json).permissions.defaultMode   # -> bypassPermissions
```

> 🔐 `bypassPermissions` 全域＝所有 session 都能不經確認跑任意工具（含刪檔、push）。要縮回去就刪掉 `defaultMode` 那行，改用單發 `claude --dangerously-skip-permissions` 或 session 內 `Shift+Tab`。autopilot 本身預設關閉，只有 `/autopilot on` 的那個 session 會啟動。

## autonomy 三件套
- `skills/safe-yolo` — 純 prompt 軟模式（模型自願不停）
- `skills/autopilot` + 本 hook — 互動 session 內**硬強制**不停
- `scripts/night-shift.sh` — headless 跨-session 迴圈（外層 `claude -p`）

---

## kan-context.ps1 — 提到 ticket 編號就注入現況

搭配 `skills/kan`（Jira 看板 CLI）。使用者 prompt 裡出現 `KAN-123` 這種編號時，
即時查那幾張單的狀態／負責人／標題並注入 context，省掉「先查再答」的往返。
純唯讀，最多 5 張，查不到的 key 會明確列出（避免模型以為自己看漏）。

**這支不進 `settings.template.json`**（那份是 autopilot 專用、帶佔位符替換），
請手動 append 到 `~/.claude/settings.json` 的 `hooks.UserPromptSubmit` 陣列：

```json
{
  "matcher": "[Kk][Aa][Nn]-[0-9]+",
  "hooks": [
    {
      "type": "command",
      "command": "pwsh -NoProfile -NonInteractive -File \"C:\\Users\\User\\.claude\\hooks\\kan-context.ps1\"",
      "timeout": 10
    }
  ]
}
```

並把腳本複製過去（`~/.claude/hooks/` 是**實體目錄**，不像 `~/.claude/skills`
是指向本 repo 的 symlink，所以改完 repo 要再複製一次）：

```powershell
Copy-Item hooks\kan-context.ps1 "$HOME\.claude\hooks\" -Force
```

### 兩個設計重點

**守門在 `matcher` 不在腳本裡。** UserPromptSubmit 的每個項目是**獨立的**、各自
拿到完整 payload（不是把前一支的 stdout 當 stdin 串起來）。matcher 沒命中就不會
spawn pwsh，省下每次 prompt 約 340ms 的啟動成本；沒有這道守門，一支「大部分時候
立刻 exit」的 hook 仍然要付全額啟動代價。

**永遠 exit 0。** 沒裝 kan、憑證過期、Jira 掛掉，一律安靜跳過。hook 不該把
使用者的 prompt 擋下來。

### 驗證

```powershell
# 無編號 → 零輸出
'{"prompt":"今天天氣不錯"}' | pwsh -NoProfile -NonInteractive -File hooks\kan-context.ps1
# 有編號 → 回 hookSpecificOutput.additionalContext
'{"prompt":"KAN-443 怎樣"}' | pwsh -NoProfile -NonInteractive -File hooks\kan-context.ps1
```

## context-inject.ps1 / context-inject.sh — SessionStart 注入專案 context

把 `gs-harness` 預渲染好的跨 repo context 注入每個新 session（報告 B4 的
benevolent prompt injection）：workspace、最近驗證結果與其資料年紀、roadmap
翻紅預警、未完成 backlog、learnings 索引、artifact 到位狀況。

**這支腳本刻意什麼邏輯都不做**——只讀 `$GS_HARNESS_ROOT/state/context-agent.md`
再算它多舊。SessionStart 是**同步阻塞 session 開場**的，跑多久使用者就乾等多久；
跨 repo 全掃要 20 秒，所以採集與 render 都在 `harness context --refresh`（nightly
loop）時做完。實測 Windows 353 ms。

- `matcher: "startup|clear|compact"` — 刻意排除 `resume` / `fork`：那兩種情況上一輪
  transcript 裡已經有同一份 context，再注入是純重複付費。
- cache 不存在或是空檔 → **安靜跳過**。注入空內容會讓 agent 把「有這個區塊但裡面
  沒東西」讀成「沒事」。
- cache 超過 3 天 → **照樣注入但標出天數**。舊 context 仍遠勝於沒有 context。
- **三份**（`.ps1` / `.sh` / `.mjs`）契約相同、必須同時維護。詳見下方「同一支 hook
  的三種形式」。

測試：
- `pwsh -File tests/test-context-inject.ps1`（11 個案例，測 `.ps1`）
- `node --test "plugins/gs-meta-harness/hooks/context-inject.test.mjs"`（12 個案例，測 `.mjs`）

## branch-guard.ps1 — PreToolUse 受保護分支硬閘門

擋掉推向 `main` / `master` 的 push、force push、`--mirror`、刪除受保護分支。
用 token 解析而非正則，所以 `main-experiment`、`feature/main` 這類名字裡剛好含
main 的分支不會被誤擋；並會先剝掉 heredoc 內文（commit message 引用 git 指令
不該被當成要執行）。逃生門：指令尾端加 `#allow-protected-push`。

測試：
- `pwsh -File tests/test-branch-guard.ps1`（38 個案例，測 `.ps1`）
- `node --test "plugins/gs-meta-harness/hooks/branch-guard.test.mjs"`（50 個案例，測 `.mjs`；
  38 個逐條移植自上面那份，另 12 個是移植時補的邊界案例）

> ⚠️ **仍然沒有 `.sh` 版。** `install.sh` 在 POSIX 平台會**剝掉**這個 hook 而不是
> 註冊一個指向 `.ps1` 的死指令——註冊一個永遠跑不起來的 hook 是假綠燈，比沒有更糟。
> POSIX 平台現在的解法是**改裝 plugin**（`gs-meta-harness`，走 `.mjs`），
> 不再等 `.sh`。

---

## 同一支 hook 的三種形式（`.ps1` / `.sh` / `.mjs`）

`context-inject` 與 `branch-guard` 各有多份實作，載體不同、契約相同：

| Hook | `.ps1` | `.sh` | `.mjs`（plugin） |
|------|--------|-------|------------------|
| `context-inject` | `hooks/context-inject.ps1` | `hooks/context-inject.sh` | `plugins/gs-meta-harness/hooks/context-inject.mjs` |
| `branch-guard` | `hooks/branch-guard.ps1` | *（無，POSIX 請改裝 plugin）* | `plugins/gs-meta-harness/hooks/branch-guard.mjs` |

- `.ps1` / `.sh` 走 **`install.ps1` / `install.sh`**（原作者的跨機器同步路徑，
  逐檔複製到 `~/.claude/hooks/` 並改 `settings.json`）。
- `.mjs` 走 **Claude Code plugin**（`plugins/gs-meta-harness/`，由該目錄的
  `hooks/hooks.json` 註冊，指令一律寫成
  `node "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.mjs"`，不 hardcode 路徑）。
  選 Node 是因為 Node **隨 Claude Code 附帶**，Windows / macOS / Linux 同一份檔就能跑，
  使用者不必額外裝 pwsh 或 jq。

> ⚠️ **三份必須同時維護。** 只改一份的話，其他平台的使用者會**靜默地拿到舊行為**——
> 不會噴錯、不會有警告，因為 hook 的失敗一律是靜默的（那正是這整套稽核在對付的
> 「假綠燈」）。改任何一份的判定邏輯之前，先確認另外兩份要不要跟著改；改完三份的
> 測試都要跑過（上面各節列的指令）。

**已知的實作漂移**（移植 `.mjs` 時發現，尚未收斂，先留痕）：
`context-inject` 的「過期幾天」格式，`.ps1` 用 `"{0:N0}"`（.NET banker's rounding，
且 ≥1000 會加千分位逗號），`.sh` 用整數 floor 除法。同一份放了 3.6 天的 context，
`.ps1` 說「已 4 天」、`.sh` 說「已 3 天」。`.mjs` 目前對齊 `.ps1`。
