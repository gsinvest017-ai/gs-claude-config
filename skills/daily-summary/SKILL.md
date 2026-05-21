---
name: daily-summary
description: 把當前 repo 路徑下「今日」git commits 與變更彙整成一份繁體中文 Markdown 日報。當使用者輸入 /daily-summary、說「彙整今天的 commits」、「生成 repo 日報」、「整理今日變更」、「summary 一下今天我做了什麼」時啟動。輸出檔名固定 `YYYY-MM-DD-summary.md`，內容含 commits 表、變更分類（feat / fix / refactor / docs / chore）、影響檔案統計、風險與後續建議。
---

# /daily-summary — Repo 今日變更彙整

當使用者觸發時，抓出當前 repo 當日所有 commits 與變更，彙整成一份**繁體中文** Markdown 日報。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析以下選項（皆可省略）：

| 參數 | 預設 | 說明 |
|------|------|------|
| `<YYYY-MM-DD>` | 今天 | 目標日期 |
| `--all-authors` | 否 | 抓全部 author（多人 repo 用） |
| `--repo <path>` | 當前目錄 | 指定 repo 路徑 |
| `--out <path>` | 自動 | 強制指定輸出路徑 |

範例 args：
- `""` → 今天、當前 repo、自己
- `"2026-05-20"` → 指定日期
- `"--all-authors --repo C:\path\to\repo"` → 切到指定 repo、抓所有作者

## 1. 前置檢查

```bash
# 確認 git repo
git rev-parse --is-inside-work-tree

# 取得 repo 名與 branch
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current)

# 決定日期
TARGET_DATE=${ARG_DATE:-$(date +%Y-%m-%d)}

# 決定 author 過濾
AUTHOR_FILTER=""
[ -z "$ALL_AUTHORS" ] && AUTHOR_FILTER="--author=$(git config user.name)"
```

PowerShell 等價：

```powershell
$REPO_NAME = (Split-Path -Leaf (git rev-parse --show-toplevel))
$BRANCH = (git branch --show-current)
$TARGET_DATE = if ($ArgDate) { $ArgDate } else { Get-Date -Format yyyy-MM-dd }
```

## 2. 抓 commits

```bash
git log --since="$TARGET_DATE 00:00" --until="$TARGET_DATE 23:59" \
  $AUTHOR_FILTER \
  --pretty=format:'%h%x09%ci%x09%s' --reverse
```

若無 commits → 回報「`$TARGET_DATE` 在 `$REPO_NAME` 無符合條件的 commits」並停止，**不產出空檔**。

## 3. 對每個 commit 收細節

```bash
git show --stat --format='%n=== %h ===%n%s%n%b%n--- files ---' <hash>
```

蒐集欄位：
- short hash、HH:MM 時間、標題、body（可能多行）
- 變更檔案清單、+/- 行數總計
- 受影響的目錄（前 2 層，例如 `src/foo`, `tests/`）

效率限制：
- 單一 commit 若變更 > 500 行，只摘要 top 5 檔案
- **絕對不要** 把完整 diff dump 到報告
- 若 commits 超過 30 個，僅在「Commits 一覽」表完整列出，分類詳述只展開 top 15（依變更行數排序）

## 4. 分類

按 commit message 標題前綴 / 關鍵字分到下列其一：

| 分類 | 關鍵字（不分大小寫） |
|------|----------------------|
| 新功能 | `feat`, `feature`, `add`, `implement`, `new` |
| 修復 | `fix`, `bugfix`, `hotfix`, `patch`, `correct` |
| 重構 | `refactor`, `rewrite`, `cleanup`, `simplify`, `reorganize` |
| 文件 | `docs`, `readme`, `comment`, `documentation` |
| 測試 / CI | `test`, `ci`, `chore`, `build`, `deps`, `bump` |
| 其他 | 無法判斷 |

特殊規則：
- `Mn:` 開頭（safe-yolo milestone 格式）→ 額外在「safe-yolo 任務群組」區塊顯示完整 milestone 鏈
- `Merge` / `Revert` → 不分類，獨立列出

