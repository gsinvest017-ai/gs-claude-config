# progress-cheatsheet-feature.md

> Track for: 替 `/prog-lang-tutor` 加 `cheatsheet` 功能，把 repo 的知識銀行匯整成
> 可離線翻閱的 Markdown 速查表（concept / usage / caveats）。
>
> 觸發指令：`/safe-yolo 替/prog-lang-tutor 加上cheatsheet功能...`
> 日期：2026-05-26

---

## 目標

`/prog-lang-tutor` 之前只能做 4 件事：`analyze`（建知識銀行）、`review`（互動抽考）、
`schedule`（彈窗排程）、`list`/`inspect`（盤點）。問題：

- 使用者離開 Claude session 就拿不到知識銀行內容
- knowledge.json 是給 LLM 讀的，不適合人類翻
- 沒辦法把 repo 的語法 / idiom 速食包分享給隊友或印出來

→ 加 `cheatsheet` sub-mode，把 `data/<slug>/knowledge.json` 渲染成一份分類的
Markdown 速查表，存到 `data/<slug>/cheatsheet.md`。可在 VS Code、Obsidian、瀏覽器
直接閱讀。

## 計畫 milestone

| # | Title | 預期產出 |
|---|---|---|
| M1 | SKILL.md 加 cheatsheet sub-mode | Phase 0 routing 加一列；新增 Phase 5 章節定義輸出規格；front-matter description 加關鍵字；範例對話更新 |
| M2 | `generate-cheatsheet.ps1` helper | 純 PowerShell，吃 knowledge.json → 渲染 markdown。支援 up-to-date skip 與 `-Force` |
| M3 | Dogfood：對 `gs-cuda-llm-ops` 跑出第一份 cheatsheet | 22 個 CUDA 知識點、10 個 sections、檔案約 32 KB、肉眼驗證格式正確 |
| M4 | 進度檔 + commit | 本檔案 + 每個 milestone 一個 commit |

## 進度日誌

### M1 — SKILL.md 加 cheatsheet sub-mode  (commit `a50b2be`)

修改：
- `skills/prog-lang-tutor/SKILL.md`
  - 第 16-29 行 Phase 0 routing table 新增 `cheatsheet` 列
  - 第 263-330 行 新增 **Phase 5 — `cheatsheet` 模式：產生速查表**，定義：
    - Step 5.1 選 repo 邏輯（args > cwd）
    - Step 5.2 兩條產生路徑（首選 PowerShell helper、fallback Claude 直接寫）
    - Step 5.3 完整 Markdown 結構規範（TOC、4-section per topic、Quick reference table）
    - Step 5.4 收尾輸出格式
  - Front-matter description 加「給我這個 repo 的語法速查表 / cheatsheet」觸發詞
  - 「不要做的事」加 mtime guard 規則
  - 「範例對話」加 cheatsheet 範例

決策：cheatsheet 寫到 `data/<slug>/cheatsheet.md`（跟 knowledge.json 同目錄、
受 `data/.gitignore` 保護不入庫——這是 runtime artifact，每台機器自己生）。

### M2 — generate-cheatsheet.ps1 helper  (commit `8c645b2`)

新檔：`skills/prog-lang-tutor/scripts/generate-cheatsheet.ps1` (194 行)

關鍵設計：
1. **Pure PowerShell 7+，無外部依賴**——`ConvertFrom-Json` + `StringBuilder` + UTF-8 (no BOM)
2. **Category 排序**：按該分類點數 desc、同數量按字母——讓「大宗 idiom」放前面
3. **Per-topic 4 區塊**：
   - `**Concept**` 從 `explanation` 萃
   - `**Usage**` `code_example` + 第一個 `where_used`（其餘用 `(+N more)` 提示）
   - `**Caveats / Why it matters**` 從 `why_important` + 折疊 `<details>` 包 `quiz.answer`
4. **Quick reference index table** 在尾端，按 topic 字母排序，附 file:line 連結
5. **Skip when up-to-date**：cheatsheet.md mtime ≥ knowledge.json mtime 就跳；`-Force` 覆寫
6. **UTF-8 no BOM** 寫出，避免 GitHub / Obsidian render BOM 字元

decision: 用 PowerShell 而非 Python，因為 (a) 其他 4 個 scripts/*.ps1 也是 PowerShell、
(b) 不希望 cheatsheet 生成綁定 venv 或 python 環境（user 可能在沒 python 的機器跑）。

### M3 — Dogfood (commit 與 M2 同批，沒有獨立 commit，因 cheatsheet.md 在 .gitignore 內)

對 `gs-cuda-llm-ops` 跑：

```
& generate-cheatsheet.ps1 -RepoSlug gs-cuda-llm-ops
→ Path:     data/gs-cuda-llm-ops/cheatsheet.md
  Sections: 10 categories
  Points:   22
  Size:     31.9 KB
```

驗證 3 點：
- ✅ TOC 跟 sections 對得起來（10 個 categories）
- ✅ Per-topic 4 區塊都正常 render（heading 級數、code fence、`Used at:`、`<details>` 折疊）
- ✅ Quick reference index 22 列、按 topic 字母排序、file:line 是 inline code

再測 idempotency：
- 不加 `-Force` 第二次跑 → "Cheatsheet is up to date" 並 exit 0 ✓
- 加 `-Force` → 重新生成同樣 31.9 KB ✓

### M4 — 進度檔 + 收尾 commit

本檔案。M1, M2 已各自 commit；本檔本身 commit 為 M4。

## Commit 範圍

```
a50b2be M1: add cheatsheet sub-mode to prog-lang-tutor SKILL.md
8c645b2 M2: add generate-cheatsheet.ps1 helper
<M4>    M4: progress doc for cheatsheet feature
```

無 push（safe-yolo 預設不 push）。

## Fallback / 回滾指引

- **單純停用功能不需要回滾**：cheatsheet 是純新增 sub-mode，舊指令 `analyze` / `review` /
  `schedule` 完全不受影響。使用者不打 `/prog-lang-tutor cheatsheet` 就什麼都不會發生。
- **完整回滾**：`git revert 8c645b2 a50b2be`（順序無所謂，兩個 commit 無相依）
- **只回 SKILL.md，保留 script**：`git revert a50b2be`，script 留著當「離線工具」用
- **手動清掉產出**：`rm data/<slug>/cheatsheet.md`（不影響 knowledge.json）

## 後續可能擴充（未做）

- `cheatsheet --by-difficulty`：另一種排序方式（按難度 5→1 而非 category）
- `cheatsheet --merge slug1 slug2`：把多個 repo 的知識銀行合成一份大 cheatsheet
- HTML / PDF 匯出：目前只有 Markdown，未來可考慮 pandoc 轉 PDF
- 跟 `save-to-obsidian` 串接：自動把生成的 cheatsheet 丟進 Obsidian vault
