# 進度：新增 /test-plan 全域 slash command

## 目標

新增一個 system-level global agent command **`/test-plan`**：在任一 repo 觸發時，依該 repo 的 codebase 結構與既有 spec（README / CLAUDE.md / docs/spec / OpenAPI 等），**寫一份分層測試計畫**——unit / integration / e2e 三層——輸出至 `docs/test-plan.md`（或拆多檔），含模組對應的測試案例表、邊界 mock 策略、entry-point flow、coverage matrix 與優先級。**只寫計畫不寫實作程式碼**。完成後安裝到 user-scope（全域）。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/test-plan` skill | `docs/progress-test-plan-command.md`、`skills/test-plan/SKILL.md` |
| **M2** | 驗證全域註冊 + 收尾 | frontmatter 解析通過、出現在 skill 清單 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /test-plan

- 新增 `skills/test-plan/SKILL.md`：frontmatter（避開 YAML colon-space 坑——描述全用全形冒號 / 不含 ASCII `: `）+ 8 段流程：
  1. 解析參數（scope / out / split / spec / framework / target / coverage-goal / case-style / apply）
  2. 前置檢查（偵測語言 + 測試框架 + 既有測試位置；讀 spec 來源優先序）
  3. **Module map**（unit tier 基礎；對每模組標 pure / side-effect / glue 純度，決定 unit 與 integration 邊界）
  4. **Boundaries map**（integration tier 焦點；DB / HTTP-out / HTTP-in / FS / queue / time / env / subprocess 各自的 mock vs real 策略）
  5. **User flow map**（e2e tier 焦點；CLI / HTTP routes / scheduled / message / UI flow entry points 各自 happy + 2~3 alternate）
  6. **產出 `docs/test-plan.md`** 模板（Overview / Unit / Integration / E2E / Coverage matrix / Implementation order / Open questions / Out of scope，含 `<!-- BEGIN/END test-plan -->` 區塊標記）
  7. 一致性檢查（每個 public interface 都有 unit、每個 boundary 都有 integration、每個 entry 都有 e2e；cross-grep 驗證引用的 symbol 真的存在）
  8. 完成回報
- 關鍵設計：
  1. **只寫計畫不寫實作程式碼**——產出是 case list / setup / assert，不是 `test_*.py`
  2. **預設 dry-run** + 需 `--apply` 才寫檔
  3. **spec-vs-code 不一致一律進 Open questions**，不靜默選邊
  4. **case 表用 ID（U-001 / I-001 / E-001）** 方便後續 review / PR cross-ref
  5. **`<!-- BEGIN test-plan -->` 區塊** 重跑只更新自家內容、不覆蓋人工手寫
  6. **`--split`** 大型 / monorepo 可拆 unit / integration / e2e / coverage 四檔
- 兩檔正規化為 CRLF。

### M2 — 驗證全域註冊 + 收尾

- `skills/test-plan/SKILL.md`：以 `---` 起、`name: test-plan` 與檔名一致、description colon-space count = 0（避開 YAML 坑）、全檔 CRLF（LF-only = 0）。
- 已即時出現在 available-skills 清單（`/test-plan`），由 user-scope 取得 → **全域可用**，無需 restart。WSL 端透過稍早建好的 `/mnt/c` symlink 也立即可見。
- commit 範圍：`420c268`(M1) → 本 commit(M2)，全在本機 `main`，**未 push**。

**任務完成**：`/test-plan` 全域 slash command 已建立並註冊。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`，分支 `main`，未 push。
- Rollback：`git log --oneline` 找 `Mn:`，`git reset --hard <hash>`。
- 整個撤掉：刪 `skills/test-plan/`、本進度檔，`git checkout -- .`。
