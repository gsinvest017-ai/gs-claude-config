---
name: update-doc
description: 把當前 repo 的文檔網站（MkDocs / Docusaurus / VitePress）更新到最新 commit 對應的狀態。當使用者輸入 /update-doc、說「更新文檔網站」、「文件 / docs site 過時了」、「最新 commit 反映進去 doc site」、「rebuild docs after merge」等情境啟動。會：(1) 掃 git log 找出上次 docs 更新後到現在的 commits；(2) 跑 strict build；(3) 列出哪些 doc 頁該根據 diff 更新（不亂改，先提案）；(4) 若有 dashboard / 自動產生產物（gap_dashboard / coverage report）就 regen；(5) commit + 可選擇 push。能在沒有現成 doc site 的 repo 上幫忙 scaffold。
---

# /update-doc — Doc site refresh from latest commits

當使用者輸入 `/update-doc [optional scope hint]`，把當前 repo 的文檔網站更新到反映最新 git 狀態。

## 第一步：偵測 repo 狀態

跑這些 read-only 探測，**不要**先動任何檔：

```bash
pwd                                      # 確認 working dir
git rev-parse --show-toplevel             # 確認 repo root
git log --oneline -20                     # 看最近 commits
git status --short                        # 看 dirty changes
```

判斷 doc site 框架：

| 偵測檔 | 框架 |
|---|---|
| `mkdocs.yml` / `mkdocs.yaml` | **MkDocs**（最常見） |
| `docusaurus.config.js` / `docusaurus.config.ts` | Docusaurus |
| `.vitepress/config.{js,ts,mts}` | VitePress |
| `_config.yml` 且有 `theme:` | Jekyll |
| 都沒有 | **未 scaffold** — 走 scaffold 路線 |

判斷 doc 目錄：MkDocs 從 `mkdocs.yml` 讀 `docs_dir`（預設 `docs/`，本人常見用 `docs-site/`）。

## 第二步：找出「上次 doc 更新後到現在」的 commits

```bash
# 找出最近一次 doc-site 相關 commit
git log -1 --format=%H -- docs-site/ docs/ mkdocs.yml 2>/dev/null

# 從那個 commit 到 HEAD 的 diff（除了 doc-site 之外的變動）
git log <last_doc_commit>..HEAD --oneline -- ':(exclude)docs-site/' ':(exclude)docs/'

# 哪些 source 檔變了
git diff <last_doc_commit>..HEAD --stat -- src/ scripts/ schema/ catalog/ 2>/dev/null
```

歸納成「需要 doc 更新的領域」清單。

## 第三步：行動方案（依框架）

### A. MkDocs (Material 通常)

1. **裝建置環境**（若未裝）：

   ```bash
   .venv/bin/pip install mkdocs==1.6.1 mkdocs-material==9.7.6
   ```

2. **strict build 跑得起來嗎**：

   ```bash
   .venv/bin/mkdocs build --strict 2>&1 | tail -30
   ```

   有 error 先修：常見是 dangling link / nav 引用不存在的 `.md`。

3. **比對 nav vs 實際檔**：

   ```bash
   # nav 列的檔案
   grep -oE '[a-z-]+/[a-z-]+\.md' mkdocs.yml | sort -u
   # 實際存在
   find docs-site -name "*.md" | sort -u
   ```

   差異 = 需要新增頁、移除 nav 條目、或更名。

4. **針對 step 2 找出的「需要 doc 更新領域」，提案要改的頁**：
   - 例如 `src/qd_ingest/sources/finmind.py` 大改 → 提案改 `docs-site/db/finmind.md`
   - 例如 `scripts/fetch_tej.py` 新增 `--table xxx` → 提案改 `docs-site/ops/manual-ingest.md`
   - 例如 schema migration → 提案改 `docs-site/db/schema.md`

5. **跑專案的 dashboard / report 重生**（若有）：

   ```bash
   # 常見模式（依 repo）
   .venv/bin/python scripts/gap_report.py --format all      # QUANTDATA
   .venv/bin/python scripts/coverage_report.py              # 其他 repo
   ```

   把產出 mirror 到 `docs-site/`（如果 repo 約定如此）。

6. **changelog 更新**（如果有 `docs-site/changelog.md`）：把上次 commit 後的重要變動寫成一段。

7. **commit**：

   ```bash
   git add docs-site/ mkdocs.yml
   git commit -m "docs: refresh doc-site to match HEAD ($(git rev-parse --short HEAD))"
   ```

8. **push? 只有當使用者明確要求 / 要觸發 docs.yml workflow** 時才 push。否則停在 local commit。

### B. Docusaurus / VitePress / Jekyll

類似 A，但 build command 不同：

| 框架 | build | dev |
|---|---|---|
| Docusaurus | `npm run build` | `npm run start` |
| VitePress | `npm run docs:build` | `npm run docs:dev` |
| Jekyll | `bundle exec jekyll build` | `bundle exec jekyll serve` |

通用 framework-agnostic 步驟：跑 build → 修錯 → 更新 nav/sidebar → 寫 changelog → commit。

### C. 沒有 doc site（scaffold 模式）

如果 `pwd` 的 repo 沒有任何 doc site config：

1. 問清楚 repo 的目的（讀 README.md）
2. 推薦 MkDocs Material（最低門檻、Mermaid native、auto deploy via gh-pages）
3. 建議 scaffold：`mkdocs.yml` + `docs-site/{index,architecture,api,ops}.md` + `.github/workflows/docs.yml`
4. 列出建議的 nav 結構 + 預期幾頁
5. 等使用者點頭再實際寫檔

## 第四步：報告

`/update-doc` 完成後，給使用者 3-5 行報告：

- 涵蓋的 commit 範圍（`abc1234..def5678`）
- 改了哪幾頁（` docs-site/db/finmind.md` / `mkdocs.yml` nav / `changelog.md` 等）
- regen 了什麼 dashboard / report
- strict build 結果（PASS / 多少警告 / 多少 error）
- 接下來建議使用者 `git push` 觸發 deploy

## 安全規則

- **不要**在沒有 commit 的情況下覆蓋使用者的 dirty changes — 先 `git stash` 或停下來問
- **不要** auto-push 到 main / master 除非使用者明確說了「push 上去」「上線」「deploy」
- **不要**砍 nav 條目，除非使用者確認；nav 結構是使用者的設計選擇
- **不要**在頁面內亂寫產品決策（如「我們現在用 X 框架」），那是使用者的事；只能基於既存 doc 風格做最小更新
- 跑 `mkdocs build --strict` 前先確認 venv 啟動且 mkdocs / material 版本一致

## 與其他 skill 的關係

- `/skill commands` 用來建立 NEW 全域 slash command；本 skill 是 ALREADY 存在的 doc 更新流程
- repo 內 `.claude/agents/<doc-related>.md` 如果存在，**先讀那個 agent 的指示**，本 skill 是 fallback
- 若 repo 有 `daily_refresh.sh` 或類似 orchestrator，呼叫它而不是手動跑 fetch+ingest

## 觸發範例

```
/update-doc                                          # 全 repo 掃描，自動找變動
/update-doc focus=db                                 # 只關心 db 相關頁面
/update-doc since=v1.2.0                             # 從特定 tag / commit 開始算
/update-doc dry-run                                  # 列計畫不執行
```

## 為什麼這 skill 存在

人類在 repo 上忙 source 變動時常忘記跟著更新 doc-site，導致 doc 與實作脫節幾週甚至幾月。本 skill 把「最近 commits → 哪幾頁該改 → strict build → commit」串成可重複的流程，讓 doc 永遠跟得上 main branch。
