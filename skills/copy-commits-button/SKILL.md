---
name: copy-commits-button
description: 在當前專案 dashboard 的 panel 注入一個「📋 複製今日 commits」按鈕，按一下就把該 repo 當日 commits 以 markdown 格式寫進剪貼簿（含 safe-yolo Mn 鏈合併、分類、commit 列表），方便使用者貼到工作群組訊息。偵測 dashboard 載體（HTML / Streamlit / Gradio / Plotly Dash / React / Vue），可同時支援多 repo（一 repo 一 panel 一按鈕），自動接上後端 endpoint（若需要）。當使用者輸入 /copy-commits-button、說「dashboard 加複製按鈕」、「一鍵複製今日 commits」、「把當日 milestone 貼到群組」、「分享今天的 commit 到 chat」、「在 panel 上加 copy markdown 按鈕」時啟動。預設 dry-run，需 --apply 才改檔。
---

# /copy-commits-button — Dashboard 一鍵複製今日 commits（markdown）

當使用者觸發時，在**當前 repo** 的 dashboard panel 注入一個複製按鈕；按下後把當日 commits 以 markdown 寫進剪貼簿，使用者貼到 Slack / Teams / Discord / Line 群組就能直接呈現。全程繁體中文回報。

**預設 dry-run**（只印計畫 + markdown sample）；需 `--apply` 才改檔。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--target <auto\|html\|streamlit\|gradio\|dash\|react\|vue>` | `auto` | dashboard 載體 |
| `--file <path>` | 無 | dashboard 入口檔（auto 找不到時指定） |
| `--repos <path,...>` | 當前 repo | 要列入的 repo 路徑清單；多個 → 一 repo 一 panel 一按鈕 |
| `--api-path <p>` | `/api/today-commits` | 後端 endpoint 路徑（HTML 載體用） |
| `--style <github\|slack\|plain>` | `github` | markdown 風格（mrkdwn 給 Slack；GitHub 給 Teams/Discord/Issue） |
| `--placement <new-panel\|each-panel\|toolbar>` | `new-panel` | new-panel=新建「今日 commits」面板；each-panel=既有每個 repo panel 加按鈕；toolbar=全域工具列一顆 |
| `--milestone-mode <chain\|individual>` | `chain` | `Mn:` 鏈合併為一段 / 逐 commit 列出 |
| `--all-authors` | 否 | 否則只取自己（`git config user.name`）的 commits |
| `--apply` | 否 | 真的改檔 |

範例 args：
- `""` → auto + new-panel + github + chain，印 dry-run
- `"--apply"` → 套用
- `"--repos . --apply"` → 只當前 repo
- `"--repos C:\Users\User\autogo,C:\Users\User\gs-claude-config --placement each-panel --apply"` → 兩個 repo 各自 panel
- `"--style slack --apply"` → mrkdwn 給 Slack

## 1. 前置檢查 — 偵測 dashboard 載體

掃描入口：

| 載體 | 偵測訊號 |
|------|---------|
| **HTML 直發** | `dashboard.html` / `index.html` + 後端 (`*app*.py`/`server.{js,ts}`/Flask/FastAPI/Express) |
| **Streamlit** | `*.py` 含 `import streamlit`、`st.set_page_config` |
| **Gradio** | `gr.Blocks`、`gr.Row` |
| **Plotly Dash** | `dash`、`html.Div`、`dcc.Graph` |
| **React / Vue** | `*.jsx` / `*.tsx` / `*.vue` 中的 dashboard 元件 |

**autogo 專案特記**：若偵測到 `C:\Users\User\autogo\web\{app.py,dashboard.html,static/dashboard.js}` → 入口 `web/dashboard.html`、後端 `web/app.py`（Flask/FastAPI）、JS 在 `web/static/dashboard.js`。

找不到 → 提示 `--file <path>` 並停止。

## 2. 收集今日 commits（每個 `--repos` 各跑一次）

```bash
git -C <repo> log \
  --since="YYYY-MM-DD 00:00" --until="YYYY-MM-DD 23:59" \
  [--author="$(git config user.name)"] \
  --pretty=format:'%H%x09%h%x09%cI%x09%s' --reverse
