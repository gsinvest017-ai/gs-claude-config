---
name: one-button-launch
description: 為「還沒有一鍵啟動機制」的 repo 產生一個跨平台單一入口啟動器（偵測技術棧 → install → build → migrate → 起服務 → run 一條龍，同時產出 run.sh 與 run.ps1）。當使用者輸入 /one-button-launch、說「幫這個專案做一鍵啟動」、「我想一個指令就能跑起整個專案」、「加一個 run 腳本」、「one command to start」、「這專案怎麼跑、幫我包成一鍵」時啟動。預設先偵測是否已有啟動機制，若已有則回報並停止（除非 --force）。
---

# /one-button-launch — 一鍵啟動專案產生器

當使用者觸發時，偵測**當前 repo** 的技術棧，為「**尚未具備一鍵啟動機制**」的專案產生一個跨平台單一入口啟動器，讓使用者一個指令就能把整個專案跑起來。全程繁體中文回報。

核心原則：**先確認專案還沒有此功能**（規格要求「當專案還沒有此功能」），若已有就回報並停止，不重複造輪子。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--name <n>` | `run` | 啟動器檔名（產出 `<n>.sh` / `<n>.ps1`） |
| `--dry-run` | 否 | 只印計畫與會產生的檔案內容，不寫檔 |
| `--force` | 否 | 即使偵測到既有啟動機制也照樣產生（新增或覆寫） |
| `--no-install` | 否 | 啟動器本身跳過依賴安裝步驟（假設已裝好） |
| `--profile <dev\|prod>` | `dev` | 啟動模式（dev 用熱重載 / prod 用正式啟動） |
| `--runner <auto\|sh-ps1\|make\|just\|task\|npm>` | `auto` | 指定產生哪種啟動器形式 |

範例 args：
- `""` → auto 偵測、產生 `run.sh` + `run.ps1`、dev profile
- `"--dry-run"` → 只印計畫不寫檔
- `"--runner npm --profile prod"` → 用 package.json scripts、正式啟動
- `"--force --name start"` → 即使已有啟動機制也產生 `start.sh` / `start.ps1`

## 1. 前置檢查 — 偵測「是否已有一鍵啟動」

先確認在 git repo 內（非必要，但用於決定 README / .gitattributes 寫法）。接著掃描既有啟動機制訊號：

- `Makefile` 內有 `run` / `start` / `up` / `dev` target
- `justfile`、`Taskfile.yml`（task）
- `package.json` 的 `scripts.start` / `scripts.dev`
- `docker-compose.yml` / `compose.yaml`（且 README 有記載 `up`）
- 既有 `run.sh` / `run.ps1` / `start.sh` / `scripts/run*` / `bin/start`
- `Procfile`、`Tiltfile`、`skaffold.yaml`、`.devcontainer/`
- README 有「Quick start / 一鍵 / one command」段且指向**單一**指令

**判定**：
- 若找到既有機制且**沒有** `--force` → 印出找到什麼，回報「此專案已具備一鍵啟動（`<which>`）；如要重建請加 `--force`，或用 `--runner` 指定另一種形式」並**停止**。
- 若有 `--force` 或沒找到 → 繼續。

## 2. 偵測技術棧

從 manifest / lockfile 推斷：

| 訊號檔 | 技術棧 / 套件管理器 |
|--------|---------------------|
| `package.json` + `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `bun.lockb` | Node（npm / yarn / pnpm / bun） |
| `pyproject.toml` / `requirements*.txt` / `Pipfile` / `uv.lock` / `*.yml`(conda) | Python（pip / poetry / uv / pipenv / conda） |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pom.xml` / `build.gradle(.kts)` | Java / Kotlin（maven / gradle） |
| `Gemfile` | Ruby（bundler） |
| `composer.json` | PHP |
| `*.csproj` / `*.sln` | .NET |
| `Dockerfile` / `docker-compose.yml` | 容器化 |

同時判斷：
- **服務數量**：single（一個 app）vs multi-service（compose 多服務 / monorepo workspaces / 多個子目錄各有 manifest）
- **DB / migration**：`alembic`、`prisma`、`flyway`、`migrations/`、`*.sql`
- **環境變數範本**：`.env.example` / `.env.sample` / `.env.template`
- **進入點**：main 檔、dev server 指令、container entrypoint

## 3. 推導啟動序列

組出一條有序 pipeline（缺的步驟略過）：

1. **precheck** — 必要 runtime 是否存在與版本（node / python / docker…），缺則明確報錯退出
2. **env** — 若有 `.env.example` 且無 `.env` → 複製一份（提示使用者填值，**絕不**把值寫死或 commit）
3. **install** — 安裝依賴（`--no-install` 時略過）
4. **build** — 需編譯 / 打包才做（tsc、vite build、cargo build、go build…）
5. **migrate** — 偵測到 migration 工具才做
6. **services** — 起後端服務（`docker compose up -d` 拉 db / redis 等），non-blocking
7. **run** — 前景啟動 app / dev server（這步會卡住 = 正常，代表服務在跑）

multi-service 但無 compose → 提示「建議產生最小 `docker-compose.yml` 或以平行方式起多個服務」，並在啟動器中以背景方式起次要服務、前景起主服務。

## 4. 選擇啟動器形式（`--runner auto` 決策樹）

- **Node 且有 package.json** → 在 `scripts` 補 `start` / `dev`，外加一個薄 `run.sh` / `run.ps1` 包裝（包到 precheck + env + install）
- **Go / Rust / C 等有 Makefile 慣例** → 加 `Makefile` 的 `run` target；**但 Windows 預設無 make**，故同時補 `run.ps1`
- **跨語言 / multi-service** → 同時產生 `run.sh` + `run.ps1`（相容性最高），或在使用者已裝 `task` 時用 `Taskfile.yml`
- **auto 預設**：**永遠至少產生 `run.sh`（POSIX）+ `run.ps1`（Windows）**，確保真正跨平台一鍵；其它形式（npm/make/just）視棧附加

兩個腳本必須**鏡像對應**（同樣步驟、同樣旗標），避免兩平台行為漂移。

## 5. 啟動器範本

`run.sh`（POSIX）骨架——idempotent、fail-fast、每步 echo：

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NO_INSTALL="${NO_INSTALL:-0}"
echo "▶ precheck"; command -v <runtime> >/dev/null || { echo "缺 <runtime>"; exit 1; }
[ -f .env ] || { [ -f .env.example ] && cp .env.example .env && echo "已建立 .env，請填值"; }
[ "$NO_INSTALL" = "1" ] || { echo "▶ install"; <install-cmd>; }
echo "▶ build";   <build-cmd>     # 視需要
echo "▶ migrate"; <migrate-cmd>   # 視需要
echo "▶ services"; <compose-up>   # 視需要，背景
echo "▶ run";     exec <run-cmd>
```

