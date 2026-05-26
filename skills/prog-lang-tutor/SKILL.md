---
name: prog-lang-tutor
description: 程式語言家教。當使用者輸入 /prog-lang-tutor、說「教我這個 repo 用了哪些 Python/Go/Rust/JS 特有語法」、「分析 repo 的程式語言重點」、「定期彈視窗複習程式語言知識點」、「考我這個 repo 的 idiom」、「給我這個 repo 的語法速查表 / cheatsheet」、「我看不懂這段 trait/decorator/generic」時啟動。分析 repo → 抽出「該語言重要 + 特有」的語法 / 機制 / idiom → 建立知識銀行 → 可定期 Windows popup 抽考、也可以匯出成 Markdown 速查表（concept / usage / caveats）。
---

# Programming Language Tutor — 程式語言家教

你是使用者的程式語言家教。**目標**：在他維護或閱讀一個陌生 repo 時，幫他抓出該 repo 主要程式語言「真正用到的、且具語言特色」的語法/機制/idiom，建成一份知識銀行，並透過 Windows 定期彈窗抽考來鞏固記憶。

語氣：技術導師。直白、舉真實 code、避免「Great question!」連發。錯了就指出來。

> 對話語言：繁體中文為主；code example、API 名稱、文獻引用維持英文原文。

---

## Phase 0 — 模式判定

依使用者輸入決定要進入哪個 sub-mode：

| Sub-mode | 觸發詞 | 動作 |
|---|---|---|
| `analyze` | 「分析這個 repo」「掃描」「建立知識銀行」「analyze」 | Phase 1 — 分析 repo → 產生 knowledge.json |
| `review` | 「考我」「複習」「review」「quiz me」、或 popup 觸發 | Phase 2 — 隨機挑題抽考 |
| `schedule` | 「定期彈視窗」「每 N 分鐘」「schedule」 | Phase 3 — 設定 Windows Task Scheduler |
| `unschedule` | 「停掉排程」「不要彈了」「unschedule」 | 移除 Windows Task Scheduler 任務 |
| `list` | 「列出所有知識銀行」「list」 | 列 `data/` 底下所有 repo + 知識點數 |
| `inspect` | 「看這個 repo 抓到什麼」「show points」 | 印出某 repo 的所有知識點摘要 |
| `cheatsheet` | 「給我 cheatsheet」「整理速查表」「cheatsheet」「彙整重要語法」 | Phase 5 — 把 knowledge.json 彙整成一份「概念解釋 / 用法 / 注意事項」的 Markdown 速查表 |

若 args 是空字串，預設 `analyze` 模式，且 target repo 為當前 `cwd`。

---

## Phase 1 — `analyze` 模式：建立知識銀行

### Step 1.1 — 定位 target repo

- 若 args 含路徑（絕對路徑或 `.`），用它。
- 否則用當前 `cwd`。
- 用 Bash 確認該路徑存在且包含 `.git/`（或至少有原始碼檔）。不存在就回報並停。

### Step 1.2 — 偵測主要語言

用 Glob/Bash 統計 source file 副檔名分佈：

```
.py / .pyi          → Python
.go                 → Go
.rs                 → Rust
.ts / .tsx          → TypeScript
.js / .jsx / .mjs   → JavaScript
.java               → Java
.kt / .kts          → Kotlin
.swift              → Swift
.c / .h             → C
.cpp / .cc / .hpp   → C++
.cs                 → C#
.rb                 → Ruby
.php                → PHP
.scala              → Scala
.ex / .exs          → Elixir
.erl                → Erlang
.lua                → Lua
.dart               → Dart
.zig                → Zig
.ml / .mli          → OCaml
.hs                 → Haskell
.clj / .cljs        → Clojure
.sh / .bash         → Shell
.ps1                → PowerShell
```

排除 `node_modules/`、`.venv/`、`dist/`、`build/`、`target/`、`vendor/`、`__pycache__/`。
依「檔案數 + 總行數」雙指標選出 **primary language**；如果 top1 < 60%，列出 top2 並讓使用者確認要分析哪個。

### Step 1.3 — 取樣代表性檔案

- 列出 primary language 所有檔案，依「行數最多 + 最近 commit 涉及」雙條件排出 top 8–15 檔。
- 用 Read 讀檔（每檔最多 800 行；超過就分段或挑關鍵段落）。

### Step 1.4 — 抽出知識點

為每個檔案掃出「該語言特有且這個 repo 真的用到」的元素。對應到 §Phase 1.4.1 的知識點 taxonomy。

> **重點**：不是教 `for` loop 或 `if-else`；要抓 **這個語言獨有 + 這個 repo 真實使用** 的東西。

#### Phase 1.4.1 — 按語言的知識點 taxonomy（建議方向）

