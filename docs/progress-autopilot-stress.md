---
type: progress
updated: 2026-07-31
repos: [gs-claude-config]
owner: Kevin (gsinvest017)
---

# progress — /autopilot 迴圈核心壓測

## 目標

backlog 項目「/autopilot 迴圈核心壓測」（P2·M）：`/autopilot` 的 Stop hook 是唯一
一層「硬性」不停機制，它壞掉的失敗模式很惡劣——**要嘛該停不停（燒 token）、要嘛
該續跑卻靜默失效（使用者以為開了其實沒開）**。上線以來只有人工體感驗證，沒有任何
自動化測試。這次補上壓測 harness，並修掉它抓到的 bug。

## 範圍與紅線

- **絕不碰活的 `~/.claude/.autopilot/`**：harness 每個案例開一個 temp 沙盒，把
  `USERPROFILE`（ps1 / node）與 `HOME`（bash）指過去。跑測試的 session 自己的
  autopilot 狀態完全不受影響。
- 三個實作跑同一份案例表，因為同一套狀態機在這個 repo 有三份：
  | 實作 | 檔案 | 安裝路徑 |
  |------|------|----------|
  | ps1 | `hooks/autopilot-continue.ps1` + `hooks/autopilot-arm.ps1` | script 安裝（Windows） |
  | sh | `hooks/autopilot-continue.sh` + `hooks/autopilot-arm.sh` | script 安裝（WSL / macOS，需 jq） |
  | mjs | `plugins/gs-autopilot/hooks/autopilot.mjs` | plugin 安裝（單檔雙事件） |

## Milestones

- [x] M1 壓測 harness `tests/autopilot-stress.ps1`（25 案例 × 3 實作）
- [x] M2 修掉 harness 抓到的 3 個 bug，50 案例全綠
- [x] M3 同步活的 `~/.claude/hooks` + 進度檔 + 收尾

## 怎麼跑

```powershell
pwsh ~\.claude\tests\autopilot-stress.ps1            # 全部實作，完整 50 輪上限壓測
pwsh ~\.claude\tests\autopilot-stress.ps1 -Quick     # 5 輪，快速回歸
pwsh ~\.claude\tests\autopilot-stress.ps1 -Impl ps1
pwsh ~\.claude\tests\autopilot-stress.ps1 -KeepSandbox   # 留下 temp 沙盒供檢查
```

exit 0 = 全綠，1 = 有 FAIL。缺工具的實作報 **SKIP 並附原因**，不靜默跳過。

## 案例覆蓋

- **V1–V5 五道安全閥**：`stop_hook_active` 讓步、無旗標預設關閉、外來 session 旗標
  不得劫持、done sentinel 收尾清檔、iterations 達上限強制停 + stderr 提示。
- **V6–V14 邊界**：正常續跑的 reason 計數、`max_iterations=0` 退回 50、缺欄位視為 0、
  旗標損毀 / 空檔 / 空 stdin 一律 fail-open、BOM 旗標仍須正常續跑、連續 5 輪計數單調、
  iterations 遠超上限立即停。
- **A1–A8 arm 子指令**：`on` 綁定正確 session、`off` 清兩個檔、`status` 與裸
  `/autopilot` 不動狀態、殘留 done 必須在 `on` 時清掉、多行任務描述仍須武裝、
  任務含引號／反斜線／中文不得讓旗標變成非法 JSON、前置空白仍可武裝。
- **S1–S3 壓測**：連跑到上限後精準放行一次（預設 50 輪）、兩 session 先後 `on` 的
  單一旗標行為、同 session 兩個 Stop 併發不得損毀 `state.json`。

## 日誌

### 2026-07-31 M1 — harness（commit c5d934e）

首跑 50 案例 48 綠。兩個 FAIL 都在 ps1，mjs 同案例通過 → 實作漂移，不是測試寫錯。

### 2026-07-31 M2 — 修 3 個 bug（commit d56b833）

