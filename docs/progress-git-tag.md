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

### M3 — slash command + skill ✅

- `commands/git-tag.md`：精簡入口，含觸發範例與精簡流程
- `skills/git-tag/SKILL.md`：完整規範，含分組演算法、slug 規則、Windows 注意事項；CRLF 已套用
- Claude Code 自動偵測到 `git-tag` skill（system-reminder 確認）

下一步：M4 — README + smoke test。

### M4 — README + smoke test ✅

**README**：目錄樹新增 `git-tag.md` / `git-tag/SKILL.md`

**Smoke test 發現 bug → 修正**：

在本 repo 跑 `git log --since="2026-05-21 00:00"` 後發現今天有兩串 `Mn:` 鏈（daily-summary 的 M1..M4 + git-tag 的 M1..M3）。原本的「連續 Mn 視為同 group」會把它們合成一個 group，這顯然不對。

修正：加入「**N 重設則切新 group**」規則（M4 → M1 = 新任務開始）。SKILL.md 與 agents/git-tag.md 都已同步更新。

**預期 dry-run 結果**（不真的執行，避免污染 tag 命名空間）：

```
[G1] feat  4 commits  →  feat/2026-05-21-1-link-daily-summary-in  on aa4f178
       b3455b3  M1: scaffold progress doc for /daily-summary command
       579d0d0  M2: add daily-summary subagent definition
       3dc089c  M3: add /daily-summary slash command + skill
       aa4f178  M4: link /daily-summary in README + smoke-test git query
[G2] feat  3+1 commits  →  feat/2026-05-21-2-add-git-tag-slash-co  on <M4 of git-tag>
       143aed3  M1: scaffold progress doc for /git-tag command
       6498e9b  M2: add git-tag subagent definition
       52f1fb3  M3: add /git-tag slash command + skill
       <M4-hash>  M4: README + smoke test for /git-tag
```

兩個 group 都分到 `feat`（chain 內多次出現 "add" 關鍵字）。

## 完成總結

- 4 commits（M1 ~ M4）建立 `/git-tag` slash command
- 觸發後抓今日 commits → 分類成 feat/fix/enh group → 在每 group 最後一個 commit 下 annotated tag
- 預設 dry-run；`--apply` 才建 tag；`--push` 才推 remote（雙重明示）
- 不會 force 覆蓋已存在 tag，不會 force-push
- 支援 safe-yolo `Mn:` 鏈自動偵測（含 N 重設切 group）

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