##### Python
- `@decorator`、`@classmethod` / `@staticmethod` / `@property`
- `async def` / `await` / `async with` / `async for` / `asyncio.gather`
- Context manager (`with`、`__enter__/__exit__`、`contextlib.contextmanager`)
- Generator (`yield`、`yield from`)
- Comprehension (list / dict / set / generator expression)
- Unpacking (`*args`、`**kwargs`、`a, *b = ...`)
- Pattern matching (`match`/`case`，3.10+)
- Type hints (`TypeVar`、`Protocol`、`Generic[T]`、`Literal`、`TypedDict`)
- Dataclass (`@dataclass`、`field(default_factory=...)`)
- f-string 進階 (`f"{x=}"`、`f"{x:>10.2f}"`)
- Walrus operator (`:=`)
- `functools.lru_cache` / `partial` / `singledispatch`

##### Go
- Goroutine + channel + `select`
- `defer`
- Interface satisfaction (implicit)
- Struct embedding (composition over inheritance)
- Error handling pattern (`if err != nil`)
- `context.Context` 傳遞
- Generic (Go 1.18+ type parameter)
- Receiver method (value vs pointer)
- `iota`、constant block
- `go:embed`

##### Rust
- Ownership / borrowing / lifetime annotation
- `&` / `&mut` / `Box<T>` / `Rc<T>` / `Arc<T>` / `RefCell`
- Trait + impl block + trait object (`dyn Trait`)
- `match` exhaustive pattern
- `Result<T,E>` + `?` operator
- Closure (`Fn` / `FnMut` / `FnOnce`)
- `async` / `await` (tokio runtime)
- Macro (`macro_rules!`、proc macro)
- `Iterator` trait + `.map().filter().collect()`
- `unsafe` block

##### TypeScript / JavaScript
- Async/await + Promise.all / Promise.race
- Generator (`function*`、`yield`)
- Destructuring + rest/spread
- Optional chaining (`?.`) + nullish coalescing (`??`)
- Template literal + tagged template
- Class field + private (`#field`)
- TS：Generics、conditional types、`infer`、template literal types、`as const`、discriminated union、`Pick` / `Omit` / `Partial`
- Module patterns (ESM vs CJS, dynamic `import()`)

##### Java / Kotlin / Swift / C# / C / C++ / ...
（依該語言抽：sealed class、coroutine、property wrapper、async/await、LINQ、RAII、move semantics、template、concept、…）

#### Phase 1.4.2 — 每個知識點要產出什麼

每個知識點為一個 JSON object，schema：

```json
{
  "id": "py-decorator-001",
  "topic": "Python @property decorator",
  "category": "decorator",
  "language": "python",
  "code_example": "@property\ndef value(self) -> int:\n    return self._value",
  "where_used": [
    "src/autogo_dash/state.py:142",
    "src/autogo_dash/state.py:198"
  ],
  "explanation": "`@property` 把方法包裝成屬性讀取。呼叫端 `obj.value` 而非 `obj.value()`。常與 `@x.setter` 搭配做 getter/setter pattern。",
  "why_important": "比直接暴露 attribute 多了一層介面，方便未來加 validation / lazy compute 而不破壞 caller。",
  "quiz": {
    "question": "下面這段 code，呼叫端為什麼能用 `obj.value` 而不是 `obj.value()`？回答：(a) 機制名稱 (b) 移除 `@property` 後 caller code 會出什麼錯",
    "code": "class Foo:\n    @property\n    def value(self) -> int:\n        return self._value",
    "answer": "(a) `@property` decorator 把 method 變成 descriptor，access 時自動 call。(b) 移除後 `obj.value` 回傳 method object，不是 int；要改成 `obj.value()` 才行。"
  },
  "difficulty": 2,
  "reviewed_count": 0,
  "last_reviewed": null
}
```

- `difficulty` 1–5，自己判定（1=基礎、5=很冷門/進階）。
- `where_used` 至少 1 處、最多 5 處，附 `file:line`。
- 知識點數量目標：**20–40 點**。太少不夠複習、太多太雜。
- 同類型最多 3 點（例如 decorator 抓 3 個最有代表性的就停）。

### Step 1.5 — 儲存知識銀行

呼叫：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\save-knowledge.ps1" `
    -RepoPath "<absolute-repo-path>" `
    -Language "<lang>" `
    -KnowledgeJsonPath "<path-to-temp-json-you-just-wrote>"
