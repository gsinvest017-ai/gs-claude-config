# Subagents 安裝進度

## 目標
在 `~/.claude/agents/` 建立兩個 Claude Code subagent，使主 Claude 可在單一 prompt 內**並行**呼叫量化策略研究與審查流程（補足 slash command「一個 prompt 只能一個」的限制）。

兩個 agent：
- `quant-researcher` — 四階段量化策略研究（理論 → 文獻 → 回測 → 中文報告）
- `review-strategy` — Jane Street 等級五階段策略稽核（輸出 PASS / CONDITIONAL / FAIL）

來源於同名 slash skill（位於 `~/.claude/skills/quant-researcher` 與 `~/.claude/skills/review-strategy`），但封裝為 subagent 後可：
1. 同一回合並行啟動多個
2. 各自獨立 context，不互相污染
3. 可指定自己的工具 allow-list 與 model

## Milestones
- **M1**：在 `gs-claude-config/agents/` 寫入兩個 markdown（含 YAML frontmatter + system prompt 本體）
- **M2**：建立 `~/.claude/agents` symlink → `gs-claude-config/agents`（與既有 commands/skills 同一機制）
- **M3**：寫此進度檔，commit 新增檔案

## 進度日誌

### M1 — Agent 定義檔
寫入兩支 agent markdown：
- `agents/quant-researcher.md`（2128 bytes）
- `agents/review-strategy.md`（2385 bytes）

YAML frontmatter 採用標準格式：`name`, `description`, `tools`, `model`。Tools 採白名單方式，限制各 agent 只能用必要工具（research 含 Write/Edit/Bash，review 不含 Write）。

### M2 — Symlink
過程曲折：
1. 首次嘗試 `ln -s` from Git Bash，因 Windows 開發者模式 / MSYS 行為差異，創出來是**獨立目錄而非符號連結**（stat inode 不同、readlink 為空）
2. 移除後改用 `powershell.exe -NoProfile -Command "cmd /c mklink /D ..."`，成功建立 NTFS 符號連結
3. 驗證 `readlink /c/Users/User/.claude/agents` → `/c/Users/User/gs-claude-config/agents`，且 `ls -la` 顯示 `lrwxrwxrwx`，與既有 `commands`、`skills` symlink 一致

**Why mklink works while ln -s didn't**：MSYS 在沒有 `MSYS=winsymlinks:nativestrict` 或開發者模式不被 MSYS 識別時，會 fallback 成 copy。直接呼叫 `cmd /c mklink` 才能跳過這層 fallback、直接走 Win32 symlink API。

### M3 — 進度檔 + commit
此檔即為產出。commit 只加：
- `agents/quant-researcher.md`
- `agents/review-strategy.md`
- `docs/progress-subagents-setup.md`

跳過 repo 內既有 WIP（`chezmoi-source/.chezmoiignore` 與 `install.ps1` 等），避免污染本次 commit。

## Fallback / Rollback 指引

### 重建 symlink（如果 ~/.claude/agents 不見了）
```powershell
cmd /c mklink /D "C:\Users\User\.claude\agents" "C:\Users\User\gs-claude-config\agents"
```
Bash 端等價：先確認 PowerShell 通道，再透過 `powershell.exe -NoProfile -Command "..."` 包一層。**不要**直接用 `ln -s`，會 fallback 成 copy。

### 完全移除這次工作
```bash
rm /c/Users/User/.claude/agents  # 移除 symlink 本身
git -C /c/Users/User/gs-claude-config rm -r agents docs/progress-subagents-setup.md
git -C /c/Users/User/gs-claude-config commit -m "revert: subagents setup"
```

### 驗證 agents 確實被 Claude Code 載入
重啟 Claude Code，在新 session 輸入：
```
請列出目前可用的 subagent
```
應看到 `quant-researcher` 與 `review-strategy`，描述與本檔一致。

## 使用範例（並行呼叫）

```
請並行執行：
1. 用 quant-researcher 設計 RSI 動量策略（標的：TXF）
2. 用 quant-researcher 設計均值回歸策略（標的：MXF）
3. 用 review-strategy 審查 ~/gs-strategy/strategies/cubic_momentum_tx/strategy.md
```

主 Claude 會在同一 assistant turn 內送出 3 個 Task tool 呼叫，三個 subagent 並行跑，最後彙整摘要。

## 與既有 slash skill 的關係

`~/.claude/skills/quant-researcher` 與 `~/.claude/agents/quant-researcher` **是兩套機制、兩份檔案**：
- Slash skill 由使用者主動 `/quant-researcher` 呼叫，在主 context 線性執行
- Subagent 由主 Claude 委派（或使用者明說「用 X agent」），在獨立 context 執行，可並行

內容相似但**不共用檔案**，未來若要改邏輯需同時更新兩處。後續若有需要可考慮把核心 prompt 抽出來 include，目前先各自獨立。
