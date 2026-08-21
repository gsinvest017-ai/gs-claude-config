---
name: compress-video
description: 把指定影片用 ffmpeg two-pass 壓縮到 10MB（或指定大小）以下。當使用者輸入 /compress-video <路徑>、說「幫我壓縮這個影片」、「把 <檔案> 壓到 10MB 以下」、「影片太大 LINE/Slack 傳不出去」時啟動。
---

# /compress-video — ffmpeg two-pass 影片壓縮

## 觸發條件

- `/compress-video <檔案路徑>`
- 「幫我把這個影片壓到 10MB 以下」
- 「<檔案> 太大傳不出去，幫我壓縮」
- 「影片壓縮到 <N>MB」（自訂目標大小）

## 執行步驟

### 1. 解析參數

從使用者輸入取得：
- `InputPath`（必填）：影片路徑，含空白請用雙引號包住
- `TargetMB`（選填，預設 10）：目標大小（MB）
- 若使用者沒給路徑，直接詢問

### 2. 執行壓縮腳本

用 PowerShell tool 執行：

```powershell
& "C:\Users\User\.claude\skills\compress-video\scripts\Compress-Video.ps1" `
    -InputPath "<路徑>" `
    -TargetMB <目標MB>
```

### 3. 回報結果

顯示腳本輸出（原始大小、壓縮後大小、輸出路徑）。

若結果仍超標（腳本會印 Warning），提示使用者加上解析度縮放：
```powershell
ffmpeg -y -i "<輸入>" -vf scale=1280:-2 `
    -c:v libx264 -b:v <videoKbps>k -c:a aac -b:a 128k "<輸出>"
```
（直接算好 bitrate 告訴使用者，不要叫他自己算）

## 常見情境快查

| 使用者說 | 對應參數 |
|---|---|
| `/compress-video C:\…\demo.mp4` | TargetMB=10（預設） |
| 「壓到 8MB」 | -TargetMB 8 |
| 「LINE 傳不出去」 | -TargetMB 24（LINE 上限 25MB） |
| 「Slack 傳不出去」 | -TargetMB 9（Slack 免費版 10MB 留 buffer） |

## 前置需求

- ffmpeg + ffprobe 在 PATH：`winget install Gyan.FFmpeg`
- 或 `pip install imageio-ffmpeg` 並手動把 binary 加到 PATH

## 注意事項

- 輸出預設為 `<原檔名>_compressed.<副檔名>`，放在同一目錄
- Two-pass passlog 寫到 `$env:TEMP`，腳本執行完自動清除
- 若影片極短（< 1秒）或極長導致 bitrate 計算為負，腳本會直接報錯並說明原因