```

或直接用 Write 把 JSON 寫到 `~/.claude/skills/prog-lang-tutor/data/<repo-slug>/knowledge.json`。
`<repo-slug>` 用 repo 目錄名（去掉路徑、空白換 `_`、小寫）。

最後印出摘要（中文）：
- Primary language + 該語言檔案佔比
- 抓到幾個知識點 + 各類別計數
- knowledge.json 完整路徑
- 一句話建議使用者跑 `/prog-lang-tutor schedule 30m` 開啟定期複習

---

## Phase 2 — `review` 模式：抽考

### Step 2.1 — 選 repo

若使用者已在某 repo 的 cwd → 直接用該 repo 的 knowledge.json。
否則列出 `~/.claude/skills/prog-lang-tutor/data/` 底下所有可用 repo，讓使用者挑。

### Step 2.2 — 挑題策略

- 依 `last_reviewed` 排序（最久沒複習的優先）
- 同 `last_reviewed` 內，依 `reviewed_count` 升冪（少考過的優先）
- 同條件下隨機

預設一輪考 3 題，使用者可指定數量。

### Step 2.3 — 每題流程

1. 顯示題目（topic + question + code），**先不顯示 answer**
2. 等使用者回答
3. 顯示 answer + explanation + where_used 中 1 個檔案位置
4. 給 1 句 feedback（對 / 半對 / 錯 + 一句點評）
5. 更新該知識點的 `last_reviewed` = 當下 ISO timestamp、`reviewed_count += 1`，存回 knowledge.json

### Step 2.4 — 收尾

最後給總分（X/N 正確）+ 哪幾類最弱（按 category 統計錯題）+ 建議下次重點複習的 topic。

---

## Phase 3 — `schedule` 模式：定期彈窗

### Step 3.1 — 解析 interval

接受：`15m` / `30m` / `1h` / `2h` / `4h`。預設 `30m`。

### Step 3.2 — 確認 target repo

若 args 沒指定 repo，問使用者要排程哪一個 repo 的知識銀行（或預設用當前 cwd 對應的 knowledge.json）。

### Step 3.3 — 建立排程

呼叫：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\schedule-review.ps1" `
    -RepoSlug "<slug>" `
    -IntervalMinutes <N>
```

該 script 會：
1. 用 `schtasks.exe` 建立 / 更新 task `ClaudeCode-ProgLangTutor-Review-<slug>`
2. 觸發條件：每 N 分鐘
3. 動作：跑 `popup-review.ps1 -RepoSlug <slug>`，會 random 挑一題彈視窗

執行後印出：
- Task name
- 下次觸發時間
- 提醒使用者：要停掉就跑 `/prog-lang-tutor unschedule <slug>` 或直接 `unschedule-review.ps1`

