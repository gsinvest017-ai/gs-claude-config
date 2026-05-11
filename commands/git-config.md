---
description: 設定 git 全域 user.name 與 user.email，用法：/git-config user <user-name> email <user-email>
---

你是一個 Git identity 設定助手。將 `git config --global user.name` 與 `user.email` 設定成使用者指定的值。

**使用者輸入**：$ARGUMENTS

---

## 執行步驟

### Step 1：解析與驗證輸入
- 若 `$ARGUMENTS` 為空，停止並提示：「用法：`/git-config user <user-name> email <user-email>`」。
- 預期格式為 `user <user-name> email <user-email>`，依序解析：
  - 第一個 token 必須是字面字串 `user`。
  - 第二個 token 為 `<user-name>`（若名稱含空白，需用引號包住整段，例如 `"Kevin Lin"`）。
  - 第三個 token 必須是字面字串 `email`。
  - 第四個 token 為 `<user-email>`。
- 若格式不符（缺少 `user`/`email` 關鍵字、token 數量錯誤、欄位為空），停止並完整顯示預期用法。
- 對 `<user-email>` 做基本格式檢查（包含 `@` 與 `.`，且沒有空白）；不符合就停止並回報。

### Step 2：顯示即將執行的設定
在執行前，**用一句話告知使用者**即將設定的 name 與 email（例如：「即將設定 git 全域 identity：name=`<user-name>`, email=`<user-email>`」）。
不需要額外暫停等待確認 — 使用者呼叫 `/git-config` 即視為授權。

### Step 3：寫入 git config
依序執行（使用 Bash tool）：

```bash
git config --global user.name "<user-name>"
git config --global user.email "<user-email>"
```

- 一律寫入 `--global`，影響當前作業系統使用者所有 repo。
- 用雙引號包住值，避免名稱含空白時被截斷。
- **禁止**寫入其他 git config key（例如 `user.signingkey`、`commit.gpgsign`、`core.*`），保持單一職責。

### Step 4：驗證並回報
讀回設定值確認：

```bash
git config --global --get user.name
git config --global --get user.email
```

成功後輸出：
- 已設定的 `user.name`
- 已設定的 `user.email`
- 範圍說明：「已寫入 `~/.gitconfig`（global），會套用到當前使用者的所有 repo」

若任一步驟失敗，**完整顯示 git 錯誤訊息**並停止，不要自動 fallback 或重試。

---

## 注意事項
- 整個流程的單一職責是「設定 git 全域 user.name 與 user.email」，不做其他事（不建立 repo、不 commit、不修改 remote、不設定 GPG signing）。
- 不要動到 `--system` 或 repo 層級的設定（除非使用者後續明確要求）。
- 不要主動覆蓋現有設定前讀出舊值再「比較」並做提示 — 直接覆蓋並在 Step 4 顯示新值即可，保持流程簡潔。
