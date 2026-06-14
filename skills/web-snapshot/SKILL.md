---
name: web-snapshot
description: 對指定 URL 的網頁畫面截圖並存 PNG 到本地。當使用者輸入 /web-snapshot <url>、說「幫我截這個網頁」、「對網頁截圖」、「screenshot 這個 URL」、「把這頁存成圖」、「web screenshot」等情境啟動。底層走 shot-scraper（Playwright + Chromium headless），支援整頁/viewport-only/CSS selector 三種模式，預設輸出到 ~/Pictures/web-snapshot/。
---

# /web-snapshot — 網頁截圖工具

呼叫 `shot-scraper` 對指定 URL 的網頁截圖並輸出 PNG。預設輸出到 `~/Pictures/web-snapshot/YYYYMMDD-HHMMSS-<slug>.png`。

**使用者請求**：$ARGUMENTS

## 觸發範例

```
/web-snapshot https://example.com
/web-snapshot https://news.ycombinator.com -o ~/Desktop/hn.png
/web-snapshot https://github.com --viewport-only            # 只截可視範圍，不要整頁
/web-snapshot https://example.com --selector "#main"        # 只截某元素
/web-snapshot https://dashboard.example.com --width 1920 --viewport-only --wait 3000
/web-snapshot https://example.com --quality 70              # 改存 JPEG（檔名自動 .jpg）
/web-snapshot https://example.com --js "document.body.style.background='black'"
/web-snapshot https://example.com --retina                  # HiDPI 2x
```

## 參數解析

從 `$ARGUMENTS` 取出（這層是給 Claude 看的介面；底下會轉成正確的 shot-scraper 旗標）：

| 介面參數 | 說明 | 預設 | → shot-scraper 旗標 |
|------|------|------|------|
| `<url>` | 必填，第一個非旗標 token；沒 scheme 自動補 `https://` | — | 直接傳 |
| `-o` / `--output <path>` | 輸出路徑；副檔名決定格式（`.png` / `.jpg`） | 預設規則見下 | `-o` |
| `--selector <css>` | 只截某個 CSS selector 對應的元素 | — | `-s` |
| `--viewport-only` | 只截可視範圍（不抓 scroll 之外的部分） | 不指定就整頁 | 傳 `-h <height>` 限制 |
| `--width <px>` | viewport 寬（shot-scraper 預設 1280） | `1440` | `-w` |
| `--height <px>` | viewport 高，**指定就會變 viewport-only** | 不傳 → 整頁 | `-h` |
| `--wait <ms>` | DOM ready 後額外等待時間 | — | `--wait` |
| `--wait-for <js>` | 等到該 JS 表達式回 true 才截（例：`document.querySelector('.loaded')`） | — | `--wait-for` |
| `--js <code>` | 截圖前注入 JS | — | `-j` / `--javascript` |
| `--quality <0-100>` | 設了就會輸出 JPEG | — | `--quality` |
| `--scale-factor <n>` | device pixel ratio | — | `--scale-factor` |
| `--retina` | 等同 `--scale-factor 2` | — | `--retina` |
| `--auth <file>` | shot-scraper auth JSON（登入態） | — | `-a` |
| `--user-agent <ua>` | 自訂 UA | — | `--user-agent` |
| `--timeout <ms>` | 整體 timeout（預設 30000） | — | `--timeout` |

slug = 從 URL host + path 取主要部分，kebab-case ≤ 30 字（例：`https://news.ycombinator.com/item?id=1` → `news-ycombinator-com-item`）。

> **shot-scraper 的整頁/viewport 行為很反直覺**：它預設就會抓**整頁高度**，不是只抓 viewport。要限制成「只截可視範圍」，必須傳 `-h <px>`。`/web-snapshot` 用 `--viewport-only`（自動套 `-h <--height|900>`）來提供比較好懂的介面。

slug = 從 URL host + path 取主要部分，kebab-case ≤ 30 字（例：`https://news.ycombinator.com/item?id=1` → `news-ycombinator-com-item`）。

## 執行流程