## 5. 決定輸出路徑

優先順序：
1. 使用者 `--out` → 直接用
2. `docs/daily-summary/<TARGET_DATE>-summary.md`（若 `docs/daily-summary/` 存在）
3. `docs/<TARGET_DATE>-summary.md`（若 `docs/` 存在）
4. `<repo_root>/<TARGET_DATE>-summary.md`

若同名檔案已存在 → **預設覆寫**（這是工具型 skill，不要中斷使用者），但在報告開頭加 `> 覆寫於 HH:MM`。

## 6. 撰寫報告（繁體中文 Markdown）

```markdown
# YYYY-MM-DD Repo 變更摘要

> Repo: `<repo-name>` · Branch: `<branch>` · Author: `<author or 全部>` · 共 N 個 commits
> 產出時間：YYYY-MM-DD HH:MM

## ⚠️ 注意（僅在有未 commit 變更時出現）

```
M  path/to/file
?? path/to/new
```

## 一句話總結

<2~3 句話講今天主要做了什麼，能點出最有價值的變更與整體方向>

## Commits 一覽

| Hash | 時間 | 標題 | 分類 |
|------|------|------|------|
| abc1234 | 09:15 | M1: scaffold progress doc | 新功能 |
| def5678 | 14:30 | fix: handle empty git log | 修復 |

## 變更分類詳述

### 新功能

- **abc1234** `09:15` — M1: scaffold progress doc
  - 影響：`docs/progress-foo.md`（+46 / -0）
  - 重點：建立 foo task 的進度文件，定義 4 個 milestone

### 修復

- **def5678** `14:30` — fix: handle empty git log
  - 影響：`src/summary.py`（+12 / -3）
  - 重點：當當日無 commit 時改回報「無 commits」而不是丟 IndexError

<其餘分類同格式>

## safe-yolo 任務群組（若有）

### 任務 `<task-slug>` — M1 → M3 完整鏈
- M1: ... `abc1234`
- M2: ... `def5678`
- M3: ... `ghi9012`

## 影響檔案 Top 5

| 檔案 | 變更行數 | 出現於 commits |
|------|----------|----------------|
| `src/summary.py` | +120 / -45 | 3 |

## 風險與後續建議

- <若今日有大型 refactor、破壞性變更、未補測試的 fix、TODO 增加等，列出>
- <若 commits 全部是 WIP，提醒明天記得收尾>

## 明日待辦（若可推斷）

- 從進度檔的「## Mn — (in progress)」、未完的 milestone、commit body 中的 TODO 推斷
- 找不到就省略本節
```

## 7. 完成回報

用 3~5 行回給使用者：

1. 產出檔案絕對路徑
2. 今日 commits 數、總 +/- 行數
3. 一個重點亮點（從「一句話總結」拉一句）
4. 若有 ⚠️ 未 commit 變更，主動提醒

## 不要做的事

- ❌ 不要 `git push` / 開 PR / 修改原始碼
- ❌ 不要把完整 diff 內容塞進報告
- ❌ 不要在沒有 commits 時硬生出一份空報告
- ❌ 不要追問使用者；解析不到的參數用預設值

## 與其他 skill 的協作

- **`/save-to-obsidian`**：日報寫好後，建議使用者一鍵匯入 Obsidian vault 的 `工程筆記/` 子資料夾，方便累積成個人 changelog
- **`/safe-yolo`**：safe-yolo 任務的 `Mn:` commit 串會自動歸成完整 milestone 鏈，方便事後追任務進度

## Windows 注意事項

- PowerShell 下，`date +%Y-%m-%d` 不存在 → 用 `Get-Date -Format yyyy-MM-dd`
- 路徑分隔符以 PowerShell 為主（`\`），但 git 命令在 Git Bash / PowerShell 都吃 `/`
- 寫檔用 Write tool；如需手動寫 PowerShell，注意 `Out-File` 預設是 UTF-16，要加 `-Encoding utf8`
