# Progress — chezmoi-ready dotfile repo + Windows support

Started: 2026-05-15
Trigger: `/safe-yolo 是建一個 chezmoi-ready 的私人 dotfile repo 結構 (因為我是要將我的設定可以快速遷移給我大量同事用)`

## 目標

把 `gs-claude-config` 從「Linux/macOS bash-only install + 個人 CLAUDE.md hardcode」升級為：

1. **chezmoi-native** 部署路徑，支援 per-user template（每位同事的 name/email/role 在 init 時 prompt）
2. **Windows 第一公民**：新增 install.ps1、PowerShell profile template、winget-based bootstrap script
3. **保留現有 install.sh + symlink 工作流不變**（你個人機沒影響）
4. **個人專案資訊不再硬編進公開 repo 給同事看到**（templates/CLAUDE.example.kevin.md 改成範例參考，repo CLAUDE.md 維持現狀避免破壞既有 symlink，標記為 follow-up tech debt）

## 計畫 milestone

- **M1** — housekeeping + chezmoi 骨架（.chezmoiroot, .chezmoi.toml.tmpl, .chezmoidata/defaults.yaml, dot_claude/CLAUDE.md.tmpl, dot_claude/settings.json.tmpl）
- **M2** — Personal vs shared 分離（templates/CLAUDE.example.kevin.md）
- **M3** — chezmoi-source 擴充 PowerShell profile + OS conditional .chezmoiignore + WT 手動設定 doc
- **M4** — Windows install.ps1 + chezmoi run_onchange_install-deps.{ps1,sh}.tmpl bootstrap scripts
- **M5** — README 更新（chezmoi quick start）+ 此進度檔 + final commit

## Fallback 指引

若要 rollback：

```bash
cd ~/gs-claude-config
git log --oneline | head -10        # 找到 M1 之前的 commit hash
git reset --hard <pre-M1-hash>      # 重置（危險：丟掉所有 M1~M5 變更）
```

若只想 disable chezmoi 路徑：刪 `.chezmoiroot` + `chezmoi-source/`，install.sh / install.ps1 仍可獨立運作。

## 進度日誌

### M0 — pre-flight housekeeping

- 設 repo-local git user：`Kevin (gsinvest017) <gsinvest017@gsinvest.com.tw>`
- Commit `commands/save-to-obsidian.md`（先前 untracked）→ `d42e174`
- Commit `skills/save-to-obsidian/SKILL.md`（中途發現也是 untracked）→ `c21856b`

### M1 — chezmoi 骨架 → `db3953f`

新檔：

```
.chezmoiroot
chezmoi-source/.chezmoi.toml.tmpl
chezmoi-source/.chezmoidata/defaults.yaml
chezmoi-source/.chezmoiignore
chezmoi-source/dot_claude/CLAUDE.md.tmpl
chezmoi-source/dot_claude/settings.json.tmpl
```

關鍵設計決策：
- `.chezmoiroot` 指向 `chezmoi-source` 子目錄，所以 chezmoi 只看那個子樹，不影響 repo 根目錄的 install.sh / commands/ / skills/
- `.chezmoi.toml.tmpl` 用 `promptStringOnce` / `promptBoolOnce` 在 `chezmoi init` 時詢問 7 個值：name / email / githubUser / role / editor / installFonts / installCron
- 用 `toJson` 渲染 list/map（避免手寫 comma 邏輯出錯）— `settings.json.tmpl` 通過 `python -m json.tool` 驗證
- 安裝 chezmoi v2.70.3 (winget user-scope) 並用 `chezmoi execute-template` 驗證 templates render

問題：使用者 chezmoi.os 在 `[chezmoi]` config 覆寫無效，是 runtime auto-detected，所以無法在 Windows 機器上完整 mock POSIX render — 接受此限制。

### M2 — Personal vs shared 分離 → `5658311`

新檔：

```
templates/CLAUDE.example.kevin.md   (Kevin 的個人 CLAUDE.md 內容，加 header 標明僅供參考)
templates/README.md
```

未做（**follow-up tech debt**）：
- `gs-claude-config/CLAUDE.md` 至今仍是 Kevin 個人專案列表，且被 symlink 到 `~/.claude/CLAUDE.md`。同事走 install.sh 路徑會 inherit 這份檔案 → 公開 repo 暴露個人專案資訊。
- 真正修法：把 repo-root CLAUDE.md 改成 generic skeleton（同 chezmoi 模板），把 Kevin 個人機器遷移到 chezmoi 路徑。
- 本次不改，避免立即破壞使用者個人 Claude Code 體驗。

