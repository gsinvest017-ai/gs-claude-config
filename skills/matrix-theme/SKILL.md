---
name: matrix-theme
description: 切換 PowerShell 終端機主題：駭客任務（Matrix 暗螢光綠）與原始配色（Campbell 多色）之間 toggle。當使用者輸入 /matrix-theme、說「切換駭客任務主題」、「換回原來配色」、「PowerShell 換主題」、「toggle matrix theme」時啟動。預設 toggle，可加 `matrix` 或 `original` 明確指定目標。
---

# /matrix-theme — PowerShell 主題切換

直接呼叫腳本處理，Claude 不需要手動讀寫任何設定檔。

## 腳本路徑

`C:\Users\User\.claude\scripts\Set-PsTheme.ps1`

## 執行方式

用 PowerShell tool 執行以下指令（依 args 決定參數）：

| args | 指令 |
|------|------|
| 空或 `toggle` | `pwsh -File "C:\Users\User\.claude\scripts\Set-PsTheme.ps1"` |
| `matrix` | `pwsh -File "C:\Users\User\.claude\scripts\Set-PsTheme.ps1" -Theme Matrix` |
| `original` | `pwsh -File "C:\Users\User\.claude\scripts\Set-PsTheme.ps1" -Theme Original` |

## 步驟

1. 依 args 組出指令
2. 用 PowerShell tool 執行（一行指令，不需要 Read/Edit 任何檔案）
3. 把腳本輸出的訊息直接回報給使用者，並提醒重開分頁或執行 `. $PROFILE` 套用

## 注意事項

- 腳本本身會偵測目前狀態並決定 toggle 方向，不需要 Claude 額外判斷
- 若腳本輸出「已經是 X 主題」表示無需切換，直接告知使用者即可
- Windows Terminal 設定即時生效（重開分頁），Profile 需執行 `. $PROFILE` 或重開分頁
