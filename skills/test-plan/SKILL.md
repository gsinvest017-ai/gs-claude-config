---
name: test-plan
description: 依當前 repo 的 codebase 結構與既有 spec（README / CLAUDE.md / docs/spec / OpenAPI / GraphQL schema）自動寫一份分層測試計畫——unit test（per 模組 / 函式列表，含 happy + edge + error 案例）、integration test（外部邊界 DB / HTTP / FS / queue / time，每邊界決定 mock vs real）、e2e test（entry-point flow，含 setup → steps → assert）。偵測語言與測試框架（pytest / unittest / jest / vitest / mocha / go test / cargo test / junit / rspec），輸出至 docs/test-plan.md（可 --split 拆分），附 coverage matrix 與優先級排序，並列出 open questions / spec-vs-code 不一致。當使用者輸入 /test-plan、說「幫這個 repo 寫測試計畫」、「列出該寫哪些 unit / integration / e2e」、「test plan」、「測試覆蓋率規劃」、「outline what to test」時啟動。只寫計畫不寫實作程式碼；預設 dry-run 印大綱，需 --apply 才寫檔。
---

# /test-plan — 依 codebase + spec 寫分層測試計畫

當使用者觸發時，掃**當前 repo** 的程式碼結構與既有 spec，產出一份**unit / integration / e2e 三層**的測試計畫文件。全程繁體中文回報。

**只寫計畫，不寫實作程式碼**——這份產出是「該寫哪些測試、優先順序、每個測試的 setup/assert 點」的清單，不是 `test_*.py` 或 `*.test.js`。實作交給後續的開發步驟（人或其他 skill）。

**預設 dry-run**（印大綱）；需 `--apply` 才寫檔。

## 0. 解析使用者參數

| 參數 | 預設 | 說明 |
|------|------|------|
| `--scope <unit\|integration\|e2e\|all>` | `all` | 限定產出層級 |
| `--out <path>` | `docs/test-plan.md` | 輸出檔；`--split` 時忽略此參數 |
| `--split` | 否 | 拆成 `docs/test-plan/{unit,integration,e2e,coverage}.md` |
| `--spec <path,...>` | 自動掃 (README / CLAUDE.md / docs/spec / openapi*.yaml / *.proto) | 額外指定 spec 來源 |
| `--framework <auto\|pytest\|unittest\|jest\|vitest\|mocha\|go-test\|cargo\|junit\|rspec\|...>` | `auto` | 測試框架；影響案例語法建議 |
| `--target <path>` | repo root | 限定分析範圍（monorepo 子套件） |
| `--coverage-goal <pct>` | `80` | 用來幫案例排優先級 |
| `--case-style <bullet\|table\|gherkin>` | `table` | 案例呈現方式 |
| `--dry-run` | 否（預設） | 只印大綱與會寫的內容 |
| `--apply` | 否 | 真的寫檔 |

範例 args：
- `""` → auto 偵測 + 全 scope dry-run
- `"--apply"` → 套用，寫一份 `docs/test-plan.md`
- `"--scope unit --apply"` → 只產 unit 層計畫
- `"--split --apply"` → 拆 4 份檔
- `"--case-style gherkin --apply"` → 案例用 Given/When/Then 寫
- `"--target packages/api --apply"` → monorepo 限定到一個 package

## 1. 前置檢查 — 偵測語言、測試框架、既有測試位置

| 訊號 | 推斷 |
|------|------|
| `pyproject.toml` 含 `[tool.pytest]` / `pytest` 在 dev-deps | **pytest** |
| `requirements*.txt` 含 `pytest` / `unittest` 用法 | pytest / unittest |
| `package.json` 含 `jest` / `vitest` / `mocha` | 對應 JS framework |
| `go.mod` + `*_test.go` | **go test** |
| `Cargo.toml` + `tests/` 或 `#[cfg(test)]` | **cargo test** |
| `pom.xml` / `build.gradle` 含 JUnit / TestNG | **junit / testng** |
| `Gemfile` 含 `rspec` | **rspec** |
| `.csproj` 含 xunit / nunit | **xunit / nunit** |

既有測試位置：`tests/` / `test/` / `__tests__/` / `spec/` / `*_test.go` / `tests.rs`。

讀 spec 來源（按優先序）：使用者 `--spec` → 自動掃 `CLAUDE.md` / `README.md` / `docs/spec*/` / `docs/api/` / `openapi*.{yaml,json}` / `*.proto` / `schema.graphql`。

## 2. Module map（unit tier 的基礎）

掃 top-level 套件 / `src/` 子目錄。對每個 module 抽：