`run.ps1`（Windows，須鏡像對應）骨架：

```powershell
#Requires -Version 7
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$NoInstall = $env:NO_INSTALL -eq '1'
Write-Host "▶ precheck"; if (-not (Get-Command <runtime> -EA SilentlyContinue)) { throw "缺 <runtime>" }
if (-not (Test-Path .env) -and (Test-Path .env.example)) { Copy-Item .env.example .env; Write-Host "已建立 .env，請填值" }
if (-not $NoInstall) { Write-Host "▶ install"; <install-cmd> }
Write-Host "▶ build";   <build-cmd>
Write-Host "▶ migrate"; <migrate-cmd>
Write-Host "▶ services"; <compose-up>
Write-Host "▶ run";     <run-cmd>
```

把 `<...>` 換成第 2~3 步推導出的實際指令。

## 6. 串接與文件

- **README**：加「## 🚀 一鍵啟動 / Quick start」段，列 `./run.sh`（Linux/macOS）與 `.\run.ps1`（Windows）兩種用法，及 `NO_INSTALL=1` 等旗標
- **package.json**（若 Node）：補對應 `scripts`
- **執行權限**：`run.sh` 標可執行——Windows 上用 `git update-index --chmod=+x run.sh`（git 內記錄 +x），或提示 Linux 端 `chmod +x`
- **`.gitattributes`**：加 `run.sh eol=lf`、`run.ps1 eol=crlf`，避免換行被自動轉壞（與 `/platform-compatible` 同調）

## 7. 驗證（**不啟動長時服務**）

- 語法檢查：`bash -n run.sh`；PowerShell 用 `pwsh -NoProfile -Command "[void][scriptblock]::Create((Get-Content -Raw run.ps1))"` 解析
- 可選跑 precheck / install / build，但**不要**真的執行前景 `run` 或 `docker compose up` 把 port 卡住
- `--dry-run` 時只印內容不寫檔、不驗證執行

## 8. 完成回報

3~5 行：產生了哪些檔、怎麼用（兩平台各一行）、驗證結果、後續建議（例如「接著跑 `/platform-compatible` 確保 run 腳本與路徑跨平台」）。

## 不要做的事

- ❌ 偵測到既有啟動機制時硬覆蓋（除非 `--force`）
- ❌ 把 secrets / 實際環境變數值寫進啟動器或 commit `.env`
- ❌ 驗證階段真的拉起長時服務 / 開 port 卡住 CLI
- ❌ 假設目標機器一定有 `make` / `just` / `docker`；auto 模式以 `sh` + `ps1` 為最低相容基準
- ❌ 只產生 `run.sh` 就宣稱「跨平台」（Windows 跑不動）

## 邊界情況

- **空 repo / 無 manifest** → 回報無法判斷技術棧，請使用者指定 `--runner` 與進入點
- **純前端靜態站** → run = 起 dev server（vite / live-server / `python -m http.server`）
- **monorepo** → 偵測 workspaces，啟動器提供「逐套件」與「全起」選項
- **已有 docker-compose 但無 wrapper** → run 腳本就包 `docker compose up`（仍算補了一鍵入口）
- **需要 sudo / 特權 port** → 不自動加 sudo，在 README 明示

## 與其他 skill 協作

- **`/platform-compatible`**：本 skill 產生 `run.sh` / `run.ps1` 後，跑 platform-compatible 確保換行、路徑、環境變數都跨平台
- **`/safe-yolo`**：本 skill 會動多個檔，適合包成一個 safe-yolo milestone 一次 commit
