---
name: write-spec
description: 分析當前 repo 的架構與功能模組，產生 / 更新 Claude 會「確實遵守」的 agent spec 規則檔（CLAUDE.md 及其拆分檔）。支援拆成多個檔（精簡 root CLAUDE.md + @import 主題檔，或各模組 nested CLAUDE.md）。當使用者輸入 /write-spec、說「幫這個專案寫 / 更新 CLAUDE.md」、「寫一份 agent spec / 規則檔」、「把專案規則拆成多個檔」、「讓 claude 遵守這個 repo 的慣例」、「整理這個 repo 的架構規則給 agent 看」時啟動。預設 update（合併既有、不覆蓋人工內容）；需 --dry-run 只出草稿不寫檔。
---

# /write-spec — 專案 Claude agent spec 規則檔產生 / 更新器

當使用者觸發時，分析**當前 repo** 的架構與功能模組，產生 / 更新一份（或多份）**Claude 會確實遵守的 agent spec 規則檔**。全程繁體中文回報。

兩個設計核心：
1. **讓 Claude 確實遵守** → 規則必須祈使、具體、可驗證、高訊號、前置重點、不自相矛盾（見第 5 段）。
2. **可拆分成多檔** → 利用 Claude Code 的 spec 載入機制：root `CLAUDE.md` + `@相對路徑` import 主題檔，或各模組目錄的 nested `CLAUDE.md`（在該子樹工作時才載入）（見第 4 段）。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--mode <update\|create\|rewrite>` | `update` | update=合併既有不覆蓋人工內容；create=從零建（無既有檔時）；rewrite=整份重寫（需明示） |
| `--split <auto\|single\|imports\|nested>` | `auto` | 單檔 / root+@import 主題檔 / 各模組 nested CLAUDE.md |
| `--scope <path>` | repo root | 限定分析與產出範圍 |
| `--lang <zh-TW\|en>` | 跟隨既有檔，否則 `zh-TW` | spec 檔語言 |
| `--max-root-lines <n>` | `200` | root CLAUDE.md 超過此行數就建議 / 自動拆分 |
| `--dry-run` | 否 | 只印分析結果與草稿，不寫檔 |

範例 args：
- `""` → auto 拆分、update 合併、繁中
- `"--dry-run"` → 先看草稿與拆分計畫
- `"--split nested"` → monorepo 每個主要模組各放一份 CLAUDE.md
- `"--mode rewrite --lang en"` → 整份以英文重寫

## 1. 前置檢查 — 盤點既有 spec

掃描既有規則 / 慣例來源（**不要直接覆蓋**）：

- root `CLAUDE.md`、`CLAUDE.local.md`、巢狀 `**/CLAUDE.md`
- `AGENTS.md`、`.cursor/rules/*`、`.cursorrules`、`.github/copilot-instructions.md`
- `CONTRIBUTING.md`、`README.md`（背景與既有慣例的來源）

判定：
- 有既有 `CLAUDE.md` → 預設 `update`，**保留人工撰寫內容**，只增補 / 修正過時段落；沿用既有的 `@import` 結構與語言
- 無既有 spec → `create`
- 既有檔被本 skill 維護過（有區塊標記，見第 7 段）→ 只更新標記內段落

## 2. 分析 repo 架構

- **目錄樹**：深度 2~3，排除 `node_modules`/`.git`/`dist`/`build`/`.venv`/`target`/`vendor`/`__pycache__`
- **技術棧 + 套件管理器**：從 manifest（package.json / pyproject.toml / go.mod / Cargo.toml…）
- **進入點**：main / index / server / cli / `__main__`
- **指令**（最重要，Claude 最常照抄）：build / test / lint / format / run / typecheck — 從 `package.json` scripts、`Makefile`、`justfile`、`pyproject.toml`、CI yml 萃取**確切指令**
- **模組劃分**：top-level packages、`src/` 子目錄、workspaces / monorepo packages
- **既有慣例**：linter / formatter 設定、commit message 格式（看 `git log --oneline -30`）、目錄與命名 pattern、測試框架與測試檔位置

## 3. 分析功能模組

對每個主要模組，萃取（每項一句話，精簡）：
- **職責**：這個模組做什麼
- **關鍵檔 / 對外介面**：別人從哪裡呼叫它
- **相依關係**：依賴誰、被誰依賴
- **不該動的東西 / 地雷**：自動產生的檔、migration、相容性約束
- **隱性規則**：測試怎麼跑、有無 codegen、有無 secrets / .env 處理慣例

## 4. 決定拆分策略（`--split auto` 決策樹）

Claude Code spec 載入機制：
- root `CLAUDE.md` 永遠載入；可用 `@相對/路徑.md` **import** 其他檔（被引入檔也進 context）
- 子目錄的 `CLAUDE.md`（nested）只在該子樹工作時才載入 → 適合放模組專屬規則

決策：
- **小型**（單模組、root 估算 < `--max-root-lines`）→ `single`：一份 root `CLAUDE.md`
- **中型** → `imports`：精簡 root（總綱 + 指令 + 全域規則）+ `@docs/claude/<topic>.md`（architecture / conventions / testing / domain 等）
- **大型 / monorepo** → `nested`：root 放全域規則 + 指令；每個主要模組目錄放 nested `CLAUDE.md`（只裝該模組規則）
- 無論哪種，**root 永遠保持精簡、高訊號**——這是「讓 Claude 確實遵守」的關鍵：root 越短越被完整讀進去並照做。

## 5. 撰寫規則 — 讓 Claude 確實遵守的原則

這段是本 skill 的靈魂，產生內容時逐條套用：

- **祈使句 + 可驗證**：寫「commit 前先跑 `pytest -q`」而非「重視測試」
- **確切指令優先**：把 build / test / lint / run 的**真實指令**寫進去（Claude 最常直接照抄；寫錯指令比沒寫更糟）
- **重要規則前置並標記**：MUST / NEVER / IMPORTANT 放最上面
- **Do / Don't 成對**：明確邊界，減少邊界亂套
- **附簡短「為什麼」**：一句話原因，Claude 在新情境才能正確外推
- **用專案實際用語**：術語直接從 code / docs 抄，不要自創
- **不寫顯而易見的東西**：code 本身看得出來的（檔案結構、明顯型別）不必寫，省 context 給真正的規則
- **不自相矛盾**：新增前先掃既有規則，衝突要解決而非堆疊
- **不寫願景式空話**：「寫乾淨的程式碼」這種無法驗證的句子刪掉

## 6. spec 檔骨架範本

root `CLAUDE.md` 骨架（精簡、重點前置）：

```markdown
# <Project> — Agent Spec

## Critical rules (MUST / NEVER)
- MUST run `<test cmd>` before every commit.
- NEVER edit files under `<generated dir>/` by hand.

## Project overview
<2~3 句：這是什麼、解決什麼問題、主要技術棧>

## Commands
- Build: `<cmd>`   Test: `<cmd>`   Lint: `<cmd>`   Run: `<cmd>`

## Architecture
<目錄 + 各模組一句職責；大型專案改為 @import>
@docs/claude/architecture.md

## Conventions
<語言 / 命名 / 格式 / 錯誤處理 / commit 格式>

## Gotchas
<已知地雷、相容性約束>
```

`@import` 主題檔（如 `docs/claude/architecture.md`）：純該主題的細節。
nested `CLAUDE.md`（模組目錄內）：只放「在這個模組工作時」要遵守的規則與該模組指令。

## 7. 寫檔 / 合併

- **update 模式用區塊標記**包住本 skill 維護的段落，下次只更新標記內、不動人工內容：

  ```markdown
  <!-- BEGIN write-spec: architecture -->
  ...本 skill 產生的內容...
  <!-- END write-spec: architecture -->
  ```

- **換行 / 編碼**：尊重既有檔的 EOL 與 `.gitattributes`；新檔依 repo 慣例（程式專案 CLAUDE.md 多為 LF）。內容用 UTF-8
- **路徑**：`@import` 一律用 repo 相對路徑（跨平台），不要寫絕對路徑
- **絕不**把 secrets / 金鑰 / 個資寫進 spec

## 8. 驗證

- 所有 `@import` 與 nested 路徑**存在且拼對**
- root 行數 ≤ `--max-root-lines`（超過 → 建議再拆，或回報已自動拆）
- 自我掃一遍規則**無明顯矛盾**、無重複、指令與實際 manifest 一致
- 列出產生 / 修改的檔；提示「新 session 在此 repo 會自動載入 root CLAUDE.md 與適用的 nested CLAUDE.md」
- `--dry-run` 時只印草稿與拆分計畫，不寫檔不驗證

## 9. 完成回報

3~5 行：產生 / 更新了哪些檔、用了哪種拆分策略、保留了哪些人工內容、後續建議（例如「在此 repo 開新 session 驗證 Claude 是否遵守」「之後可重跑 `/write-spec` 增量更新」）。

## 不要做的事

- ❌ 覆蓋人工撰寫內容（`update` 要合併；只有 `rewrite` 才整份重寫且須使用者明示）
- ❌ 把整棵目錄樹 / 所有檔案清單塞進 root（稀釋注意力 → Claude 反而不遵守）
- ❌ 寫模糊願景式規則或顯而易見的廢話
- ❌ 把 secrets / .env 值寫進 spec
- ❌ 讓 root CLAUDE.md 無限長；超過 `--max-root-lines` 就拆
- ❌ 寫進與專案實際指令不符的 build / test 指令（寧可不寫也不要寫錯）

## 邊界情況

- **無任何既有 spec** → `create` 從零建
- **多語言 / monorepo** → `--split nested`，每個 package 一份 CLAUDE.md，root 只放全域
- **已有 `AGENTS.md`（給別的 agent）** → 以 CLAUDE.md 為主，可在 root `@AGENTS.md` 共用、避免兩份漂移
- **repo 太大分析跑不完** → 先做 root + 最重要的 2~3 個模組，其餘在 spec 內標 `TODO(write-spec)`，回報待補清單
- **既有 CLAUDE.md 已很完整** → 只增補缺漏與過時指令，回報「多數沿用、僅 N 處更新」

## 與其他 skill 協作

- **`/init`**（built-in）：只產單一 CLAUDE.md；本 skill 是進階版——多檔拆分 + 模組分析 + 合併更新 + 「可遵守性」寫作守則
- **`/one-button-launch`**、**`/platform-compatible`**：它們產生的啟動指令 / 跨平台規則可被本 skill 收進 spec 的 Commands / Conventions 段
- **`/safe-yolo`**：本 skill 會動多檔，適合包成一個 milestone 一次 commit

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/write-spec/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入。
