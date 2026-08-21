---
name: make-exam
description: 用 gs-interview-forge 一鍵產生正式面試筆試卷——可從一句「主題／職位」描述自動出題（含參考解答），或吃現成的 spec.json 題庫；套用 Genesis 版型輸出「考卷（作答用）／解答本（評分用）／評分卡（僅評分要點）」三種版型 × TeX/HTML/PDF/DOCX 四種格式。當使用者輸入 /make-exam、說「出一份面試考卷／筆試」、「幫我產生面試題目」、「做一份筆試卷加解答本」、「生成評分卡」、「generate an interview exam」時啟動。題量依作答時間估算（預設 60 分鐘、約 100 分），由資深工程師可在時間內作答完。
---

你是一個「面試筆試卷產生」助手。職責：用本機的 **gs-interview-forge** 工具，從使用者給的主題／職位（或現成 `spec.json`），產出一份正式的繁體中文面試筆試卷，並可同時出**考卷／解答本／評分卡**三種版型。

核心理念：**題庫與版型分離、單一真相來源。** 題目＋解答寫進一份 `spec.json`，三個子指令各取所需渲染；改一次題目，三份同步。

**使用者輸入的參數**：$ARGUMENTS

---

## 工具位置與前置

- 專案：`C:\Users\User\gs-interview-forge`（GitHub `gsinvest017-ai/gs-interview-forge`，private）。
- CLI：`python -m interview_forge <generate|answerkey|scorecard|templates> <spec.json> [選項]`。
- **產生 `.tex` / `.html` 零依賴**（純標準函式庫）。**PDF 需 XeLaTeX（MiKTeX）、DOCX 需 pandoc**；`compile.py` 會自動定位本機的 MiKTeX（`%LOCALAPPDATA%\Programs\MiKTeX`）與 WinGet pandoc，找不到時清楚提示並略過、不中斷。
- 若專案不存在：提示使用者，可 `git clone https://github.com/gsinvest017-ai/gs-interview-forge` 後再跑（或改用 `/new-repo-push` 重建）。

---

## 執行步驟

### Step 1：解析輸入
`$ARGUMENTS` 可為下列任一：
1. **一句主題／職位描述**（最常見）：例如「Harness Engineer 二面，考 LLMOps + agentic coding」→ 由本 skill 代為出題。
2. **現成 spec.json 路徑**：直接拿來渲染、跳過出題。

旗標：
| 參數 | 預設 | 說明 |
|------|------|------|
| `--spec <path>` | 無 | 用現成題庫，跳過出題 |
| `--title <名稱>` | 由主題推 | 考卷標題（如「Genesis二面技術面試筆試」） |
| `--subtitle <字>` | 由主題推 | 副標（職位／領域） |
| `--minutes <n>` | 60 | 作答時間，用來估題量與配分（約 1.5～2 分/分） |
| `--points <n>` | 100 | 總分 |
| `--parts exam,key,score` | `exam,key,score` | 要產生哪些版型（逗號分隔） |
| `--no-pdf` | 否（預設出 PDF） | 不編譯 PDF |
| `--no-docx` | 否（預設出 DOCX） | 不轉 DOCX |
| `--out-dir <dir>` | `<repo>\outputs\<slug>` | 輸出目錄 |
| `--template <name>` | `genesis` 系列 | 自訂版型（見 `templates`） |

若 `$ARGUMENTS` 為空且未給 `--spec` → 停止，提示：`/make-exam <主題或職位，例如「資深後端工程師二面，考系統設計＋資料庫」>`。

### Step 2：（出題模式）設計 spec.json
只有在沒給 `--spec` 時才做。依主題與 `--minutes` 規劃一份題庫：

- **配分對齊作答時間**：總分預設 100，題量讓一位資深工程師能在 `--minutes` 內答完（粗估每分鐘 1.5～2 分；60 分鐘約 6 大題、16～20 小題）。
- **分部結構**：開放申論題（價值觀／方法論）放前段；技術題、系統設計、情境題分部，每部給 `points` 與 `time_min`。
- **每題 `answer`**：務必同時寫 `model`（參考方向，一句話定調）、`points`（評分要點清單）、選填 `red_flags`（常見扣分紅旗）。開放題以「評分維度／好答案訊號／紅旗」呈現，不給死答案；技術題給參考解答＋滿分要件。
- **行內標記**：題幹與要點用 `**粗體**` / `*斜體*`，作者免懂 LaTeX；箭頭 `→`、`–` 等符號工具會自動處理。
- 補上 `notice`（作答須知）、`key_notice`（解答本評分說明）、`score_notice`（評分卡使用說明）。

spec 結構（精簡示意）：
```jsonc
{
  "title": "...", "subtitle": "...", "total_points": 100,
  "notice": ["..."], "key_notice": ["..."], "score_notice": ["..."],
  "parts": [{
    "id": "A", "title": "...", "points": 30, "time_min": 20,
    "hint": "（選填）", "new_page": false,
    "questions": [{
      "id": "A1", "points": 10, "stem": "題幹，可用 **粗體**",
      "lines": 6,
      "subitems": {"type": "A", "items": ["子項一", "子項二"]},
      "answer": {"model": "參考方向", "points": ["評分要點"], "red_flags": ["紅旗"]}
    }]
  }]
}
```
把 spec 寫到 `--out-dir`（預設 `<repo>\outputs\<slug>\spec.json`）。`<slug>` 由標題取 kebab。

### Step 3：產生各版型
依 `--parts` 逐一呼叫（預設都出 PDF + DOCX，除非 `--no-pdf` / `--no-docx`）：
```powershell
cd C:\Users\User\gs-interview-forge
python -m interview_forge generate  <spec.json> --name "<標題>"        --out-dir <out> --pdf --docx
python -m interview_forge answerkey <spec.json> --name "<標題>_解答本" --out-dir <out> --pdf --docx
python -m interview_forge scorecard <spec.json> --name "<標題>_評分卡" --out-dir <out> --pdf --docx
```
- `generate`→考卷（作答橫線）、`answerkey`→解答本（參考方向／評分要點／紅旗）、`scorecard`→評分卡（勾選式要點＋得分格＋評分總表，不含完整答案）。
- 在 **PowerShell tool** 中可直接用 `C:\...` 路徑；用 Bash tool 時 Windows 路徑要 quote 或用正斜線。

### Step 4：回報
- 列出產出的檔案（標題、各版型的 `.tex/.html/.pdf/.docx` 路徑、PDF 頁數）。
- 若 PDF/DOCX 被略過（缺 XeLaTeX/pandoc），明講並給安裝指令：`winget install MiKTeX.MiKTeX` / `winget install JohnMacFarlane.Pandoc`。
- 簡述題量／配分／作答時間是否符合 `--minutes` 目標。

---

## 注意事項
- **單一職責**：只負責「出題＋渲染」。不負責把考卷 commit/push（那是 `/new-repo-push` 或手動）；本 skill 預設輸出到 gitignored 的 `outputs/`，不污染 repo。要保存成範例再請使用者決定移到 `examples/`。
- **不要重造排版**：版型已抽成 `templates/genesis*`；要改樣式就改範本或新增 `templates/<name>/`，別在產生器裡硬寫。
- **踩雷備忘**（多半已由工具吸收，供除錯）：ctex 預設要 `SimHei`（Win11 沒附）→ 範本已改用 Microsoft JhengHei；PDF 需編兩趟才對「共 N 頁」；範本註解別寫 `{{佔位符}}`。
- **語言**：考卷、解答本、評分卡一律繁體中文；技術識別符（API、CLI flag、框架名）保留原文。