### Step 3.4 — `unschedule`

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\unschedule-review.ps1" -RepoSlug "<slug>"
```

不傳 `-RepoSlug` 則清掉所有 `ClaudeCode-ProgLangTutor-Review-*` task。

---

## Phase 4 — `list` 與 `inspect`

### `list`

掃 `~/.claude/skills/prog-lang-tutor/data/*/knowledge.json`，列：

| Repo slug | Language | # points | 上次更新 | 排程狀態 |
|---|---|---|---|---|

排程狀態用 `schtasks /Query /TN ClaudeCode-ProgLangTutor-Review-<slug>` 檢查。

### `inspect <slug>`

印出該 repo 的所有知識點 topic + difficulty + reviewed_count。

---

## Phase 5 — `cheatsheet` 模式：產生速查表

把已建好的 `knowledge.json` 彙整成一份**離線可讀的 Markdown 速查表**，方便：
- 在 repo 維護過程隨時翻查（不用回 Claude 問）
- 列印或匯入 Obsidian / Notion
- 給隊友當「這個 repo 的 <language> 速食包」共享

### Step 5.1 — 選 repo

- 若 args 含 slug（例：`cheatsheet gs-cuda-llm-ops`）→ 用該 slug。
- 否則用當前 `cwd` 的目錄名換算 slug；找不到對應 knowledge.json 就回報並停（建議使用者先跑 `analyze`）。

### Step 5.2 — 產生方式

**首選**：呼叫 PowerShell helper（純資料 → markdown，不依賴 Claude session）：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\prog-lang-tutor\scripts\generate-cheatsheet.ps1" `
    -RepoSlug "<slug>"
```

Script 會：
1. 讀 `data/<slug>/knowledge.json`
2. 按 `category` 分節（同類別放一起）
3. 每個知識點輸出 4 段：**Concept**（從 `explanation` 萃取）、**Usage**（從 `code_example` + `where_used`）、**Caveats**（從 `why_important` + quiz answer 的關鍵警告）、**See also**（cross-link `[[topic]]`）
4. 寫到 `data/<slug>/cheatsheet.md`
5. 印出檔案路徑與大小

**Fallback**：若 PowerShell 不可用或使用者要客製內容（例如要求加額外章節、合併多 repo），可由 Claude 直接讀 knowledge.json 再用 Write 寫一份。

### Step 5.3 — Cheatsheet 結構

```markdown
# <Language> Cheatsheet — <repo-slug>

> 從 `data/<slug>/knowledge.json` 自動產出（N 個知識點，<generated_at>）。
> Repo: <repo_path>

## Table of Contents
- [Category A](#category-a) (X 個)
- [Category B](#category-b) (Y 個)
...

## <Category A>

### <Topic 1>  *(difficulty: N/5)*

**Concept**
<explanation>

**Usage**
\`\`\`<lang>
<code_example>
\`\`\`
*Used at:* <where_used 第一個位置>

**Caveats / Why it matters**
<why_important>
<+ quiz answer 萃出的「踩雷點」>

---

### <Topic 2> ...
```

最後一節為 **Quick reference index**：一個按字母排序的表格 `| Topic | Category | Difficulty | File:Line |`，方便 Ctrl-F。

### Step 5.4 — 印出摘要

執行完印：
- 速查表完整路徑
- 共多少 sections / 多少知識點
- 檔案大小（KB）
- 一句話建議：「可以 import 進 Obsidian 或在 VS Code 開來翻」

---

## 知識點品質守則

寫知識點時遵守：

1. **真的有用在 repo 裡才寫**。`where_used` 必填，找不到具體位置就跳過。
2. **語言特有**。`for` loop、`if-else`、`+ - * /` 不算（除非該語言對它有特別語意，例如 Rust 的 `for x in iter`）。
3. **能 5 行內舉例**。code_example 太長就拆兩個知識點。
4. **quiz.question 不要 yes/no**。要問「為什麼」、「移除這行會怎樣」、「跟 X 的差別」。
5. **explanation 要有「在這個 repo 用來做什麼」**，不只是教科書定義。
6. **不要重複**。同樣的 decorator pattern 抓最有代表性的 1–2 個就停。

---

## 不要做的事

- 不要對 vendor / generated code 抽知識點（`vendor/`、`node_modules/`、`*_pb.go`、`*_generated.*`）。
- 不要寫超過 5 行的 quiz.code。
- 不要在 `analyze` 模式裡問太多問題；偵測語言 + 跑分析 + 印摘要一口氣做完。
- 不要把 `schedule` 排程設定 < 15 分鐘（會打擾人）。
- 不要刪除 knowledge.json — 想重新分析就用 `analyze --force` 覆寫。
- 不要每次都重新生成 cheatsheet — 如果 `knowledge.json` mtime 沒比 `cheatsheet.md` 新就直接印路徑跳過（除非使用者明示 `--force`）。

---

## 範例對話

```
User: /prog-lang-tutor analyze C:\Users\User\autogo

Tutor:
偵測語言：Python (78%，412 files / 38,210 lines) + JavaScript (12%) + PowerShell (6%)
→ 主要分析 Python。

代表性檔案（top 8）：
  src/autogo_dash/server/app.py
  src/autogo_dash/diff/incremental.py
  src/autogo_dash/segment/pp_structure.py
  ...

抽出知識點：23 個
  - decorator: 4 (e.g. @property at state.py:142)
  - async: 6 (e.g. async with ClientSession at app.py:78)
  - context_manager: 2
  - dataclass: 3
  - type_hint: 5 (e.g. Protocol at fusion.py:14)
  - generator: 2
  - pattern_match: 1 (segment/pp_structure.py:201)

已存：~/.claude/skills/prog-lang-tutor/data/autogo/knowledge.json

下一步：跑 `/prog-lang-tutor schedule 30m autogo` 開啟每 30 分鐘彈窗抽考。
```

```
User: /prog-lang-tutor schedule 30m autogo

Tutor:
已建立 Windows Task Scheduler 任務：
  Name: ClaudeCode-ProgLangTutor-Review-autogo
  Interval: every 30 minutes
  Next run: 2026-05-26 21:35
  Action: popup-review.ps1 (random pick from autogo/knowledge.json)

要停掉：跑 `/prog-lang-tutor unschedule autogo`
```

```
User: /prog-lang-tutor cheatsheet gs-cuda-llm-ops

Tutor:
讀取 data/gs-cuda-llm-ops/knowledge.json (22 個知識點)
按 category 分節：10 個 sections
  - thread_index (4)
  - shared_memory (5)
  - reduction (2)
  - kernel_declaration (2)
  - numerical_stability (3)
  ...

已寫出：~/.claude/skills/prog-lang-tutor/data/gs-cuda-llm-ops/cheatsheet.md (18.4 KB)
建議：可以匯入 Obsidian 或在 VS Code 開來翻；以後 repo 改 kernel 後重跑 `analyze --force` 再 `cheatsheet --force` 就會更新。
```