1. **續跑上限閥完全失效（嚴重，V8）** — `continue.ps1` 的
   `$state.iterations = $iterations + 1` 在**缺 `iterations` 屬性**的 PSCustomObject
   上是靜默 no-op（`$ErrorActionPreference='SilentlyContinue'` 又把錯誤吃掉）。旗標
   一旦沒有該欄位（手寫的、或舊版 arm 產生的），計數永遠寫不回去 → valve 5 永遠
   不觸發 → 一路續跑到 Claude Code 內建的 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`（本機
   設 60）才停。症狀是 reason 印成「第 /50 次續跑」——**數字位置是空的**，這就是
   線上辨識這個 bug 的特徵。改用 `Add-Member -Force`，reason 改用區域變數 `$next`。
2. **多行任務不武裝（靜默失敗，A6）** — `arm.ps1` 與 `arm.sh` 的 regex 都以 `(.*)$`
   收尾，而 .NET 預設與 bash ERE 的 `.` 都不吃換行。於是
   `/autopilot on 做 X⏎細節…` 整條 match 失敗、hook exit 0 不建旗標，**使用者完全
   收不到錯誤**，以為 autopilot 開了其實沒開。ps1 加 `(?s)`；sh 改成只 match 指令頭，
   task 用 `sed '1s@…@@'` 剝掉第一行前綴、保留後續行。mjs 因為原本就用 `/s` flag，
   沒有這個 bug。
3. **BOM 相容** — ps1 兩支原本用 `Set-Content -Encoding UTF8`，在 **PS 5.1 會寫出
   BOM**；同一個旗標檔的 sh（jq）與 mjs（`JSON.parse`）reader 都會解析失敗 →
   fail-open → autopilot 靜默失效。ps1 改用 `UTF8Encoding($false)` 明確寫無 BOM，
   兩個 reader 也各自加上剝 BOM。V12 從「觀察筆記」升級為硬斷言。

### 2026-07-31 M3 — 收尾

- `install.ps1` 是**複製**而非 symlink（`hooks/` 在每台機器是實體目錄），所以修完
  repo 還要把 `autopilot-continue.ps1` / `autopilot-arm.ps1` 複製到
  `~/.claude/hooks/`，否則活的 session 用的還是舊版。已同步並比對 SHA256 一致 +
  AST 解析 0 錯誤。
- 未來改這條 hook 的 SOP：**改 repo → 跑 harness → 同步 live → 再跑一次 harness**。

## 已知限制（測到但刻意不修）

- **sh 端到端未驗**：本機 Git Bash 與 WSL 都沒有 jq，`.sh` hook 缺 jq 時直接
  fail-open（exit 0），狀態機測不出來 → harness 報 SKIP。M2 對 sh 的兩處改動已用
  不依賴 jq 的方式單獨驗過（8 種 prompt 的 match/task 抽取 + BOM 剝除首 byte 為
  `0x7b`），但整條 hook 仍未在有 jq 的環境跑過。**要補的話：在 WSL 裝 jq 後跑
  `-Impl sh`。**
- **單一全域旗標（S2）**：`state.json` 只有一份，第二個 session 下 `/autopilot on`
  會覆蓋第一個的旗標，第一個 session 於下次 Stop 被放行、**靜默退出 autopilot**。
  這是設計取捨（valve 3 保證的是「不誤鎖別人」，不是「多 session 各自續跑」）。
  S2 把現行行為釘住，避免將來無聲改變。要支援並行 autopilot 得改成
  per-session 旗標檔（`state-<session_id>.json`）。
- **併發 Stop 的 lost update（S3）**：同 session 兩個 Stop hook 同時跑時，計數可能
  只 +1（read-modify-write 無鎖）。實測 ps1 得 1、mjs 得 2，兩者都合法。後果僅是
  上限略微寬鬆，不影響安全性，故不加鎖。
- **`codex-hooks/` 下的同名 ps1 未修**：那是未進版控的 Codex toolkit 進行中工作
  （7/9），不屬本次範圍。它若是從 `hooks/` 複製出去的，同樣有上述 1、2、3 三個 bug。
