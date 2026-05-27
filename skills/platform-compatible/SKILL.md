---
name: platform-compatible
description: 稽核並（在 --fix 時）修正 repo 的平台相依問題，使其同時可在 Windows / Linux(/macOS) clone、安裝、執行。掃描路徑分隔符、shell 腳本、換行(EOL)/.gitattributes、檔名大小寫與保留字、環境變數語法、原生相依套件、檔案編碼、CI matrix 等八大類。當使用者輸入 /platform-compatible、說「讓這個專案跨平台」、「在 Windows 上跑不起來」、「相容 Windows 和 Linux」、「這個 repo 能不能在 Windows 用」、「幫我檢查跨平台問題」、「加 .gitattributes / 換行問題」時啟動。預設只稽核出報告，需 --fix 才改檔。
---

# /platform-compatible — 跨平台相容性稽核與修正

當使用者觸發時，稽核**當前 repo** 的平台相依問題，並（在 `--fix` 時）修正，使其同時可在 **Windows** 與 **Linux/macOS** 上 clone、安裝、執行。全程繁體中文回報。

**預設 dry-run**（只稽核出報告，不改檔）；需 `--fix` 才實際改檔。原則是「**補**相容層，不是把某平台的支援拔掉」——例如有 `.sh` 就補 `.ps1`，而不是刪 `.sh`。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--fix` | 否 | 真的改檔（否則只出稽核報告） |
| `--target <win,linux,mac>` | `win,linux` | 目標平台集合（決定哪些差異算「問題」） |
| `--scope <all\|paths\|scripts\|eol\|names\|env\|deps\|encoding\|ci>` | `all` | 限定稽核類別 |
| `--ci` | 否 | 額外產生 / 更新跨平台 CI matrix |

範例 args：
- `""` → 全類別稽核、出報告、不改檔
- `"--fix"` → 全類別套用修正
- `"--scope eol --fix"` → 只處理換行 / .gitattributes 並修正
- `"--target win,linux,mac --ci --fix"` → 三平台 + 補 CI matrix + 修正

## 1. 前置檢查

確認在 git repo 內（EOL renormalize、檔名衝突偵測需要 git）。掃出語言組成（從副檔名與 manifest），決定哪些類別適用。**排除** vendored / 產物目錄：`.git`、`node_modules`、`vendor`、`dist`、`build`、`.venv`、`target`、`__pycache__`。

## 2. 稽核類別（逐項掃描）

### A. 路徑處理（paths）
- 硬編路徑分隔符：字串拼接 `"a/" + b`、`"dir\\file"`、`os.path` 與字串混用
- 硬編絕對路徑：`C:\Users\...`、`/home/<user>`、`/tmp`、`/var/...`
- **修正**：Python → `pathlib.Path` / `os.path.join`；Node → `path.join` / `path.sep`；Go → `filepath`。temp/home → `tempfile` / `os.homedir()` / `Path.home()`

### B. Shell 腳本 / 執行器（scripts）
- 只有 `.sh` 沒有對應 `.ps1`（Windows 無法執行）
- npm/Make 內直接用 `rm` / `cp` / `mv` / `export` 等 POSIX 指令
- bash-ism 與 shebang（Windows 忽略 shebang）
- **修正**：補對應 `.ps1`，或改用跨平台 task runner（`npm scripts` + `rimraf`/`shx`/`cross-env`、`just`、`python -m`）

### C. 換行（EOL）/ `.gitattributes`（eol）
- 缺 `.gitattributes` → 換行交給各機器 autocrlf，易壞
- 已 commit 的 `.sh` 含 CRLF → Linux bash 報 `\r` 錯誤
- **修正**：加 `.gitattributes`（見第 4 步範本），加好後 `git add --renormalize .`

### D. 檔名 / 大小寫 / 保留字（names）
- 大小寫衝突：兩檔僅差大小寫（Windows 不分大小寫 → clone 壞）
- Windows 保留檔名：`CON PRN AUX NUL COM1-9 LPT1-9`；檔名含 `:`、`*`、`?`、`<`、`>`、`|`、結尾空白或 `.`
- 路徑過長（>260 字元）風險
- **修正**：`git mv` 改名（提示影響 import / 參照）；保留字檔名必須改名

### E. 環境變數 / 指令（env）
- 文件 / 腳本內 `$VAR`（POSIX）vs `%VAR%`（cmd）vs `$env:VAR`（PowerShell）混用
- `export X=` vs `set X=`；`&&` 在舊 cmd.exe 的差異（PowerShell 7 已支援）
- **修正**：腳本提供兩版，或在文件同時列兩平台寫法；npm 用 `cross-env`

### F. 相依套件 / 原生模組（deps）
- 平台限定套件：`pywin32`、`uvloop`（無 Windows）、`fcntl`/`pty`/`termios`（POSIX-only）、`windows-curses`
- **修正**：Python requirements 加 environment markers（`; sys_platform == "win32"` / `!= "win32"`）；package.json 用 `os`/`cpu` 欄位或 `optionalDependencies`

### G. 檔案編碼（encoding）
- 讀寫檔未指定 encoding（Windows 預設非 UTF-8，中文 / emoji 易壞）；UTF-8 BOM 差異
- console 輸出中文 / emoji 在 Windows 編碼
- **修正**：明確 `encoding="utf-8"`（Python open / Node readFile）；必要時設 `PYTHONUTF8=1`

### H. CI / 自動化（ci）
- CI 只跑 `ubuntu-latest` → 沒驗證過 Windows
- step 預設 bash shell，Windows runner 需指定 `shell:`
- **修正**（`--ci` 時）：`strategy.matrix.os` 加 `windows-latest`（+ `macos-latest`）

## 3. 稽核報告（dry-run 預設）

輸出表格：

| 類別 | 嚴重度 | 命中檔案數 | 範例 | 修正建議 |
|------|--------|-----------|------|----------|

嚴重度判準：
- **高**：直接導致某目標平台無法 clone / install / run（CRLF in .sh、大小寫衝突、保留字檔名、只有 .sh、平台限定 import 無 fallback）
- **中**：行為差異或部分功能壞（硬編路徑、未指定編碼、env 語法）
- **低**：風格 / 最佳實踐（缺 .gitattributes 但目前沒壞、CI 未加 matrix）

若**沒有** `--fix` → 結束，回報「稽核完成；要套用修正請加 `--fix`（建議先處理完高嚴重度項）」並列出高嚴重度清單。

## 4. 修正階段（僅 `--fix`）

逐類套用，可逆優先，每類改完印 diff 摘要：

`.gitattributes` 建議範本：

```gitattributes
* text=auto eol=lf
*.sh   text eol=lf
*.bash text eol=lf
*.ps1  text eol=crlf
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.png binary
*.jpg binary
```

加好 `.gitattributes` 後重新正規化既有檔案的 EOL：

```bash
git add --renormalize .
```

其餘修正：補對應 `.ps1` / `.sh`、路徑改用標準函式庫、open 加 `encoding="utf-8"`、requirements 加 environment markers、`--ci` 時改 CI matrix。大小寫衝突 / 保留字檔名用 `git mv` 並提示需同步改參照處。

## 5. 驗證

- 腳本語法：`bash -n *.sh`；`pwsh -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw x.ps1))"`
- 重跑稽核，確認高嚴重度項歸零
- 確認 `.gitattributes` 生效：`git ls-files --eol <file>` 看 `i/`（index）欄
- 若有測試，提示在兩平台或 CI matrix 跑（本 skill 不替使用者開兩台機器）

