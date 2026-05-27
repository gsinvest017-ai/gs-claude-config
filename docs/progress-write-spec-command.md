# 進度：新增 /write-spec 全域 slash command

## 目標

在 `gs-claude-config`（= `~/.claude` 的 chezmoi 來源）新增一個 **system-level global agent command `/write-spec`**：在任一專案 repo 內觸發時，分析該 repo 的**架構與功能模組**，產生 / 更新 **Claude agent spec 規則檔（CLAUDE.md 及其拆分檔）**，且寫法要讓 Claude **確實遵守**；支援**拆分成多個檔案**（root CLAUDE.md + `@import` 主題檔 / 各模組 nested CLAUDE.md）。完成後安裝到 user-scope（全域）。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/write-spec` skill | `docs/progress-write-spec-command.md`、`skills/write-spec/SKILL.md` |
| **M2** | 驗證全域註冊 + 收尾 | frontmatter 解析通過、出現在 skill 清單、進度檔收尾、最終報告 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /write-spec

- 建立本進度檔（目標 / milestone / fallback）。
- 新增 `skills/write-spec/SKILL.md`：frontmatter（name + description + 觸發語）+ 10 段流程：解析參數 → 盤點既有 spec → 分析架構 → 分析功能模組 → 拆分策略決策樹 → **「讓 Claude 確實遵守」的寫作守則** → spec 骨架範本 → 寫檔/合併（區塊標記保留人工內容）→ 驗證（@import 路徑、root 行數、矛盾）→ 完成回報；含不要做的事、邊界情況、跨 skill 協作、全域註冊說明。
- 關鍵設計決策：
  1. **可遵守性**靠「祈使句 + 確切指令 + 重點前置 + 不寫廢話」，並強調 root 越精簡越會被完整遵守。
  2. **多檔拆分**對應 Claude Code 的兩種機制——root `CLAUDE.md` 的 `@相對路徑` import，與子目錄 nested `CLAUDE.md`（在該子樹工作才載入）；`--split auto` 依 repo 規模決策。
  3. **update 預設不覆蓋人工內容**，用 `<!-- BEGIN/END write-spec: <section> -->` 區塊標記只更新自己維護的段落。
- 兩檔正規化為 CRLF（與既有 skill 一致）。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`，remote `origin` = github.com/gsinvest017-ai/gs-claude-config.git。
- 本任務**只 commit 到本機 `main`，不 push**。
- Rollback：`git -C C:\Users\User\gs-claude-config log --oneline` 找 `Mn:` commit，`git reset --hard <hash>` 回退。
- 整個撤掉：刪 `skills/write-spec/`、本進度檔，再 `git checkout -- .`。
- 新 skill 通常即時出現在 available-skills 清單；若沒有，開新的 Claude Code session 即可。
