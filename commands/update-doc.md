---
description: 把當前 repo 的 doc-site 更新到最新 commit 對應的狀態（MkDocs / Docusaurus / VitePress / Jekyll）
---

你要執行 `/update-doc` 工作流。完整指示在 `~/.claude/skills/update-doc/SKILL.md`。

**使用者參數（可能為空）**：$ARGUMENTS

## 重點摘要

1. **偵測**：跑 `git rev-parse --show-toplevel` + `git log --oneline -20` + `git status --short`，識別 doc-site 框架（`mkdocs.yml` / `docusaurus.config.*` / `.vitepress/config.*` / `_config.yml`），找出 docs 目錄。
2. **找變動**：`git log <last_doc_commit>..HEAD -- ':(exclude)docs-site/' ':(exclude)docs/'` 撈出非 doc commit 變動，歸納成「需要 doc 更新領域」。
3. **strict build**：跑 `mkdocs build --strict`（或對應框架的 build），先把 build error 修掉。
4. **提案更新頁面**：依 step 2 的變動清單，列出哪幾頁該改（不要亂改，先 propose）。常見：
   - `src/<module>/*.py` 大改 → 對應 `docs-site/<topic>/*.md`
   - 新增 CLI flag → `docs-site/ops/*.md`
   - schema migration → `docs-site/db/schema.md`
5. **regen 自動產物**：repo 內有 `gap_report.py` / `coverage_report.py` / 類似 dashboard 產生器就跑一遍，把產出 mirror 進 docs-site/。
6. **changelog**：更新 `docs-site/changelog.md` 若存在，把上次 commit 後重要變動寫一段。
7. **commit**：`git add docs-site/ mkdocs.yml && git commit -m "docs: refresh doc-site to match HEAD ($(git rev-parse --short HEAD))"`。
8. **回報**：3-5 行報告 commit 範圍、改的頁、build 結果、是否要 push。

## 安全

- 別覆蓋未 commit 的 dirty changes — 先 stash 或停下
- 別自動 `git push` 除非使用者說了「上線 / push / deploy」
- 別砍 nav 條目 / 動產品決策內容；只做基於最近 commit 的最小更新
- 若 repo 內有 `.claude/agents/<doc-*>.md`，先尊重那個 agent；本 skill 是 fallback

詳細決策樹、框架對照表、scaffold 路徑都在 `~/.claude/skills/update-doc/SKILL.md`。