### M3 — PowerShell profile + WT doc → `de539eb`

新檔：

```
chezmoi-source/Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl
chezmoi-source/docs/windows-terminal-setup.md
```

改檔：

```
chezmoi-source/.chezmoiignore   (加 OS-conditional pattern)
```

設計決策：
- PowerShell profile 全量複製 ~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 的內容（fish-like：PSReadLine + oh-my-posh + PSFzf + zoxide），把硬編的 theme filename 替換為 `{{ .terminal.ohMyPoshTheme | quote }}`。
- WT settings.json **不**模板化 — 混雜 per-machine GUID（WSL distro、default profile），自動覆寫風險太高。改為提供 `docs/windows-terminal-setup.md` 講解一鍵手動設定字型（`CaskaydiaCove NFM`）。未來可加 `modify_*.ps1.tmpl` 用 JSON merge 而非整檔覆寫。
- `.chezmoiignore` 是 chezmoi template，用 `{{ if ne .chezmoi.os "windows" }}` 把 `Documents/PowerShell/**` 跟 `AppData/**` 在 POSIX 上 ignore。

### M4 — Windows install.ps1 + chezmoi bootstrap → `65c55e4`

新檔：

```
install.ps1                                              (legacy 路徑的 Windows 版)
chezmoi-source/run_onchange_install-deps.ps1.tmpl        (Windows chezmoi bootstrap)
chezmoi-source/run_onchange_install-deps.sh.tmpl         (POSIX chezmoi bootstrap)
```

關鍵實作細節：
- `install.ps1` 用 `cmd /c mklink /D` 建 symlink（**不**用 `New-Item -ItemType SymbolicLink`，因為它在 Dev Mode 下會 silently 失敗 — 來自使用者 memory）。
- chezmoi bootstrap 用 `run_onchange_` prefix（不是 `run_once_`），這樣 bump script body 內的 `$ScriptVersion` 就會強制下次 apply 重跑。
- bootstrap 流程：winget install pwsh + oh-my-posh + git + gh + fzf + zoxide → 字型 install（gated on `.installFonts`）→ clone quant-research-skill → symlink commands/skills（chezmoi 管 CLAUDE.md/settings.json/profile 作 rendered files，但 commands/skills 用 symlink 讓 contributor edit + `git pull` 立即生效）
- `.chezmoiignore` patterns 改用 **target name**（`install-deps.ps1`）而不是 source filename — chezmoi 在 evaluate ignore rule 時已把 `run_onchange_` prefix 剝掉。
- 每個 script 內部還有 OS early-exit guard 做 defense in depth。
- 用 `chezmoi managed --include=scripts` / `--include=files` 驗證 chezmoi 正確識別 script vs file（早期被 `apply --dry-run --verbose` 的 diff output 誤導以為 chezmoi 把 script 當 file，後來確認那是 chezmoi 顯示 script 內容的方式）。

### M5 — README + 進度檔 → this commit

README 加入 chezmoi quick-start section、Windows-specific 指引、與 install.sh/install.ps1 路徑的對比表。

## 未推送的 commits

```
65c55e4 M4: Windows install.ps1 + chezmoi run_onchange bootstrap scripts
de539eb M3: chezmoi-source PowerShell profile + OS-conditional ignore
c21856b chore: commit save-to-obsidian skill body (paired with M0's slash command)
5658311 M2: extract personal CLAUDE.md as templates/CLAUDE.example.kevin.md
db3953f M1: add chezmoi-source skeleton (per-user template layer)
d42e174 M0: add save-to-obsidian slash command
74b3636 M2: wire prettify modules into PS7 profile and verify  ← pre-existing
c01626c M1: install Terminal-Icons / posh-git / oh-my-posh     ← pre-existing
```

`origin/main` 落後 8 個 commits（這次 6 個 + 之前 2 個 prettify-related）。Push 前請使用者確認 — 特別是 `gs-claude-config` 是公開 GitHub repo (`gsinvest017-ai`)，這次推送會讓全公司 GitHub 看見。

## 給同事的 onboarding 一行指令（push 後可用）

Windows（推薦）：

```powershell
winget install --id twpayne.chezmoi --scope user -e
chezmoi init --apply https://github.com/gsinvest017-ai/gs-claude-config.git
```

macOS / Linux：

```bash
brew install chezmoi   # or: sh -c "$(curl -fsLS get.chezmoi.io)"
chezmoi init --apply https://github.com/gsinvest017-ai/gs-claude-config.git
```

期間會 prompt 7 個問題（name / email / GitHub username / role / editor / install Nerd Font? / install nightly cron?）— 全部按 enter 也可以用預設值。
