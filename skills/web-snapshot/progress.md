# /web-snapshot 安裝進度

> 2026-05-26 / safe-yolo run
> Trigger: `/safe-yolo 安裝shot-scraper 並且把對網頁畫面截圖寫成system-global claude agent command "/web-snapshot"`

## 目標

讓任何 Claude Code session 都能用 `/web-snapshot <url>` 把網頁畫面截圖成 PNG 並存到本地。

## 計畫 milestone

| Milestone | 預期產出 | 狀態 |
|---|---|---|
| M1 | `shot-scraper` 與 Playwright Chromium 安裝完成、CLI 可用 | ✅ |
| M2 | `~/.claude/commands/web-snapshot.md` 寫好 | ✅ |
| M3 | 用實際 URL 跑通三種模式（full-page / viewport / selector） | ✅ |

## 進度日誌

### M1 — Install shot-scraper + chromium

- 環境發現：WSL2 / Python 3.12，系統 pip 是 **PEP 668 externally-managed**（無法直接 `pip install`）
- 採用 `pipx`（已預裝 1.4.3）裝 shot-scraper → `~/.local/bin/shot-scraper`
- 跑 `shot-scraper install` 把 Playwright Chromium 拉到 `~/.cache/ms-playwright/chromium-1223`
- 驗證：`shot-scraper https://example.com -o /tmp/example.png` → 寫出 1280x720 PNG（18KB）

無 commit（不在 git repo 內）。

### M2 — Write /web-snapshot command

- 路徑：`~/.claude/commands/web-snapshot.md`
- 格式對齊現有命令（frontmatter `description:` + `$ARGUMENTS` + 觸發範例 + 執行流程 + 邊界處理）
- 第一版引用了不存在的 shot-scraper 旗標（`--full-page`、`--jpeg`、`--wait-for` 當 CSS selector），看了 `shot-scraper shot --help` 後修正：
  - shot-scraper **預設就是整頁**；要 viewport-only 是傳 `-h <px>`（用 `--viewport-only` 包裝這個反直覺行為）
  - `--quality N` 設了就自動輸出 JPEG
  - `--wait-for` 吃 JS 表達式（非 CSS selector）
  - 加上「介面參數 → shot-scraper 旗標」對照表，讓 Claude 知道怎麼翻譯
- 預設輸出路徑：`~/Pictures/web-snapshot/<YYYYMMDD-HHMMSS>-<slug>.png`

無 commit（不在 git repo 內）。

### M3 — End-to-end smoke test

三個模式都跑通：

| 模式 | 指令 | 輸出 |
|---|---|---|
| 整頁（預設） | `shot-scraper https://example.com -w 1440` | 1440x720 PNG, 18KB |
| Viewport-only | `... -w 1440 -h 900` | 1440x900 PNG |
| Selector | `... -s "h1"` | 768x28 PNG（只截標題） |

並用 `Read` tool 預覽 PNG，確認 Claude 可在對話內直接顯示圖檔。

## Fallback / rollback

要移除整套工具：
```bash
pipx uninstall shot-scraper
rm -rf ~/.cache/ms-playwright   # 可選，會省 ~500MB
rm ~/.claude/commands/web-snapshot.md
rm ~/.claude/commands/web-snapshot.progress.md
```

要在新機器復現：
```bash
sudo apt install pipx           # 若沒裝
pipx install shot-scraper
shot-scraper install
# 然後把 web-snapshot.md 同步到該機器的 ~/.claude/commands/
```

## 已知 caveats

- 需要登入的頁要先跑 `shot-scraper auth <url> ~/.shot-scraper-auth.json`（互動式），再用 `--auth` 帶上
- SPA / lazy-load 頁可能截到白屏，要靠 `--wait` 或 `--wait-for "<js-expr>"` 處理
- Playwright chromium 約 500MB 佔在 `~/.cache/ms-playwright/`，是預期的
- shot-scraper 預設行為與 Playwright/Chrome headless 都不一樣（**預設整頁**，不是 viewport）；這在命令檔有醒目註記