## 6. 完成回報

3~5 行：稽核找到幾項（依嚴重度）、`--fix` 修了哪些類別、剩餘需人工處理的項目、後續建議（例如「跑 `/one-button-launch` 產生跨平台啟動器」「在 CI matrix 跑一輪確認」）。

## 全域註冊（apply to system globally）

本 skill 安裝在 user-scope：`~/.claude/skills/platform-compatible/SKILL.md` → 對**所有**專案全域可用，不限單一 repo。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，故新增此檔即等於全域註冊；新 session 啟動時會載入。

## 不要做的事

- ❌ 沒有 `--fix` 就改檔
- ❌ 把 `.sh` 直接刪掉（Linux 還要用）；是「補 `.ps1`」不是「換掉 `.sh`」
- ❌ 無腦把整個 repo 轉成全 CRLF 或全 LF；一律依 `.gitattributes` 分類
- ❌ 動 vendored / 第三方目錄（`node_modules`、`.git`、`vendor`、`dist`）
- ❌ 把容器內 Linux runtime 的東西也硬要跨平台（見邊界情況）

## 邊界情況

- **純 Python 套件無 script** → 重點放 pathlib + `encoding="utf-8"` + `sys_platform` markers
- **已經很跨平台** → 報告「無高嚴重度問題」，只列低嚴重度與可選優化
- **容器化專案（runtime 固定 Linux container）** → 區分「host 端開發工具鏈」（要跨平台）與「容器內 runtime」（不必）；只稽核 host 端會碰到的部分
- **大小寫衝突檔已 commit** → 在不分大小寫的檔案系統上需先 `git mv` 到暫名再改回，提示風險
- **目標只含單一平台**（`--target linux`）→ 退化成單純的 Linux 慣例檢查，不報 Windows-only 問題

## 與其他 skill 協作

- **`/one-button-launch`**：launcher 產生 `run.sh` / `run.ps1` 後跑本 skill，確保換行（`run.sh eol=lf` / `run.ps1 eol=crlf`）與路徑都跨平台
- **CLAUDE.md Behavior rules**：呼應「Windows 絕對路徑要 quote / 用正斜線」「新檔換行用 CRLF」兩條跨 repo 規則
- **`/safe-yolo`**：`--fix` 會動多檔，適合包成 safe-yolo milestone
