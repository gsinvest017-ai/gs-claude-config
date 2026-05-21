# progress — /git-tag slash command

## 目標

新增一個 `/git-tag` slash command（搭配 subagent 定義），讓使用者在任何 git repo 路徑下執行後，會：

1. 抓出**當天**所有 git commits
2. 依分類（**feature / fix / enhancement**）把連續同類 commit 視為同一個 milestone group
3. 在每個 group 的 **final phase**（最後一個 commit）下一個 git tag
4. 預設只建本機 tag，**不** push（push 是不可逆 remote 操作，要 user 自己決定）
5. 預設先 dry-run 顯示要打的 tag，使用者確認後 / 加 `--apply` 才真的建立

## Tag 命名規範

格式：`<category>/<YYYY-MM-DD>-<n>[-<slug>]`

- `<category>`：`feat` / `fix` / `enh`（簡寫）
- `<n>`：當天該分類的第 n 個 group（從 1 起算）
- `<slug>`：可選，從 group 最後一個 commit 標題擷取的 kebab-case slug（≤ 20 字）

範例：
- `feat/2026-05-21-1-add-cli-flag`
- `fix/2026-05-21-1-handle-empty-log`
- `enh/2026-05-21-2-faster-stat`

若同名 tag 已存在 → 跳過該 group，提示使用者用 `git tag -d` 後重跑。

## 計畫 milestone

| M | 標題 | 預期產出 |
|---|------|----------|
| M1 | progress 骨架 | `docs/progress-git-tag.md`（本檔） |
| M2 | agent 定義 | `agents/git-tag.md`（subagent，model=sonnet） |
| M3 | slash command + skill | `commands/git-tag.md`、`skills/git-tag/SKILL.md` |
| M4 | README + smoke test | 更新 README；在本 repo 跑 dry-run 確認 tag 規劃合理 |

## 進度日誌

### M1 — progress 骨架 ✅

Commit: `143aed3`。

### M2 — agent 定義 ✅

寫 `agents/git-tag.md`：

- model: sonnet
- 分類：feat / fix / enh / skip（skip = docs/chore/test/...，不獨立成 group 但夾在 group 中仍歸入）
- safe-yolo `Mn:` 鏈視為一個 group（不被分類規則拆）
- 預設 dry-run，需 `--apply` 才建 tag；`--push` 才 push remote（push 視為影響 remote，要明示）
- annotated tag（`-a`）；不 `--force` 覆蓋

下一步：M3 — slash command + skill。

## Fallback 指引

若中途要 rollback：

```bash
git log --oneline --grep='git-tag'
git revert <commit-hash>   # 或 git reset --hard <pre-task-hash>
git tag --list 'feat/*' 'fix/*' 'enh/*' | xargs -r git tag -d  # 刪掉測試 tag
```

刪以下檔即完全回退：

- `agents/git-tag.md`
- `commands/git-tag.md`
- `skills/git-tag/SKILL.md`
- `docs/progress-git-tag.md`
- README.md 內 `git-tag.md` 條目