```

接著套用**`Mn:` chain 合併規則**（與 `/git-tag` 同一套，確保兩者一致）：

- 連續 `Mn:` 視為同一個 milestone group
- **N 重設**（current N ≤ previous N，例如 M3→M1）→ 切新 group
- 非 `Mn:` commits 依 feat / fix / enh / skip 分類，連續同類合一 group
- skip 類（docs/chore/test/…）不獨立成 group，附在前一個 group 後

`--milestone-mode chain` → 用 group 為單位輸出；`individual` → 逐 commit 輸出。

## 3. Markdown 格式（依 `--style`）

### GitHub style（預設，適用 Teams / Discord / Issue / PR）

```markdown
**[<repo>] 2026-05-28** · <N> commits / <G> milestones

**🎯 feat — <group 摘要>** (3 commits)
- `79f66e5` M1: add /one-button-launch skill + progress doc
- `6c6b6d5` M2: add /platform-compatible skill
- `16f040f` M3: verify ... finalize progress

**🔧 fix — <group 摘要>** (1 commit)
- `d4e5f6a` fix: handle empty
```

emoji 對應：feat `🎯` / fix `🔧` / enh `✨` / Mn-chain `🪜`。

### Slack style（mrkdwn）

```
*[<repo>] 2026-05-28* · <N> commits / <G> milestones

:dart: *feat — <group 摘要>* (3 commits)
• `79f66e5` M1: add /one-button-launch skill + progress doc
• `6c6b6d5` M2: add /platform-compatible skill
• `16f040f` M3: verify ... finalize progress
```

注意：Slack mrkdwn 用 `*粗體*`（單星號）、無語法高亮的程式碼用反引號。

### Plain（純文字 fallback）

無格式標記，純文字 + emoji，給不支援 markdown 的 IM。

當日**無 commits** → markdown 為 `[<repo>] 2026-05-28 — 今日無 commits`。

## 4. 後端 endpoint（HTML/JS 載體需要；Streamlit 不需要）

選擇規則：
- 找到既有 server 檔（Flask `@app.route` / FastAPI `@app.get` / Express `app.get`）→ **追加** 新 route，不動既有 endpoint
- 無 server → 提示需要起一個（提示用 `/one-button-launch` 或手動）

route 範例（FastAPI）：

```python
# <!-- BEGIN copy-commits-button -->
from fastapi import Query
from typing import Optional
import subprocess, datetime

@app.get("<api-path>")
def today_commits(repo: str = Query(...), date: Optional[str] = None,
                  style: str = "github", all_authors: bool = False):
    d = date or datetime.date.today().isoformat()
    # validate repo against allowlist; reject path traversal
    ...
    # git log + Mn: group merge + render markdown
    return {"date": d, "repo": repo, "markdown": text, "groups": [...]}
# <!-- END copy-commits-button -->
```

**安全**：
- `repo` 必須在白名單（從 `--repos` 帶入）；拒絕 `..`、絕對路徑跳脫
- 不接受任意 git arg；只接 date / style / all_authors
- 不暴露 commit body 或檔案內容，只 subject + hash + author

## 5. 前端按鈕注入（依 `--placement`）

### `new-panel`（預設）
在 dashboard 容器頂端 / 側邊新增「📋 今日 commits」panel，每個 repo 一張卡，每卡有：
- repo 名 + 日期
- commit / milestone 摘要（折疊或前 5 筆預覽）
- **[複製] 按鈕**（按下 `navigator.clipboard.writeText(markdown)` + toast「已複製」2 秒）

### `each-panel`
對既有有 `data-repo` 屬性（或可推斷 repo 的）的每個 panel 加一個小複製按鈕。若既有 panel 沒有 repo 識別 → 提示加 `data-repo` 標記或退回 `new-panel`。

### `toolbar`
dashboard toolbar / header 加一個全域按鈕，複製「所有 `--repos` 合併」的 markdown。

### 共通實作（Vanilla JS / 框架皆同）

```js
async function copyTodayCommits(repo) {
  const r = await fetch(`<api-path>?repo=${encodeURIComponent(repo)}&style=<style>`);
  const data = await r.json();
  await navigator.clipboard.writeText(data.markdown);
  showToast(`已複製 ${repo}`);
}
```

**HTTPS / clipboard 限制**：`navigator.clipboard.writeText` 只能在 secure context（HTTPS 或 `localhost`）跑。若 dashboard 部署在 plain HTTP 域名 → 提供 fallback：開一個 `<textarea>` + `document.execCommand('copy')`，並在 panel 顯示警告。

### Streamlit 變體

無前後端分離，直接：

```python
import streamlit as st
md = render_today_commits(repo, style=...)
st.code(md, language="markdown")
# 注入 JS 抓 markdown 寫剪貼簿
st.components.v1.html(f"""
  <button onclick="navigator.clipboard.writeText({md!r}); ...">📋 複製</button>
""", height=40)
```

## 6. 寫檔 / 套用（僅當 `--apply`）

- **後端**：在 server 檔內以 `# <!-- BEGIN copy-commits-button -->` / `# <!-- END -->` 區塊標記插入 route，不動既有 endpoint
- **前端**：HTML 注入新 panel（同樣用標記）；JS 加 handler；CSS 走既有主題 class
- **每個檔改完印 diff 摘要**
- 不改 data / 商業邏輯
- **保留人工內容**：再次跑本 skill 只更新標記內

