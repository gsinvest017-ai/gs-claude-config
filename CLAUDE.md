<!-- BEGIN gh-branch-guard policy -->
## 分支保護政策（不可協商）

**`main` / `master` 是受保護分支。禁止直接 push，一律從 `dev/*` 分支開 Pull Request。**

- 開工前先確認分支：`git rev-parse --abbrev-ref HEAD`。若在 `main`/`master`，先 `git checkout -b dev/<主題>`。
- 允許的分支前綴：`dev/`（預設）、`feat/`、`fix/`、`hotfix/`、`claude/`、`agent/`。
- **禁止**：`git push origin main|master`、`git push --force` 到受保護分支、`gh pr merge`（除非使用者本人是 admin 且明確要求）、修改或停用 ruleset / branch protection、改寫受保護分支歷史。
- 若 push 被拒（`GH006` / `Repository rule violations found`），那是政策生效而非錯誤——改走 PR，不要繞過。
- **任務完成的定義 = PR 已開啟**，不是 merge 完成。

完整政策：[`.github/BRANCH-PROTECTION-POLICY.md`](.github/BRANCH-PROTECTION-POLICY.md)　·　Agent 守則：[`AGENTS.md`](AGENTS.md)
<!-- END gh-branch-guard policy -->

---

# Persistent Project Awareness

## gs-zipline-tej

Path: `/home/kevin/gs-zipline-tej`
A Zipline fork integrated with TEJ (Taiwan Economic Journal) data for Taiwan-market backtesting.

Entry doc:
@/home/kevin/gs-zipline-tej/README.md

Other key files (read on demand):
- `simple_run.md` / `simple_run_zw.md` — quick-start guides (EN / 中文)
- `pyproject.toml`, `setup.py` — build config
- `zipline-tej*.yml` — conda env specs (linux/mac/generic)
- `src/` — source code
- `tests/` — test suite
- `tools/`, `dockerfile/` — utility scripts and container setup

## gs-auto-fix

Path: `/home/kevin/gs-auto-fix`
GitHub Actions 自動化流水線：CI 失敗 → 自動開 issue → Claude 修復並開 PR → Claude review → auto-merge。四段式無人介入 loop。

Entry doc:
@/home/kevin/gs-auto-fix/README.md

Other key files (read on demand):
- `.github/workflows/ci.yml` — pytest + 失敗時 open-issue-on-failure
- `.github/workflows/claude-fix.yml` — `auto-fix` label / `@claude` 觸發修復
- `.github/workflows/claude-review.yml` — PR 自動 review
- `.github/workflows/auto-merge.yml` — `claude/*` branch 或 `auto-merge` label 啟用 native auto-merge
- `requirements.txt`, `tests/` — Python 依賴與測試骨架

## gs-strategy

Path: `/home/kevin/gs-strategy`
雙用途 repo：(1) `quant_crawler/` — 期貨/量化研究論文爬蟲（arXiv q-fin、NBER、RePEc NEP、FED FEDS、Wiley JFM、AQR），SQLite 去重 + relevance filter；(2) `strategies/` — 從爬到的論文挑出 4 支可在台灣期貨市場執行的策略（vgrsi_tx、cubic_momentum_tx、tsmom_tx_mtx、xsmom_stkfut_rmt），目標跑在 zipline-tej 的 `tquant_future` bundle。同時作為 Claude Code YOLO (bypassPermissions) 模式的 sandbox。

Entry doc:
@/home/kevin/gs-strategy/README.md

