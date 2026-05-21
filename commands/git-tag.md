---
description: 把當天 commits 依 feature/fix/enhancement 分段，在每個 milestone 最後一個 commit 下 annotated git tag
---

# /git-tag — 每日 milestone tag 工

抓當前 repo **今天**的所有 commits，依分類（feat / fix / enh）把連續同類 commit 合成 milestone group，並在每個 group 的最後一個 commit 上下 annotated git tag。

**使用者請求**：$ARGUMENTS

## 觸發範例

```
/git-tag                          # dry-run 印計畫（預設今天）
/git-tag --apply                  # 真的建 tag（先印計畫再執行）
/git-tag 2026-05-20 --apply       # 指定日期
/git-tag --apply --push           # 建 tag + 推到 origin（會影響 remote！）
/git-tag --apply --prefix v0.3-   # 加自訂前綴：v0.3-feat/...
```

## Tag 命名

```
<prefix><category>/<YYYY-MM-DD>-<n>[-<slug>]
```

- `<category>`：`feat` / `fix` / `enh`
- `<n>`：當天該分類第 n 個 group
- `<slug>`：從 group 最後一個 commit 標題擷取（kebab-case，≤ 20 字），可省略

範例：`feat/2026-05-21-1-add-cli-flag`、`fix/2026-05-21-1-handle-empty-log`

## 流程（精簡版，完整規範見 `skills/git-tag/SKILL.md`）

1. 抓今日 commits（`git log --since=... --until=...`）
2. 分類：feat / fix / enh / skip
3. 切 milestone group（連續同類合併；`Mn:` 鏈視為同一 group；skip 類夾在中間仍歸該 group）
4. 規劃 tag 名稱 + 衝突偵測（已存在則跳過）
5. **預設 dry-run** 印計畫 → 沒加 `--apply` 就停在這裡
6. `--apply`：跑 `git tag -a <name> <hash> -m <msg>`
7. `--push`：`git push origin --tags`（影響 remote，會在報告中明示）

## 不會做的事

- 不會 `--force` 覆蓋已存在的 tag
- 不會在沒 `--apply` 時建任何 tag
- 不會主動 push（除非 `--push` 明確指定）
- 不會把 docs/chore/test 等 skip 類 commit 獨立成 group

## 邊界情況

- 當天無 commit → 回報並停止
- 當天全是 skip 類 → 告訴使用者「無需 tag」
- 同名 tag 已存在 → 跳過該 group（不 force 覆蓋）
- detached HEAD → 警告但仍可建 tag
