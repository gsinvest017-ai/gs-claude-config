---
name: git-tag
description: 把當前 repo 路徑下「今日」commits 依 feature / fix / enhancement 分類成 milestone group，並在每個 group 的最後一個 commit 上下 annotated git tag。當使用者輸入 /git-tag、說「替今天的 commits 下 tag」、「把今天的 milestone 標起來」、「自動 tag feature/fix groups」、「幫我 tag 一下今天的版本」時啟動。預設 dry-run，需 `--apply` 才建立 tag；永遠不會 `--force` 覆蓋或主動 push（除非 `--push` 明確指定）。
---

# /git-tag — 每日 milestone tag 工

當使用者觸發時，把當天 commits 依分類切成 milestone group，並在每個 group 的最後一個 commit 上下 annotated tag。**全程繁體中文回報**。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `<YYYY-MM-DD>` | 今天 | 目標日期 |
| `--apply` | 否 | 真的建 tag（否則只 dry-run） |
| `--push` | 否 | 建好後 push 到 origin（必須先 `--apply`） |
| `--prefix <s>` | 無 | tag 名前綴（e.g. `v0.3-`） |
| `--repo <path>` | 當前目錄 | 指定 repo 路徑 |
| `--all-authors` | 否 | 否則只看自己（`git config user.name`）的 commits |

範例 args：
- `""` → dry-run 今天、當前 repo、自己
- `"--apply"` → 真建 tag
- `"2026-05-20 --apply --push"` → 指定日期 + apply + push
- `"--apply --prefix v0.3-"` → tag 前綴 `v0.3-feat/...`

## 1. 前置檢查

```bash
git rev-parse --is-inside-work-tree
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current)
TARGET_DATE=${ARG_DATE:-$(date +%Y-%m-%d)}
AUTHOR_FILTER=""
[ -z "$ALL_AUTHORS" ] && AUTHOR_FILTER="--author=$(git config user.name)"
```

PowerShell 等價：
```powershell
$TARGET_DATE = if ($ArgDate) { $ArgDate } else { Get-Date -Format yyyy-MM-dd }
```

## 2. 抓 commits（時間升冪）

```bash
git log --since="$TARGET_DATE 00:00" --until="$TARGET_DATE 23:59" \
  $AUTHOR_FILTER \
  --pretty=format:'%H%x09%h%x09%cI%x09%s' --reverse
```

回傳欄位：full hash / short hash / ISO time / subject。若無 commits → 回報「`$TARGET_DATE` 無符合條件的 commits」並停止。

## 3. 分類規則

依 commit message 標題（subject）前綴或關鍵字分到下列其一（**不分大小寫**）：

| 分類 | 對應關鍵字 |
|------|------------|
| `feat` | `feat`, `feature`, `add`, `implement`, `new`, `introduce` |
| `fix` | `fix`, `bugfix`, `hotfix`, `patch`, `correct`, `repair` |
| `enh` | `enhance`, `improve`, `refactor`, `perf`, `optimize`, `polish`, `tweak`, `rewrite`, `simplify`, `cleanup` |
| `skip` | `docs`, `chore`, `test`, `ci`, `build`, `deps`, `bump`, `style`, `merge`, `revert`, `wip` |

**特殊規則 — safe-yolo `Mn:` 鏈**：

- 標題以 `M<數字>:` 開頭 → 屬 safe-yolo milestone 系列
- 一連串 `Mn:` commit 視為**同一個 milestone group**，不能被分類規則拆開
- 整個 group 的分類用「最後一個 commit 的 body 判斷」；body 無線索則看「最後一個 commit 的標題去掉 `Mn:` 後的剩餘關鍵字」；都沒有就預設 `enh`
- group slug 也用最後一個 `Mn:` commit 的剩餘標題

## 4. 切 milestone group

依時間升冪掃 commits，連續同類合成 group：

1. 初始化空 group list
2. 對每個 commit：
   - 若是 `Mn:` → 與前一個 commit 是否也 `Mn:`？是 → 加入同 group；否 → 開新 `Mn:` group
   - 否則 → 與前一個 commit 同分類（feat/fix/enh）？是 → 加入；否 → 開新 group
   - `skip` 類：**不獨立成 group**。若前後都有非 skip group → 歸入前一個 group。若 group 開頭就是 skip → 暫存，等下一個非 skip commit 出現再合併。
3. 收尾：若 group 列表結尾有 skip-only 暫存區 → 丟棄（不獨立成 group，避免奇怪 tag）

範例：

```
時間升冪：
  c1 feat: add A
  c2 docs: README
  c3 feat: add B
  c4 fix: handle empty
  c5 M1: scaffold
  c6 M2: agent
  c7 M3: skill

→ groups:
  G1 [feat] c1 c2 c3      → tag on c3
  G2 [fix]  c4            → tag on c4
  G3 [enh from Mn 系列] c5 c6 c7  → tag on c7
```

## 5. 規劃 tag 名稱

對每個 group：

```
<prefix><category>/<YYYY-MM-DD>-<n>[-<slug>]
```