Other key files (read on demand):
- `strategies/README.md` — 4 支策略一覽（標的、訊號類型、論文出處）與 `_common/runner` 執行流程
- `strategies/{vgrsi_tx,cubic_momentum_tx,tsmom_tx_mtx,xsmom_stkfut_rmt}/` — 各策略子目錄（strategy.py + config.yaml + 獨立 README）
- `quant_crawler/` — `config.py`（source + 關鍵字）、`orchestrator.py`、`crawlers/`、`storage/db.py`（SQLite papers.db）、`utils/http.py`（per-host rate limit）
- `data/papers.db` — 已爬到的 87 篇論文/報告 SQLite
- `docs/EXPERIMENT_LOG.md` — 爬蟲決策過程（含 SSRN/CME/Man Group 為何停用）
- `docs/progress-taiwan-futures.md` — 台灣期貨策略開發進度
- `.claude/settings.json` — 專案層級 bypassPermissions 設定（僅作用於此目錄）
- `claude-yolo-bypass-settings.md` — YOLO 模式完整設定說明（內文仍稱舊名 yolo-claude）
- `tests/` — pytest 測試（arxiv parsing、storage、strategy math、text utils）

## quant-research-skill

Path: `/home/kevin/quant-research-skill`
Claude Code skill pack：`/quant-researcher`（四階段策略產生：理論 → 文獻 → 回測 → 中文報告）與 `/review-strategy`（Jane Street 等級五階段審查，輸出 PASS/CONDITIONAL/FAIL 判定）。

Entry doc:
@/home/kevin/quant-research-skill/README.md

Other key files (read on demand):
- `skills/quant-researcher/SKILL.md` — 四階段研究 pipeline 完整 prompt
- `skills/review-strategy/SKILL.md` — 五階段審查 pipeline 完整 prompt
- `commands/quant-researcher.md`, `commands/review-strategy.md` — `~/.claude/commands/` 用的 slim entry
- `commands/commit-push.md`, `commands/gh-new.md`, `commands/git-config.md` — 配套 git/gh 工具 skill
- `example/` — ATDF 台指期趨勢策略範例輸出（strategy md + 回測圖 + metrics json）
- `add-new-skill.md` — Claude Code custom skill 安裝指南

## autogo

Path: `C:\Users\User\autogo` (Windows-native; the other repos run on Linux/WSL)
Windows desktop screen agent — UIA-first, runtime 0 LLM. `autogo_dash` 是 dashboard 子系統：capture → segment → OCR → diff → fusion → REST。

Entry doc:
@C:\Users\User\autogo\CLAUDE.md

Other key files (read on demand):
- `web/app.py`, `web/static/dashboard.js`, `web/dashboard.html` — 主前後端
- `src/autogo_dash/diff/{incremental,differ}.py` — diff pipeline
- `src/autogo_dash/segment/{pp_structure,heuristic}.py` — segment（PP-StructureV3 + heuristic fallback）
- `src/autogo_dash/server/{app,state}.py`、`src/autogo_dash/ocr/paddle.py`、`src/autogo_dash/fusion.py` — server / OCR / fusion core
- `scripts/lib/{traced-harness,searxng-client}.mjs` — Playwright tracing 與 SearxNG client
- `test-plans/` — 階段性手動測試劇本（含 RTX5090 系列）
- `pyproject.toml` — `[tool.pytest.ini_options].addopts` 已內建 3 個 default-skip ignores

## tutorial

Path: `/home/kevin/tutorial`
量化策略研究員 / 量化開發工程師 onboarding 知識庫。四大模組：策略驗證術語、台灣半導體供應鏈、系統架構、Harness Engineering。

Entry doc:
@/home/kevin/tutorial/README.md

Other key files (read on demand):
- `strategy/strategy-validation-terms.md` — 中英對照術語表（bps、Walk-Forward、IS/OOS Sharpe、Bonferroni、ADX 等）
- `industry/semiconductor-supply-chain.md` / `.html` — 台灣半導體供應鏈 Mermaid 流程圖（IP → Fabless → Foundry → OSAT → Test）
- `system-architecture/arch.drawio` — 端到端系統架構圖（draw.io 格式）
- `harness-engineering/roadmap.drawio` — Harness 工程藍圖（NanoClaw Sandbox、Telemetry、Auto-Fix 等）

---

# Behavior rules

四條 cross-repo 規則，從 /cc-insights 找出的反覆踩坑提煉：

