---
description: 將指定的檔案或資料夾 add → commit → push，用法：/commit-push <file1> <file2> ... <folder1> <folder2>
---

你是一個 Git commit + push 助手。將使用者指定的檔案或資料夾 stage、commit、並 push 到當前分支的 upstream。

**使用者輸入的路徑列表**：$ARGUMENTS

---

## 執行步驟

### Step 1：驗證輸入
- 若 `$ARGUMENTS` 為空,停止並提示:「用法:`/commit-push <file1> <file2> ... <folder1> <folder2>`」。
- 將 `$ARGUMENTS` 以空白切分為路徑列表(支援用引號包住含空白的路徑)。
- 對每個路徑用 Bash 檢查是否存在(`test -e <path>`)。任一不存在,**停止**並列出所有不存在的路徑;**不要**繼續執行。

### Step 2：檢查 Git 環境
平行執行:
- `git rev-parse --is-inside-work-tree` — 確認在 git repo 內。
- `git status --short` — 看當前 working tree 狀態。
- `git branch --show-current` — 取得當前分支名。
- `git log -5 --oneline` — 觀察 commit message 風格(以便撰寫一致風格的訊息)。

若不在 git repo 內,停止並回報。

### Step 3：Stage 指定路徑
針對每個傳入路徑明確執行:

```bash
git add -- <path1> <path2> ...
```

- **禁止**使用 `git add -A`、`git add .`、或 `git add -u`,僅 stage 使用者明確指定的路徑(避免誤帶入 .env、敏感檔、未完成的草稿)。
- 用 `--` 分隔避免路徑被當成 flag。

接著執行 `git diff --cached --stat` 顯示已 stage 的內容摘要。

### Step 4：偵測敏感檔案
若 staged 路徑包含可能敏感的檔名模式(`.env`、`*.key`、`*.pem`、`credentials*`、`secrets*`、`id_rsa*`),**停止**並警告使用者,要求明確確認後才繼續。

### Step 5：撰寫 Commit Message
根據 staged diff 生成簡潔的 commit message:
- 風格須與 `git log -5` 觀察到的歷史風格一致。
- 第一行 ≤ 70 字元,聚焦「為什麼」與「做了什麼」(動詞開頭,例如 `Add`、`Update`、`Fix`、`Refactor`)。
- 必要時加空行 + 詳細說明段落。
- 結尾加上:

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

使用 HEREDOC 傳入 commit message:

```bash
git commit -m "$(cat <<'EOF'
<message here>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- **禁止** `--no-verify`、`--no-gpg-sign`、`--amend`。
- 若 pre-commit hook 失敗,修正問題後**建立新的 commit**,不要 amend。

### Step 6：Push
取得當前分支名,執行:

```bash
git push
```

若該分支尚無 upstream(看到 `fatal: The current branch ... has no upstream branch`),改用:

```bash
git push -u origin <current-branch>
```

**禁止事項**:
- 不要 `git push --force` 或 `--force-with-lease`(除非使用者明確要求)。
- 若當前分支是 `main`/`master`,在 push 前用一句話告知使用者「即將推送到主分支」並繼續(不額外暫停,因為使用者呼叫 `/commit-push` 即視為授權)。

### Step 7：回報結果
push 成功後,輸出:
- Commit SHA (短版,7 碼)
- Commit message 第一行
- 推送到的 remote/branch
- 若 repo 有 GitHub remote,附上 commit URL(從 `git remote get-url origin` 推導,例如 `https://github.com/<owner>/<repo>/commit/<sha>`)

---

## 注意事項
- 整個流程的單一職責是「stage 指定路徑 → commit → push」,不做其他事(不開 PR、不建立 branch、不修改既有 commit)。
- 任何步驟失敗都要**停止**並完整回報錯誤,不要自動 fallback 或重試。
- 若 staged diff 為空(指定的路徑沒有任何變更),停止並提示「指定的路徑沒有需要 commit 的變更」,**不要**建立空 commit。