- **責任**：一句話（從 docstring、README 章節、檔名）
- **公開介面**：可被 import 的函式、類別、constants
- **相依**：呼叫了誰、被誰呼叫
- **純度標籤**：
  - **pure**：無 IO，輸入→輸出，**unit-test 黃金目標**
  - **side-effect**：寫 DB / FS / network / 改 global state，**unit 用 mock，integration 才真打**
  - **glue**：把幾個 module 串起來，**integration tier 才有意義**

排除：vendored / generated / migrations / `__init__.py` 空檔。

## 3. Boundaries map（integration tier 焦點）

列出 repo 跨越的所有**外部 / 跨層邊界**：

| 邊界類型 | 偵測訊號 | 預設策略 |
|---------|---------|---------|
| **DB** | `sqlalchemy` / `psycopg` / `prisma` / `mongoose` / `entity-go` | **real test DB + per-test transaction rollback** |
| **HTTP client（出）** | `requests` / `httpx` / `axios` / `fetch` / `reqwest` | **VCR** / `responses` / `nock` / `wiremock`，可選契約測試 |
| **HTTP server（入）** | Flask / FastAPI / Express / gin / actix | **test client**（不開真 socket） |
| **檔案系統** | `open()` / `fs.writeFile` / `std::fs` | **tmpdir / tempfile** |
| **訊息佇列** | kafka / rabbit / sqs / nats | **embedded / testcontainers** |
| **時間 / 隨機** | `datetime.now` / `Math.random` / `time.Now` | **freeze / seed** |
| **環境變數** | `os.environ` / `process.env` | **monkeypatch / setenv** |
| **subprocess / shell** | `subprocess.run` / `child_process.exec` | **stub or fake binary** |

對每邊界列：實際呼叫位置、要驗的契約（input → output / 錯誤路徑 / retry / timeout）、選定策略原因。

## 4. User flow map（e2e tier 焦點）

找 **entry points**：

- **CLI**：`if __name__ == "__main__"` / `bin/` / `cmd/main.go` / `package.json scripts.start`
- **HTTP routes**：Flask `@app.route` / FastAPI `@app.{get,post}` / Express `app.get` / Dash `@callback`
- **scheduled / cron**：`apscheduler` / `node-cron` / GitHub Actions cron / kubernetes CronJob
- **message handlers**：kafka consumer / SQS handler / webhook receiver
- **UI flows**（若有 frontend）：login → search → CRUD → logout 等

對每個 entry：1 個 happy path + 2–3 個 alternate / error path。每條 flow 寫：
- **Entry**（入口請求 / 指令）
- **Setup**（DB seed、env、auth token）
- **Steps**（時序動作）
- **Assert**（HTTP 200 + body shape / DB 終態 / side effect / log lines）

## 5. 產出 `docs/test-plan.md`（或 `--split` 多檔）

**模板骨架**：

```markdown
# Test plan — <repo>

> 生成於 <YYYY-MM-DD>；spec source: <list>; framework: <detected>

## Overview
- Stack：<lang> <runtime>，test framework：<X>
- 測試檔位置：<path>，命名慣例：<pattern>
- Coverage goal：<pct>%（用於 P0/P1/P2 排序）

## Unit tests
### Module: <module>
**責任**：<1-句話>
**純度**：pure / side-effect / glue
**公開介面**：`foo()`、`Bar`、…

| # | Target | Case | 類型 | 前置 / Mock | 優先 |
|---|--------|------|------|------------|------|
| U-001 | `foo(x)` | x=[] → return [] | happy | — | P0 |
| U-002 | `foo(x)` | x=None → ValueError | error | — | P0 |
| U-003 | `foo(x)` | 1M 筆 → O(n) 不退化 | perf | — | P2 |

（重複每個 module）

## Integration tests
### Boundary: DB layer (PostgreSQL via SQLAlchemy)
**Strategy**：real test DB + transactional rollback per test

| # | Flow | Setup | Assert | 優先 |
|---|------|-------|--------|------|
| I-001 | User.create + read | empty DB | row 寫入 + 欄位匹配 | P0 |
| I-002 | unique constraint | 既有 email | IntegrityError | P0 |

### Boundary: HTTP client (calls Stripe API)
**Strategy**：VCR cassette；首次錄、之後 replay

| # | Scenario | Cassette | Assert | 優先 |

### Boundary: Filesystem
**Strategy**：pytest tmpdir

| # | ... |

## E2E tests
### Flow: 使用者登入到下單
**Entry**：`POST /api/login` → `POST /api/orders`
**Setup**：DB seed user(id=1, balance=1000)；ENV `STRIPE_KEY=test`
**Steps**：
1. POST /api/login {email, password} → 200 + token
2. POST /api/orders {item_id, qty} → 201 + order_id
3. GET /api/orders/{order_id} → 200 + status=pending

**Assert**：
- HTTP status 鏈 200 / 201 / 200
- DB：`orders` 多一筆，user.balance 扣款
- Side effect：寄送確認信（mock SMTP 收到 1 封）

| # | Flow | 優先 |
|---|------|------|
| E-001 | 上述登入下單 happy | P0 |
| E-002 | 餘額不足 → 402 + 不寫 DB | P0 |
| E-003 | 重複下單（idempotency-key） | P1 |

## Coverage matrix
| Module / Layer | Unit | Integration | E2E |
|----------------|------|-------------|-----|
| `auth/`        | ✅   | ✅          | ✅  |
| `orders/`      | ✅   | ✅          | ✅  |
| `notifications/` | ✅ | ✅ (SMTP mock) | ⚠️ partial |

## Implementation order（建議撰寫順序）
1. **P0 unit** for pure-logic modules（最便宜、回報最高）
2. **P0 integration** for DB + 主要外部 HTTP
3. **P0 e2e** for 1 條主 happy + 1 條主 error path
4. **P1** 邊界 case、retry、timeout
5. **P2** 效能 / perf / 大量資料

## Open questions
- Spec 第 X 章說 `Y` 該回 404，但 code（`<file>:<line>`）回 422 → 哪個是 canonical？
- 沒看到 `cancel_order` 的 spec，code 有 endpoint → 需補規格？

## Out of scope
- Vendored libs（`vendor/`、`node_modules/`）
- Generated code（`*.pb.go`、`schema.graphql.ts`）
- Migrations（除非有複雜 data transform）

<!-- BEGIN test-plan: auto-generated section -->
（本標籤區內由 /test-plan 維護；下次重跑只更新此區）
<!-- END test-plan -->
```

