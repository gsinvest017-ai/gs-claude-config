# safe-yolo: autogo hook pipeline 根本修復 + SKILL.md v2 改進

## 目標
1. 修 hook pipeline 的 cmd.exe UTF-8 encoding root cause（改用 PowerShell 原生 pipe + @winArgs splatting）
2. SKILL.md 補四項行為改進：空間排序描述、stub 偵測提示、filter 透明度、通用查詢 preview-first

## 計畫 milestone

- [x] M1：autogo-prefetch.ps1 — 移除 cmd.exe pipe，改用 PowerShell 原生 pipe + @winArgs splatting
- [ ] M2：SKILL.md — 四項行為改進
- [ ] M3：進度檔更新 + commit

## 根因分析（M1）
cmd.exe /c 指令：
1. 以非 UTF-8 code page piping context_cli → context_summary
2. Chinese JSON chars 在 pipe 中被錯誤解碼，context_summary 讀到 surrogates
3. sys.stdout.write(format_full_json_block(payload)) 丟 UnicodeEncodeError
4. [autogo-json] 塊未被寫出 → Claude 收不到 filter_aliases

修法：@winArgs PowerShell splatting + 直接 PS pipe → 完全繞過 cmd.exe encoding 問題

## 進度日誌

### M1 — 移除 cmd.exe，改 PowerShell 原生 pipe

移除 $winArgsCmd 建構邏輯（cmd 格式 quoted string），
改用 @winArgs splatting + `| & $py` PowerShell pipe。

## Fallback 指引
- rollback: `git revert HEAD` 在 gs-claude-config repo
- 影響檔案：~/.claude/hooks/autogo-prefetch.ps1、~/.claude/skills/autogo/SKILL.md