## 7. 驗證

- 後端：`curl <base>/api/today-commits?repo=<allowed-path>` 看 JSON
- 前端：若有 Chrome DevTools / Playwright MCP → navigate、`evaluate_script` 觸發 click、讀 `navigator.clipboard.readText()` 比對 markdown
- 否則：列出注入位置 + sample markdown，請使用者目視 + 手動點

## 8. 完成回報

3~5 行：
1. 偵測到的 dashboard 載體與檔
2. 注入的按鈕位置與數量（依 placement）
3. markdown 風格、是否合併 Mn: 鏈
4. 後端 endpoint 路徑（若有）+ 驗證結果
5. 後續建議（部署若為 HTTP 需 HTTPS / 或加 fallback）

## 不要做的事

- ❌ 沒 `--apply` 就改檔
- ❌ 把 commits 內容 **inline 進 HTML**（一刷新就過時）；一律走 API / Streamlit server-side
- ❌ endpoint 接受任意 repo path（會變成資料外洩）；只認 `--repos` 白名單
- ❌ 寫死作者 = 使用者；支援 `--all-authors`
- ❌ 砍既有 panel / 改既有 endpoint；只**新增**
- ❌ 把 commit body / 檔案內容 / secrets 放進 markdown 推到 chat
- ❌ 預設用 Slack `@here` / `@channel` 等通知 token（永遠不要自動帶）

## 邊界情況

- **當日無 commits** → 按鈕仍存在，markdown 為「今日無 commits」（給使用者明確訊號）
- **多個 repo** → `new-panel` 一卡一 repo + 一個「複製全部」按鈕；`toolbar` 預設複製合併
- **非 secure context（HTTP）** → 自動加 `<textarea>` + `execCommand('copy')` fallback，並在 console + UI 顯示「建議改 HTTPS」
- **Repo 不是 git repo** → 跳過該 repo 並在 markdown 加註記
- **commit message 含特殊字元**（反引號 / 中文 / emoji） → markdown 用 backtick 包 hash，subject 直接放原文（UTF-8），不額外 escape，由 chat 端 mrkdwn / GFM 處理
- **時區**：以使用者本地時區判定「今日」；endpoint 可選 `?date=YYYY-MM-DD` 覆寫

## 與其他 skill 協作

- **`/git-tag`**：共享 `Mn:` chain 合併與分類規則（同一套邏輯）
- **`/daily-summary`**：複製出來的內容是 daily-summary 的精簡 chat 版；可在 markdown 末段附 daily-summary 路徑
- **`/ui-compact`**：注入新 panel 後跑 `/ui-compact` 確認沒撐破 viewport
- **`/one-button-launch`**：dashboard 需起服務才能驗證 endpoint
- **`/platform-compatible`**：JS / Python clipboard 處理在不同瀏覽器都要可用

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/copy-commits-button/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入。
