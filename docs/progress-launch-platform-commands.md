# 進度：新增 /one-button-launch 與 /platform-compatible 兩個全域 slash command

## 目標

在 `gs-claude-config`（= `~/.claude` 的 chezmoi 來源）新增兩個 **agent command（skill）**，讓它們對所有專案全域可用：

1. **`/one-button-launch`** — 對「尚未具備一鍵啟動機制」的 repo，偵測技術棧並產生一個跨平台單一入口啟動器（install → build → migrate → run 一條龍，含 `run.sh` + `run.ps1`）。
2. **`/platform-compatible`** — 稽核並（在 `--fix` 時）修正 repo 的平台相依問題，使其同時可在 Windows / Linux(/macOS) clone、安裝、執行；並安裝到 user-scope（全域）。

兩支 skill 都遵循既有 skill 慣例：`skills/<name>/SKILL.md`、frontmatter 含 `name` + `description`、檔案以 CRLF 換行、全程繁體中文回報。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/one-button-launch` | `docs/progress-launch-platform-commands.md`、`skills/one-button-launch/SKILL.md` |
| **M2** | `/platform-compatible` | `skills/platform-compatible/SKILL.md` |
| **M3** | 驗證全域註冊 + 收尾 | 兩支 frontmatter 通過解析、進度檔收尾、最終報告 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /one-button-launch

- 建立本進度檔（目標 / milestone 計畫 / fallback 指引）。
- 新增 `skills/one-button-launch/SKILL.md`：frontmatter（name + description + 觸發語）+ 9 段流程（解析參數 → 偵測既有啟動機制 → 偵測技術棧 → 推導啟動序列 → 選啟動器形式 → run.sh/run.ps1 範本 → 串接文件 → 驗證不啟長時服務 → 完成回報），含「不要做的事」、邊界情況、跨 skill 協作。
- 兩檔已正規化為 CRLF（與既有 skill 慣例一致）。
- 驗證：`one-button-launch` 已即時出現在 available-skills 清單，無需 restart。
- 決策：auto 模式一律同時產 `run.sh` + `run.ps1` 作為跨平台最低基準，而非只賭目標機有 make/just/docker。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`，remote `origin` = github.com/gsinvest017-ai/gs-claude-config.git。
- 本任務**只 commit 到本機 `main`，不 push**（push 屬 safe-yolo 強制停下的外部操作）。
- Rollback：每個 milestone 一個 `Mn:` commit。`git -C C:\Users\User\gs-claude-config log --oneline` 找到對應 hash，`git reset --hard <hash>` 即可回退。
- 要整個撤掉：刪 `skills/one-button-launch/`、`skills/platform-compatible/`、本進度檔，再 `git checkout -- .`。
- 新 skill 要在 slash command 選單出現，可能需要開新的 Claude Code session（skill 清單在啟動時載入）。
