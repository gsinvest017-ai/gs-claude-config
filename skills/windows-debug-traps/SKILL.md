---
name: windows-debug-traps
description: Windows / PowerShell / WSL / 排程 / MCP 環境的「已知陷阱」對照表，用來在花時間 debug 程式邏輯前，先排除那些看起來像 bug、其實是環境坑的症狀。當使用者輸入 /windows-debug-traps、說「腳本在排程跑不出東西」、「手動跑好好的、排程就壞」、「輸出是空的 / 0 bytes」、「中文變亂碼」、「JSON 塞回去檔案就壞了」、「toast 不跳」、「MCP 連不上」、「權限規則沒生效」、「WSL 裡 git 說 dubious ownership」、「SQLite 複製出來就損壞」時啟動；也應在 diagnosing-bugs / systematic-debugging 進入「提假設」階段前主動掃一遍。
---

# Windows Debug Traps

**用法**：拿使用者描述的症狀去比對下表，命中就直接照「立即驗證」那欄做一次確認，別急著讀程式碼。沒命中就交還給 `diagnosing-bugs`（建 repro loop）或 `systematic-debugging`（四階段紀律）。

本表只收「本機環境已經真的踩過、而且會重複發生」的坑。修好一個新的環境坑，就把它加進來。

---

## 1. PowerShell 執行層

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| 腳本在排程 / 子程序輸出 **0 bytes**，手動跑正常 | `pwsh -File` 沒加 `-NoProfile`，被 profile（idle-arcade、oh-my-posh 之類）卡住 | 重跑一次加上 `-NoProfile`，比對輸出 |
| 傳 `A,B,C` 進腳本卻只拿到一個字串 | `-File` **不會**把逗號解析成陣列 | 要傳陣列改用 `pwsh -NoProfile -Command "& { ... }"` |
| 單元素陣列送進 API 回 `422 not of type array` | `switch` 會**拆開**陣列，單元素退化成物件 | 改 `if/elseif`；序列化前用 `@()` 包住 |
| 計數器永遠是 0、屬性賦值像沒發生 | `ConvertFrom-Json` 出來的 `PSCustomObject` 賦值**不存在的屬性會靜默失敗**（配 `EAP=SilentlyContinue` 尤其無聲） | 改 `Add-Member -Force`；把 EAP 暫時設 `Stop` 重跑 |
| 原生指令明明成功卻被當例外中止 / exit code 判斷不執行 | PowerShell 5.1 下原生指令寫 stderr + `$ErrorActionPreference='Stop'` | 改經 `cmd /c` 吞掉輸出，或暫時降 EAP |
| `-ErrorAction SilentlyContinue` 還是 exit 1 | 非終止錯誤不會進 `catch`，但仍污染 exit code | 要真的忽略：`try { ... -ErrorAction Stop } catch {}` |

## 2. 打包 / ps2exe（= PowerShell 5.1 引擎）

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| 捷徑點下去閃退，直接跑 exe 卻正常 | `$PSScriptRoot` 在 ps2exe 下是**空的** | 用 `[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName` 取路徑 |
| `?.` / `??` / 三元運算子語法錯誤 | ps2exe 走 5.1 引擎，不認 7.x 語法 | 這些語法一律不進打包腳本 |
| 中文在 exe 裡變亂碼 | UTF-8 **無 BOM** 被當 cp950 讀 | 存成 UTF-8 with BOM |
| 上面三個混在一起 | 根治法：ASCII-only 的 bootstrap，再轉手丟給 `pwsh` 7 跑真正的邏輯 | — |

## 3. Windows 排程工作

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| 排程跑起來會閃黑框 | `-WindowStyle Hidden` 在 Windows Terminal 下**完全擋不住** | console-only 走 `wscript` + `run-hidden.vbs`；需要彈 GUI 走 `conhost --headless` |
| 排程「某天開始」靜默失效，沒有錯誤 | 動作路徑寫成 WindowsApps 帶版本號的 `pwsh.exe`，pwsh 更新後路徑消失 | 一律指向 `C:\Program Files\PowerShell\7\pwsh.exe` |
| toast 不跳了 | 為了藏視窗把帳戶改成 S4U（不儲存密碼），BurntToast 失效 | **別改 S4U**；改用上面的 vbs / conhost 方案 |
| toast 在某些腳本裡完全沒反應 | BurntToast **只裝在 pwsh 7**，`powershell` 5.1 看不到 | 子程序明確呼叫 `pwsh` |
| hook 觸發的工作沒跑完就被砍 | SessionEnd hook 只有約 1.5s 預算 | 要跑長任務就 `-Detach` 丟到背景 |

