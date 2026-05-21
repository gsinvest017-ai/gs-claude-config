---
description: 彙整當前 repo 今日 git commits 與變更，產出繁體中文 Markdown 日報 YYYY-MM-DD-summary.md
---

# /daily-summary — Repo 今日變更彙整

抓出當前 repo 路徑下**當天**所有 git commits 與檔案變更，彙整成一份繁體中文 Markdown 日報。

**使用者請求**：$ARGUMENTS

## 觸發範例

```
/daily-summary                          # 彙整今天、當前 repo、預設 author
/daily-summary 2026-05-20                # 彙整指定日期
/daily-summary --all-authors             # 多人 repo：抓全部 author 的 commits
/daily-summary --repo C:\path\to\repo    # 指定 repo 路徑（會先切換目錄）
```

## 執行流程（精簡版，完整規範見 `skills/daily-summary/SKILL.md`）

1. **前置檢查**：確認在 git repo 內、決定目標日期、決定 author 範圍
2. **抓 commits**：`git log --since="<date> 00:00" --until="<date> 23:59"` + `--author`
3. **收細節**：對每個 commit 跑 `git show --stat` 取標題、檔案數、+/- 行數
4. **分類**：feat / fix / refactor / docs / chore；safe-yolo 的 `Mn:` commit 自動歸到對應任務群組
5. **寫檔**：固定檔名 `YYYY-MM-DD-summary.md`，位置：`docs/daily-summary/` > `docs/` > repo 根目錄
6. **報告**：用繁體中文 Markdown，含：一句話總結、commits 表、分類詳述、影響檔案 Top 5、風險與明日待辦

## 不會做的事

- 不會 `git push` 或建立 PR
- 不會修改任何原始碼，只新增 summary 檔
- 不會把完整 diff dump 到報告（太長），只摘要關鍵變更

## 邊界情況處理

- **今日無 commits** → 回報並停止，不產出空檔
- **有未 commit 變更** → 在報告開頭加 `⚠️ 注意` 區塊列出 `git status --short`
- **同名檔案已存在** → 預設覆寫，並在報告開頭標註 `(覆寫於 HH:MM)`
- **跨 branch（rebase / merge）** → 只看當前 branch
