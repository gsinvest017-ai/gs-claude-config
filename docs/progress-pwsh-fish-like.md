# Progress — PowerShell fish-like 體驗 + 終端機美化

## 目標
讓 Windows 上的 PowerShell 7 達到接近 fish shell 的互動體驗：

- 語法 highlight、inline ghost-text 預測、fuzzy menu 補完（PSReadLine + CompletionPredictor）
- 終端機美化三件套：Terminal-Icons（檔案圖示）、posh-git（git 狀態嵌入 prompt）、oh-my-posh（完整 prompt 主題）

> 此進度文件只追蹤 /safe-yolo 觸發的第二輪「美化套件」工作。第一輪（PowerShell 7 + PSReadLine + CompletionPredictor + fish-like keybindings）已在前一個對話完成，profile 落於 `C:\Users\User\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`。

## 計畫 Milestones

| Milestone | 內容 | 預期產出 |
|---|---|---|
| **M1** | 安裝 Terminal-Icons + posh-git（PSGallery, CurrentUser scope）+ oh-my-posh（winget） | 三個模組/binary 都已可載入；progress 文件初版 |
| **M2** | 把三者接入 PS7 `$PROFILE`，並在 fresh pwsh 驗證載入無錯 | profile 包含 `Import-Module Terminal-Icons / posh-git` 與 oh-my-posh init；驗證腳本顯示模組就緒 |
| **M3** | 收尾文件 + 使用說明（如何選 oh-my-posh 主題、Nerd Font 注意事項） | 完成的 progress 文件 + final commit |

## 環境
- OS: Windows 11 Home 10.0.26200
- Shell: PowerShell 7.6.1（pwsh.exe，已於前一輪 winget 安裝）
- 既有 profile: `C:\Users\User\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`（fish-like PSReadLine 設定已存在）

## 進度日誌

### M1 — 安裝套件
**完成內容：**
- `Install-Module Terminal-Icons -Scope CurrentUser -Force` → **Terminal-Icons 0.11.0**
- `Install-Module posh-git -Scope CurrentUser -Force` → **posh-git 1.1.0**
- `winget install JanDeDobbeleer.OhMyPosh` → **Oh My Posh 29.13.1**

**安裝位置：**
- PSGallery 模組 → `~\Documents\PowerShell\Modules\<name>\<version>\`（PS7 user scope）
- oh-my-posh binary → `C:\Users\User\AppData\Local\Microsoft\WindowsApps\oh-my-posh.exe`（winget 透過 MSIX/Store 方式安裝，user PATH 預設已含）

**Commit:** `c01626c`

**注意事項：**
- 三個套件都裝在 user scope，沒有動到系統路徑 / 沒有用 admin。
- 第一輪建立的 fish-like profile 不會被本輪影響；M2 只會在 profile 尾端**追加**新的 Import / init 區塊，不修改既有設定。

### M2 — 接入 PS7 profile + 驗證

**完成內容：**
- 在 `Microsoft.PowerShell_profile.ps1` 尾端追加 `# === Prettify (M2) ===` 區塊，順序為 `Terminal-Icons → posh-git → oh-my-posh`（oh-my-posh 必須最後，才能擁有最終的 prompt function）。
- 下載 `jandedobbeleer.omp.json` 至 `C:\Users\User\AppData\Local\oh-my-posh\themes\`（winget MSIX 安裝模式不附 themes 檔，也不設 `POSH_THEMES_PATH`，必須自備）。
- profile 內顯式設定 `$env:POSH_THEMES_PATH` 供將來換主題用。
- fresh pwsh 啟動測試結果：四個模組（PSReadLine 2.4.5 / CompletionPredictor 0.1.1 / Terminal-Icons 0.11.0 / posh-git 1.1.0）皆載入；`prompt` function 被 oh-my-posh 注入；無錯誤輸出。

**踩到的坑：**
1. 第一版用 `Join-Path $env:POSH_THEMES_PATH ...`，但 winget MSIX 安裝沒設這個環境變數，導致 null binding 噴出 terminating error，連 else fallback 都沒跑。修法：profile 內顯式 set 該變數。
2. oh-my-posh v18+ 不再把 themes 嵌入 binary。必須額外下載 theme 檔到本地、或讓 `--config` 直接吃線上 URL（每次 shell 啟動會跑網路）。本實作選下載到 user-local，無網路依賴。

**Commit:** _待填_（M2 commit）

## Fallback 指引

若要把 M1 ~ M3 的變更整個 rollback：

```powershell
# 1) 移除 PSGallery 模組
Uninstall-Module Terminal-Icons -AllVersions -Force
Uninstall-Module posh-git        -AllVersions -Force

# 2) 移除 oh-my-posh
winget uninstall JanDeDobbeleer.OhMyPosh

# 3) profile 還原：刪除本輪追加的「Prettify」區塊
notepad $PROFILE
# 移除介於 "# === Prettify (M2) ===" 和 "# === /Prettify ===" 之間的內容即可
```

若只想 rollback 到 M1 完成、profile 尚未修改的狀態：直接 `git checkout <M1 commit hash> -- docs/progress-pwsh-fish-like.md` 並執行上面的 (1)(2)。
