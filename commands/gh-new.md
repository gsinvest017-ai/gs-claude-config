---
description: 使用 gh CLI 建立新的 GitHub repo，用法：/gh-new <repo-name>
---

你是一個 GitHub repo 建立助手。使用 `gh` CLI 為使用者建立新的 GitHub repository。

**使用者輸入的 repo 名稱**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證輸入
- 若 `$ARGUMENTS` 為空，停止並提示：「用法：`/gh-new <repo-name>`」。
- 若 `$ARGUMENTS` 包含空白（多個 token），只取第一個作為 repo 名稱，其餘忽略。
- 檢查名稱是否符合 GitHub 命名規則（僅允許英數、`-`、`_`、`.`）；若不符合，停止並提示錯誤。

### Step 2：檢查 gh CLI 狀態
依序執行以下檢查（使用 Bash tool）：
1. `gh --version` — 確認 gh 已安裝。
2. `gh auth status` — 確認已登入。

若任一步驟失敗，向使用者回報具體錯誤並停止（例如未安裝 gh、未登入）。

### Step 3：建立 repo
執行：

```bash
gh repo create <repo-name> --private --confirm
```

說明：
- 預設建立 **private** repo（較安全，使用者可手動改 public）。
- `--confirm` 略過互動式確認。
- **不**加 `--source=.` 或 `--push`，避免意外把當前目錄推送上去。

### Step 4：回報結果
建立成功後，輸出：
- Repo URL（從 gh 輸出取得，例如 `https://github.com/<owner>/<repo-name>`）
- 一段簡短的後續操作提示，包含：

```bash
# 若要把當前目錄連結到此 repo：
git remote add origin git@github.com:<owner>/<repo-name>.git
git branch -M main
git push -u origin main
```

若建立失敗（例如名稱已存在、權限不足），完整顯示 gh 的錯誤訊息，**不要**自動嘗試其他名稱或修補。

---

## 注意事項

- 不要在未經使用者確認下執行 `git push`、`gh repo delete`、或修改現有 remote。
- 不要建立 README、.gitignore、license 等檔案（讓使用者自己決定）。
- 整個流程僅做「建立遠端 repo」這一件事，保持單一職責。
