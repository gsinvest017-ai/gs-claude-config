# 進度：撰寫「commit message 用繁體中文寫」spec

## 目標

在全域 `~/.claude/CLAUDE.md`（= `gs-claude-config/CLAUDE.md`）的 `# Behavior rules` 區段新增第 3 條 cross-repo 規則：要求 Claude 之後在所有 repo 觸發 `git commit` 時，**訊息主體（subject + body 描述句）用繁體中文撰寫**，技術識別符 / prefix / git trailer 保留原文。本規則為被動 / always-on 的 behavior rule，不是 slash command。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + 在 CLAUDE.md 加第 3 條規則 | `docs/progress-zh-commit-message-spec.md`、`CLAUDE.md` 改動 |
| **M2** | 驗證 + 收尾 | 規則在全域 CLAUDE.md 內、進度檔最終段、commit 範圍記錄 |

**本任務的 commit message 從 M1 起即用繁體中文寫**（dogfood 新規則）。

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 在 CLAUDE.md 新增第 3 條規則

- 把 `# Behavior rules` 區段開頭「**兩**條 cross-repo 規則」改為「**三**條」。
- 在第 2 條後追加第 3 條：「**Git commit message 的主體用繁體中文撰寫**」。內容涵蓋：
  - 適用範圍：所有由 Claude 觸發的 `git commit`（safe-yolo `Mn:` 鏈、單發 `feat:` / `fix:` 等、merge / revert 皆同）
  - 保留原文清單：commit prefix、git trailer、技術識別符、英文錯誤訊息引用
  - 格式：subject ≤ 72 字（不含 prefix），維持 safe-yolo「不要寫小說」原則
  - 例外：純工具自動產生的 commit（dependabot、auto-merge）、他人撰寫的 commit 不改
  - **Why**：使用者母語為繁中、commit log 由本人 review、與 `/git-tag` / `/daily-summary` / `/copy-commits-button` 中文輸出語感一致
  - **How to apply**：寫前先想中文版主體；不確定該不該翻譯的（stack trace / API 路徑）原樣保留並用中文做框架說明
- 本任務從本 commit 起，**commit message 即以繁體中文寫**（dogfood）。
- 兩檔正規化為 CRLF。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`，分支 `main`。
- Rollback：`git log --oneline` 找 `M1:` / `M2:`，`git reset --hard <hash>` 即可。
- 整個撤掉：把 CLAUDE.md 改回原本「兩條」，刪本進度檔，`git checkout -- .`。