`--split` 模式 → 改寫入 `docs/test-plan/{unit,integration,e2e,coverage}.md` 並在 `docs/test-plan/README.md` 串目錄。

## 6. 一致性檢查（產出前）

- 每個 module map 的**公開介面**在 unit 表至少出現一次（或標 `excluded: <reason>`）
- 每個 boundary map 條目在 integration 表至少一筆
- 每個 entry point 在 e2e 表至少一筆 happy
- 計畫內提到的檔案 / 函式**真的存在**（cross-grep 確認）
- spec 與 code 不一致 → 加進 `## Open questions`，不靜默選邊
- 既有 `docs/test-plan.md` + `BEGIN test-plan` 標籤 → 只更新標籤內

## 7. 完成回報

3~5 行：
1. 偵測到的 framework + 既有測試覆蓋現況
2. 產出檔位置（單檔 / 拆檔）
3. 三層測試**案例總數**（U-xxx + I-xxx + E-xxx）
4. Open questions 數量（spec-vs-code 不一致）
5. 建議下一步（先寫 P0 / 跑既有 / 接 CI）

## 不要做的事

- ❌ **寫實作 test code**（這是計畫，不是 `test_*.py`）；要實作另跑開發步驟
- ❌ 沒 `--apply` 就寫檔
- ❌ 猜測 framework；偵測不到要明示「需 `--framework` 指定」
- ❌ 為了湊數寫 trivial getter / setter / typedef 測試；專注邏輯 + 邊界
- ❌ e2e 還在大量 mock；e2e 該打**真的 wiring**（DB 用 test 環境、外部 HTTP 用 VCR 仍算 e2e 但要明確標）
- ❌ 隱藏低信心 / 猜測；統一寫進 `## Open questions`
- ❌ 規劃 vendored / generated code 的測試

## 邊界情況

- **完全沒既有測試** → 計畫變「foundation 版」，標 `no existing reference`，建議從 P0 unit 開工
- **mono-repo**（多個 package 各有 manifest） → 自動 `--split` 或每個 package 一份子計畫（`docs/test-plan/<pkg>.md`）
- **純 library（無 e2e flow）** → e2e tier 可改為「example / demo / doctests」型；或 `--scope unit,integration` 跳過
- **既有完整測試** → 計畫變「gap analysis」，列出未覆蓋的 module / boundary / flow
- **spec 與 code 衝突** → 兩個都列，最終結論寫 `Open questions`
- **時程很趕** → 用 `--coverage-goal 50` 拿小一點的 P0 集合

## 與其他 skill 協作

- **`/write-spec`**：spec 不齊 / 散亂 → 先跑它整理 CLAUDE.md，再回頭跑本 skill
- **`/code-review`**：審 PR 時把本計畫當焦點清單，看新 code 是否覆蓋對應 case
- **`/one-button-launch`**：e2e 要能啟服務 → 沒 launcher 先跑它
- **`/platform-compatible`**：e2e 兩平台都要跑 → 配 CI matrix 一起做

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/test-plan/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入（本 session 即時生效，WSL 端透過 `/mnt/c` symlink 也立即可見）。