**1. Edit/Write 前先 Read 一次**（避免 `<tool_use_error>File has not been read yet`）。
特別在同檔多輪編輯後，formatter / linter / 另一個 Bash 指令可能改過內容；重 Read 比較穩。

**2. Bash tool 中的 Windows 絕對路徑要 quote 或用正斜線**。
反斜線會被 Bash 吃掉 — `ls C:\Users\User\autogo` 會變成 `ls C:UsersUserautogo` 然後失敗。寫成 `ls 'C:\Users\User\autogo'`、`ls "C:\Users\User\autogo"`、或 `ls /c/Users/User/autogo` 三選一。在 **PowerShell tool** 中沒這個問題，可正常用 `C:\...` 路徑。

**3. Git commit message 的主體用繁體中文撰寫**。所有由 Claude 觸發的 `git commit`（含 `safe-yolo Mn:` 鏈、單發 `feat:` / `fix:` / `refactor:`、merge / revert）一律以繁體中文寫主體描述句。
- **保留原文**：commit prefix（`Mn:` / `feat:` / `fix:` 等）、git trailer（`Co-Authored-By:` / `Signed-off-by:` / `Refs:`）、技術識別符（檔名、函式、`--apply` / `--force` 等 CLI flag、`SKILL.md`、`gs-trading-portal` 等專案名）、引用的英文錯誤訊息原樣。
- **格式**：subject ≤ 72 字（不含 prefix），延續 safe-yolo「不要寫小說」原則——背景與細節寫進 body 或進度檔，不塞 subject。
- **例外**：純機械式工具產生的 commit（dependabot bump、lockfile 重生、auto-merge）保留工具預設訊息；他人撰寫的 commit 不改。
- **Why**：使用者主要語言為繁體中文，commit log 由本人直接 review，中文閱讀效率高；同時讓 `/git-tag` 切 milestone group / `/daily-summary` / `/copy-commits-button` 產出的中文摘要與 commit 標題語感一致，貼到工作群組不會有語言斷層。
- **How to apply**：寫 commit message 前先想中文版主體，再決定要不要加 ASCII prefix；如果不確定某段該不該翻（如 stack trace、API 路徑），原樣保留並用中文做框架說明（例：`修正 /api/today-commits 在 path traversal 下回 500 的 bug`）。

**4. 做完用量顧問（`claude-usage-advisor`）推薦的待辦，要讓它從清單上退場**。推薦有兩個來源，退場方式不同：
- **scan 來源**（「無upstream」「N 檔未commit」）：衍生自即時 git 狀態，commit / push / 建 upstream 後**自己會消失**，不用做任何事。
- **backlog 來源**（`backlog.json` 手動清單）：**不會自己消失**。做完後跑
  `pwsh -File C:\Users\User\tools\claude-usage-advisor\Complete-Task.ps1 -Match <關鍵字> -Note <commit hash 或證據>`。
  帶 `doneWhen` 客觀條件的項目會由 SessionEnd hook 的 `-Auto` 自動歸檔、不用手動；沒有 `doneWhen` 的（研究型、判準主觀）只能靠這條規則。
- **Why**：backlog 沒有退場機制時會一直被推薦，使用者反覆被指派已經做完的事。實例：2026-08-03 清出 3 筆早就完成卻仍在清單上的殘留（gs-spec-forge 3 個 PoC、gs-agent-workshop video pipeline、gs-mlops-loop 進入實作）。
- **How to apply**：收尾時若這次做的事對應到顧問推薦的 backlog 項目，就在最後一個 commit 後補跑 `Complete-Task.ps1`；不確定關鍵字是否唯一命中先加 `-DryRun`。**新增** backlog 項目時盡量附 `doneWhen`（`pathExists`（`path` 可含 `*`）/ `hasUpstream` / `gitLog`），能自動判定就不要靠人。也別反過來硬寫：條件不客觀時留空，比誤判把沒做完的事抹掉好。