1. **健檢 shot-scraper 是否就緒**
   ```bash
   command -v shot-scraper >/dev/null 2>&1 || command -v ~/.local/bin/shot-scraper >/dev/null 2>&1
   ```
   找不到就：
   ```bash
   pipx install shot-scraper && shot-scraper install
   ```
   （若 `pipx` 也沒有，提示使用者 `sudo apt install pipx` 後重試，不要硬上 `pip install --break-system-packages`。）

2. **解析 `$ARGUMENTS`**：拆出 URL + 各旗標。URL 沒 scheme 補 `https://`。

3. **算輸出路徑**：
   - 使用者有給 `-o` 就尊重它（必要時 `mkdir -p` 父資料夾）。
   - 沒給就用預設規則：
     ```bash
     mkdir -p ~/Pictures/web-snapshot
     ts=$(date +%Y%m%d-%H%M%S)
     out=~/Pictures/web-snapshot/${ts}-${slug}.png
     ```

4. **組合 shot-scraper 指令**並執行（注意旗標名）：
   ```bash
   shot-scraper "<url>" -o "<out>" \
       -w 1440 \
       [-h <height>]              # 有給 --viewport-only 或 --height 才加
       [-s "<selector>"] \
       [--wait 2000] [--wait-for "<js-expr>"] \
       [-j "<js-code>"] \
       [--quality 80]             # 設了就輸出 JPEG，輸出路徑副檔名應為 .jpg
       [--retina | --scale-factor 2] \
       [-a ~/.shot-scraper-auth.json] [--timeout 60000]
   ```
   shot-scraper 預設整頁；要 viewport-only 就傳 `-h`（介面用 `--viewport-only` → 預設 `-h 900`，或使用者用 `--height` 覆寫）。

5. **驗證輸出**：執行完用 `file "<out>"` 確認為 `PNG image data` 或 `JPEG image data`，並印檔案大小。

6. **回報結果**（簡短 3~5 行）：
   - 輸出路徑（絕對路徑）
   - 解析後尺寸（width × height，可從 `file` 輸出讀）
   - 檔案大小
   - 若使用者在 Claude Code 環境內，**用 Read tool 預覽該 PNG** 讓他在對話內直接看到

## 失敗排查

| 現象 | 處理 |
|------|------|
| `shot-scraper: command not found` | 嘗試 `~/.local/bin/shot-scraper`；都沒有則照「健檢」步驟安裝 |
| `Executable doesn't exist at ... chrome-linux/chrome` | 跑 `shot-scraper install` 把 playwright chromium 補齊 |
| `net::ERR_NAME_NOT_RESOLVED` / `ERR_CONNECTION_REFUSED` | URL 不可達，請使用者確認連線 / VPN / 是否要 `--auth` |
| 頁面是 SPA、截到白屏 | 加 `--wait 3000` 或 `--wait-for ".some-loaded-class"` |
| 需要登入 | 引導使用者跑 `shot-scraper auth <url> ~/.shot-scraper-auth.json`（互動式登入存 cookie），下次截圖加 `--auth ~/.shot-scraper-auth.json` |
| 看到 `Timeout 30000ms exceeded` | 加 `--timeout 60000` 或設 `--wait-for "<js-expr>"` 等待具體訊號 |

## 不要做的事

- **不要** 在系統 Python 用 `pip install --break-system-packages`（這台是 PEP 668 externally-managed）。一律走 pipx。
- **不要** 覆寫已存在的輸出檔而不提示；偵測到同名檔時在檔名加 `-2`、`-3`…後綴。
- **不要** 把 PNG 存進 git repo 的工作目錄裡；預設目錄是 `~/Pictures/web-snapshot/`，除非使用者明確 `-o` 指到 repo 內。
- **不要** 沒有 `--auth` 就嘗試截需要登入的頁；先警告使用者該頁可能要 auth flow。

## 邊界情況

- 沒給 URL → 印用法後停止
- URL 是 `file://...` 或本地 HTML → shot-scraper 也支援，直接傳即可
- 使用者一次給多個 URL → 逐一截，輸出檔名各自帶 slug
- 在沒有 X server 的 WSL/伺服器 → shot-scraper 用 headless chromium，**不需要** DISPLAY；不用裝 xvfb
