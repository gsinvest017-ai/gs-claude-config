---
name: new-repo-push
description: 在當前路徑用 gh 建立新 GitHub repo，git init（若未初始化）、stage 所有檔案、commit、設 remote、push。當使用者輸入 /new-repo-push、說「幫我建新 repo」、「init 並 push 到 GitHub」、「gh 建 repo 然後 push」、「新開一個 GitHub repo 並把現在的東西推上去」時啟動。預設 public；加 --private 建私有 repo。
---

# /new-repo-push — 一鍵建 GitHub repo 並 push

在當前工作目錄建立新的 GitHub repo，把現有檔案 commit 後推上去。**全程繁體中文回報**。

## 0. 解析參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `<repo-name>` | 當前目錄名稱 | GitHub repo 名稱 |
| `--private` | 否（public） | 建立私有 repo |
| `--desc "<text>"` | 空 | repo 描述 |
| `--branch <name>` | `main` | 初始分支名 |
| `--no-commit` | 否 | 跳過 commit 步驟（只設 remote 並 push 現有 commits） |

範例 args：
- `""` → repo 名 = 當前目錄名，public
- `"my-project --private"` → 指定名稱，私有
- `"my-project --private --desc \"量化策略研究\""` → 加描述
- `"--branch master"` → 用 master 作初始分支

## 1. 前置確認

```powershell
# 取得當前目錄名
$REPO_NAME = Split-Path -Leaf (Get-Location)
# 若 args 有指定名稱，覆蓋
# 確認 gh 與 git 存在
gh --version
git --version
```

若 `gh` 不在 PATH → 提示安裝：`winget install GitHub.cli` 並停止。

確認 `gh auth status` 已登入 → 若未登入提示 `gh auth login` 並停止。

## 2. 檢查 git 狀態

```powershell
$IS_GIT = git rev-parse --is-inside-work-tree 2>$null
```

- 已是 git repo → 略過 `git init`，直接進步驟 3
- 非 git repo → 執行：
  ```powershell
  git init -b <branch>
  ```

## 3. 建立 .gitignore（若不存在）

若當前目錄沒有 `.gitignore`，偵測專案類型並建議最基本的 ignore（`__pycache__/`、`*.pyc`、`.env`、`node_modules/`、`.DS_Store` 等），**但不自動寫入**，只印出建議後繼續。

## 4. Stage 並 Commit（若有未提交的變更）

```powershell
$STATUS = git status --porcelain
```

- 若已有 commits 且 working tree clean → 略過 commit，跳到步驟 5
- 若 `--no-commit` → 略過，直接進步驟 5
- 否則：

```powershell
git add .
git commit -m "feat: 初始 commit

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Commit message 主體使用**繁體中文**（遵循 CLAUDE.md 規則）。

## 5. 在 GitHub 建立 repo

```powershell
$VISIBILITY = if ($PRIVATE) { "--private" } else { "--public" }
$DESC_FLAG = if ($DESC) { "--description `"$DESC`"" } else { "" }

gh repo create $REPO_NAME $VISIBILITY $DESC_FLAG --source=. --remote=origin --push
```

`--source=.` 告訴 gh 把當前目錄設為 source；`--push` 直接推第一個 commit。

若已存在同名 repo：
- 印出錯誤並提供選項：
  1. 改用不同名稱（提示重跑加新名稱）
  2. 若只想加 remote（repo 已存在）：`git remote add origin <url>` 然後 `git push -u origin <branch>`

## 6. 完成回報

成功後印出：

```
✓ 已建立 GitHub repo：<owner>/<repo-name>
  可見性：Public / Private
  URL：https://github.com/<owner>/<repo-name>
  分支：<branch>
  推送的 commit：<短 hash> — <message>

快速連結：
  Clone：git clone https://github.com/<owner>/<repo-name>
  在 GitHub 上開啟：gh repo view --web
```

## 錯誤處理

| 情況 | 處理方式 |
|------|---------|
| gh 未登入 | 提示 `gh auth login`，停止 |
| repo 名稱已存在 | 提示改名或手動 `git remote add` |
| 無網路 | gh 回傳錯誤時印出並停止 |
| 空目錄（0 檔案） | 警告「目錄為空，將只建立空 repo」，繼續 |
| git push 衝突 | 不 force push，提示手動解決 |

## 不要做的事

- ❌ 不要 `git push --force`
- ❌ 不要在沒確認的情況下刪除現有 remote
- ❌ 不要自動覆蓋已存在的 GitHub repo
- ❌ 不要 commit `.env`、`.env.local`、credentials 等敏感檔案（若 stage 時偵測到，警告並從 staging 移除）