- `<prefix>`：使用者 `--prefix` 值，或空字串
- `<category>`：`feat` / `fix` / `enh`
- `<n>`：當天**該分類**第 n 個 group（per category 計數，從 1 起算）
- `<slug>` 規則：
  1. 從 group 最後一個 commit 標題擷取
  2. 去掉 `Mn:` / `feat:` / `fix:` 等前綴
  3. 轉成小寫，非 `[a-z0-9]` 字元替換為 `-`，連續 `-` 收成一個，去頭尾 `-`
  4. 截到最長 20 字
  5. 若結果為空字串 → 省略 `-<slug>` 部分

## 6. 衝突偵測

對每個規劃的 tag：

```bash
git tag -l '<name>'
```

若已存在：
- dry-run → 在計畫中標 `[exists, skip]`
- apply → 跳過該 group，最後彙總提示

## 7. Dry-run 輸出

**永遠先印計畫**（即使使用者加了 `--apply` 也先印一次再 apply）：

```
Repo: gs-claude-config   Branch: main   Date: 2026-05-21   Author: Kevin
共 7 個 commits，切成 3 個 milestone group：

[G1] feat  3 commits  →  tag `feat/2026-05-21-1-add-b`  on c3 (a1b2c3d)
       c1 a1b2c3d  feat: add A
       c2 b2c3d4e  docs: README
       c3 c3d4e5f  feat: add B

[G2] fix   1 commit   →  tag `fix/2026-05-21-1-handle-empty`  on c4 (d4e5f6a)
       c4 d4e5f6a  fix: handle empty

[G3] enh   3 commits  (Mn: chain) →  tag `enh/2026-05-21-1-skill`  on c7 (g7h8i9j)
       c5 e5f6g7h  M1: scaffold
       c6 f6g7h8i  M2: agent
       c7 g7h8i9j  M3: skill
```

若使用者**沒有** `--apply` → 結束於此，回報「Dry-run 完成；若無誤請加 `--apply` 重跑」。

## 8. Apply 階段（僅當 `--apply`）

對每個未衝突的 group：

```bash
git tag -a "<tag-name>" <full-hash> -m "<annotated message>"
```

Annotated message 格式：

```
<category>: <group 摘要 — 從各 commit subject 串接，截到 200 字>

Date: YYYY-MM-DD
Commits:
  - <short-hash> <subject>
  - ...
```

執行後印「✓ Created tag <name> on <short-hash>」一行一個。

## 9. Push 階段（僅當 `--apply --push`）

**重要**：push tags 會影響 remote，必須在計畫輸出和最後報告**雙重明示**。

```bash
git push origin --tags
```

push 完印每個 tag 對應的 remote ref 名（從 `git push --porcelain` 解析）。

## 10. 完成回報

3~5 行：

1. 「Dry-run 完成」或「建立了 N 個 tag」
2. tag 名稱清單（一行一個）
3. 衝突跳過清單（若有）
4. 「Tag 未 push；要 push 用 `git push origin --tags` 或下次加 `--push`」（若沒推）
5. 「已推到 origin」（若有推）

## 不要做的事

- ❌ 不要 `git tag --force` 或 `git tag -f`
- ❌ 不要在沒 `--apply` 時建任何 tag
- ❌ 不要主動 `git push --tags`（除非 `--push` 明確）
- ❌ 不要 `--force-push`（永遠不要）
- ❌ 不要把 skip 類 commit 獨立成 group
- ❌ 不要 tag 非當天 commit（即使日期算錯，照使用者給的日期跑）

## 邊界情況

- **當天只有 1 commit** → 仍可建 1 個 tag（單 commit 也是一個 milestone）
- **當天全是 skip** → 「無需 tag」並退出
- **detached HEAD** → 警告但允許繼續（git tag 本身允許）
- **完全空 repo（無 HEAD）** → 拒絕並退出
- **使用者指定未來日期** → 警告但仍嘗試（會找不到 commit 而退出）
- **同分類連續多個獨立任務**（例如兩個不相關的 feat 任務各 3 commit）→ 兩個會合在同一 group。此為限制；使用者若要分開，可下兩次：第二次指定範圍或事先 rebase 分隔。在 dry-run 報告底部加一行提示。

## 與其他 skill 的協作

- **`/daily-summary`**：今天的 changelog 路徑可放進 tag annotated message 的尾段
- **`/safe-yolo`**：`Mn:` commit 鏈會自動合成同一 group，tag slug 用最後一個 milestone 描述
- **GitHub release**：本 skill 不會建 release。需要時請手動跑 `gh release create <tag-name>`

## Windows 注意事項

- PowerShell 下 `date +%Y-%m-%d` 改用 `Get-Date -Format yyyy-MM-dd`
- `git tag -a ... -m "..."`：訊息含中文字時用 Git Bash 較穩；若用 PowerShell，多行訊息建議寫入暫存檔再用 `-F <file>`
- Tag 名不能含空白與這些字元：`:^~?*[` 等。slug 已過濾，但 prefix 由使用者提供，需在 dry-run 時 sanity-check
