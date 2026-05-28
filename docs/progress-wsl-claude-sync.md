# 進度：WSL 端套用 Method 1（symlink 到 Windows 端），再評估 Method 3

## 目標

讓 WSL Ubuntu-24.04 的 system-level Claude（`~/.claude/`）所見的 skills / commands / agents / 全域 CLAUDE.md 與 Windows 端**同一份來源**，且能即時看到 Windows 端新加 / 修改的 skill，不再有兩個 clone 各自漂移的問題。

執行順序：
1. **M1**：在 WSL 端套用 Method 1（symlink `~/.claude/{skills,commands,agents,CLAUDE.md}` → `/mnt/c/Users/User/gs-claude-config/`），保留原 Linux clone 不刪。
2. **M2**：比較目前 Windows / WSL 兩端 system global skills/commands 的差異——主要是 Linux 端原本獨有的 commits 與未 commit 內容、以及 Windows 端 session 新加的 6 個 skill。
3. **M3**：根據 M2 找到的差異類型，決定要不要套用 Method 3（chezmoi 模板化），給出具體方案。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | WSL symlink 切換 + 驗證 | WSL `~/.claude/{skills,commands,agents,CLAUDE.md}` 都指向 `/mnt/c/...`；WSL 看得到 Windows 端 16 個 skill |
| **M2** | 兩端內容差異盤點 | 進度檔列出 Linux-only commits / 檔案 vs Windows-only；分類差異性質（漂移 vs OS 相關） |
| **M3** | Method 3 決策 | 結論：是否導入 chezmoi 模板；若否，給出輕量 sync 方案 |

## 進度日誌

### M1 — WSL symlink 切到 Windows clone（完成）

**Before**：WSL `~/.claude` 有自家 symlink 指向 `/home/kevin/gs-claude-config/`（Linux 本地 clone）；缺 `agents` symlink。Linux clone 與 Windows clone **diverged**：
- Linux head：`4395279 fix: register lean skills via skills/<name>/SKILL.md`，獨有已 commit 的 `lean-prove` / `lean-explain` / `lean-mil`；untracked 的 `commands/update-doc.md` / `skills/update-doc/` / `skills/web-snapshot/`。
- Windows head：`1d51f21 feat: add /set-serve-eth skill`，獨有本 session 新加的 6 個 skill（`one-button-launch`、`platform-compatible`、`write-spec`、`ui-compact`、`copy-commits-button`、`set-serve-eth`）。

**動作**：
```bash
# WSL
rm ~/.claude/skills ~/.claude/commands ~/.claude/CLAUDE.md   # 三個舊 symlink
ln -s /mnt/c/Users/User/gs-claude-config/skills    ~/.claude/skills
ln -s /mnt/c/Users/User/gs-claude-config/commands  ~/.claude/commands
ln -s /mnt/c/Users/User/gs-claude-config/agents    ~/.claude/agents     # 補上原本沒有的
ln -s /mnt/c/Users/User/gs-claude-config/CLAUDE.md ~/.claude/CLAUDE.md
```
**未刪** `/home/kevin/gs-claude-config/`——原 Linux clone 完整保留在磁碟上，供 M2 比對 / M3 決策使用。

**驗證**：
- 四個 symlink resolve `[OK]`
- WSL 端可列出 16 個 skill（與 Windows 一致），含 6 個 session 新增
- `wc -l /home/kevin/.claude/skills/set-serve-eth/SKILL.md` = 239 行，與 Windows 端剛 commit 的檔案吻合

**caveats（不阻塞，待 M2 評估）**：
- Linux clone 獨有的 `lean-*` skill 與未 commit WIP 暫時「對 WSL Claude 不可見」（symlink 切走了），但檔案仍在 disk
- `settings.json` / `.credentials.json` 等 per-host 狀態檔**故意**不 symlink，兩端各自獨立

<!-- M2 / M3 待續 -->

### M2 — Windows / WSL system global skills/commands 差異盤點

**diff 表**：

| 類別 | Linux-only | Windows-only | 共有數 |
|------|-----------|-------------|--------|
| skills   | `lean-explain`、`lean-mil`、`lean-prove`、`update-doc`*、`web-snapshot`* | `autogo`、`cc-insights`、`copy-commits-button`、`one-button-launch`、`platform-compatible`、`prog-lang-tutor`、`set-serve-eth`、`ui-compact`、`write-spec` | 7 |
| commands | `lean-explain.md`、`lean-mil.md`、`lean-prove.md`、`update-doc.md`* | `prog-lang-tutor.md` | 11 |
| agents   | (無) | (無) | 5 |

*打星號 = Linux 端未 commit 的 WIP（不在本次合併範圍內）。

**Git 史**：兩邊 `main` 真的 diverged——Windows clone 連 Linux 那條 commit chain 都沒 fetch 過（`merge-base` 直接 fail），代表兩個 clone 從某個共同祖先各自往不同方向走。

**OS-specific 內容掃描結論**：差異**幾乎沒有**「另一個 OS 上會壞」的硬內容。出現在 skill 文字裡的 `C:\Users\...` / `/home/...` / `PowerShell` 大多是**註解、範例、跨平台對照**，不是 runtime 路徑。**真正只在單一 OS 才有意義的 skill**（會「在另一 OS 上觸發但沒效」）：
- `cc-insights`（呼叫 `Invoke-CCInsights.ps1` → Windows-only）
- `language-tutor`（TTS 走 `speak.ps1` → Windows-only）
- `autogo`（瞄準 Windows desktop / OCR → Windows-only）
- `lean-*`（Linux 上 Lean4 / Mathlib 開發較常見，但 skill 本身是 markdown，跨 OS 可載入）

**結論**：分歧不是 **OS-difference**，是 **sync drift**（兩個 clone 各自 commit 沒互相 push/pull）。


## Fallback 指引

- 全部還原成「WSL 用自家 Linux clone」：
  ```bash
  rm ~/.claude/skills ~/.claude/commands ~/.claude/agents ~/.claude/CLAUDE.md
  ln -s /home/kevin/gs-claude-config/skills    ~/.claude/skills
  ln -s /home/kevin/gs-claude-config/commands  ~/.claude/commands
  ln -s /home/kevin/gs-claude-config/CLAUDE.md ~/.claude/CLAUDE.md
  # agents 原本沒有，依需要決定是否補
  ```
- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`。
- 本任務只 commit progress doc 到本機 main，不 push。
