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

兩條 cross-repo 規則，從 /cc-insights 找出的反覆踩坑提煉：

**1. Edit/Write 前先 Read 一次**（避免 `<tool_use_error>File has not been read yet`）。
特別在同檔多輪編輯後，formatter / linter / 另一個 Bash 指令可能改過內容；重 Read 比較穩。

**2. Bash tool 中的 Windows 絕對路徑要 quote 或用正斜線**。
反斜線會被 Bash 吃掉 — `ls C:\Users\User\autogo` 會變成 `ls C:UsersUserautogo` 然後失敗。寫成 `ls 'C:\Users\User\autogo'`、`ls "C:\Users\User\autogo"`、或 `ls /c/Users/User/autogo` 三選一。在 **PowerShell tool** 中沒這個問題，可正常用 `C:\...` 路徑。