## 4. Git / Git Bash / WSL 交界

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| `ls C:\Users\...` 說找不到、路徑少了反斜線 | Bash tool 會吃掉反斜線（`C:UsersUser...`） | 用引號包住，或改正斜線 `/c/Users/...`；PowerShell tool 無此問題 |
| `robocopy /MIR` 變成 `C:\Program Files\Git\MIR` | Git Bash 的 MSYS 路徑轉換 | 前綴 `MSYS_NO_PATHCONV=1` |
| WSL / UNC 路徑下 git 拒絕操作 | `dubious ownership` | `git config --global --add safe.directory <path>` |
| `.gitignore` 某條規則整條失效 | **不支援行內註解**：`datastore/ # 註解` 會整條壞掉 | 註解另起一行；接手沒推過的 repo 先全檔掃一遍 |
| `dev/xxx` 分支 push 被拒（ref conflict） | repo 已有裸 `dev` 分支，D/F 衝突 | 改用 `feat/` 前綴 |
| `gh pr create` 說 `No commits between…` | 這是 fork，PR 預設開到**上游母 repo** | 加 `--repo <自己的 owner/repo>` |
| symlink 建出來是普通檔 | PowerShell 的 `New-Item -ItemType SymbolicLink` 忽略 Dev Mode | 用 `cmd /c mklink` |

## 5. Claude Code 自身環境

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| `~/.claude.json` 改完變 0KB / 設定全失 | 該檔有**只差大小寫的重複 key**，`ConvertFrom-Json` 往返會失敗但不中斷，`$null` 寫回把檔案清空（已踩過） | 讀用 `-AsHashtable`，寫就**別用往返**；動大設定檔前先備份 |
| 加了 allow 規則還是每次問 | 判定順序 deny → ask → allow，且**跨 scope 合併不覆蓋**：user 層的 ask 蓋不掉 | 檢查 user 層是否有同名 ask 規則；非互動 `claude -p` 下 ask ≡ deny |
| 專案層 `.claude/settings.json` 整份沒作用 | workspace 未受信任會**整份忽略**專案層權限設定 | 找 CLI 啟動時的 `Ignoring` 警告 |
| MCP server 回 `-32000` | Windows 下用了裸 `npx`，PATH 沒有 Node | 改絕對路徑 `npx.cmd` |
| 改了 MCP 設定沒生效 | `/mcp` reconnect **不會**重讀 `~/.claude.json` | 完全重啟 Claude Code |
| 剪取工具截圖後 `Ctrl+V` 貼不進去、**靜默無反應** | Windows 上 `chat:imagePaste` 官方預設是 **`Alt+V`**。`Ctrl+V` 是 Windows Terminal 自己的 binding，它只取 `CF_UNICODETEXT`；剪貼簿只有點陣圖時取到空 → 送 0 bytes → Claude Code **連按鍵都沒收到** | 改按 `Alt+V`（2.1.227 實測正常）。檔案總管 `Ctrl+C` 複製圖檔則一直可用，因為那是 `CF_HDROP` 路徑清單 |

## 6. dap CLI（debugging-code skill 的後端）

`dap` 裝在 `C:\Users\User\tools\dap\dap.exe`（已加進 User PATH）。它的文件是為 macOS / Linux 寫的，Windows 下有兩個必踩的坑：

| 症狀 | 陷阱 | 正確寫法 |
|---|---|---|
| `starting debugpy: process exited without reporting listen address` | `--python` 預設找 PATH 上的 **`python3`**，Windows 上那是 WindowsApps 的 Store stub，不是真的直譯器 | 每次都明確指定：`--python "C:\Users\User\AppData\Local\Programs\Python\Python312\python.exe"`（專案有 venv 就指該 venv 的 `python.exe`） |
| `invalid breakpoint spec ...: line must be a number` | `--break` 用 `file:line` 解析，Windows 絕對路徑的 `C:` 冒號會把它打壞 | **先切到腳本所在目錄**，`--break` 只給檔名：`dap debug app.py --break app.py:42` |

已實測可用的完整叫法（斷點命中並回傳 locals / stack）：

```powershell
Set-Location <script dir>
dap debug app.py --break app.py:42 --python "<絕對路徑 python.exe>"
dap eval "some_var"
dap stop   # 收尾一定要跑，否則 daemon 留著
```

`debugpy` 需裝在你指定的那個直譯器裡（本機 Python 3.12 已有 debugpy 1.8.20）。

## 7. 資料與服務

| 症狀 | 陷阱 | 立即驗證 |
|---|---|---|
| 從容器複製出來的 SQLite 檔損壞 / 少資料 | WAL 模式下 `docker cp` 只拿 `.db`，漏了 `-wal` / `-shm` | 先 `PRAGMA wal_checkpoint(TRUNCATE);` 再複製，或三個檔一起複製 |
| server 起不來說 port 被佔 | 殘留進程（前一次沒收乾淨） | `netstat -ano \| findstr :<port>` → `Get-Process -Id <pid>` 確認是誰再處理 |
| 中文輸出變 `?` 或亂碼 | 主控台 / 檔案編碼在 cp950 與 UTF-8 之間錯配 | 確認寫檔編碼；pwsh 7 預設 UTF-8 無 BOM，5.1 不是 |
| Windows 記憶體看起來吃很滿 | 5–7 成是**正常**的（cache / standby），Windows 也沒有 zombie 進程概念 | 別當洩漏處理；要抓孤兒進程看「父已死」條件 |

---

## 收尾

命中並修掉一個坑之後：

1. 在 commit message 裡寫清楚「症狀 → 真正原因」，因為下一個人只會搜症狀。
2. 如果這個坑**會再發生**（環境層、而非這次的程式邏輯），補一列進上面的表。
3. 如果它同時值得跨 session 記住，寫進 `~/.claude/projects/<project>/memory/` 並在 `MEMORY.md` 補索引行。
