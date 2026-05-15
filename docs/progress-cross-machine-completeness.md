# Progress — Cross-machine migration completeness

Started: 2026-05-15
Trigger: `/safe-yolo 先做1跟2` (follow-up to chezmoi-bootstrap discussion)

## 目標

把 chezmoi 遷移路徑的兩個漏洞補起來，讓「Windows → Ubuntu」這個情境真的能一鍵完成：

1. **language-tutor 三檔案 commit 進 repo** — 之前 untracked，不 commit 就不會跟著 chezmoi 過去
2. **新增 `scripts/clone-all.sh` + `repos.txt.example`** — chezmoi 不管專案 repos，這個腳本補位

## 計畫 milestone

- **M1** — Commit `agents/language-tutor.md`、`commands/language-tutor.md`、`skills/language-tutor/`
- **M2** — 新增 `scripts/clone-all.sh`、`scripts/repos.txt.example`、`.gitignore` 加 `scripts/repos.txt`
- **M3** — README 加 "What chezmoi does NOT clone" 段落 + 此進度檔 + final commit

## Fallback 指引

若要 rollback：

```bash
cd ~/gs-claude-config
git log --oneline | head -5    # 找到 M1 之前的 commit hash（應是 371656b）
git reset --hard 371656b       # 危險：丟掉 M1~M3 的三個 commit
```

若只想 disable `clone-all.sh`：直接不要建 `scripts/repos.txt` 即可，腳本會 exit 1 並提示用法。

## 進度日誌

### M1 — language-tutor commit → `546de85`

新增 6 files：
- `agents/language-tutor.md`（sub-agent 入口）
- `commands/language-tutor.md`（slash command 入口）
- `skills/language-tutor/SKILL.md`（教學 SOP 主體）
- `skills/language-tutor/PROGRESS.md`（先前 skill 開發進度）
- `skills/language-tutor/scripts/speak.ps1`（Windows SAPI TTS）
- `skills/language-tutor/scripts/speak-edge.py`（edge-tts neural voice）

**Known limitation**：TTS 腳本是 Windows-specific（PowerShell SAPI + edge-tts Windows distribution）。Linux/macOS 上 skill 仍能 load，但 `speak.ps1` 呼叫會失敗 — skill 內已寫「TTS 失敗訊息顯示後繼續教學」的容錯。

Path hardcoding：`agents/language-tutor.md` 與 `commands/language-tutor.md` 內的 SKILL.md 路徑是 `C:\Users\User\.claude\skills\language-tutor\SKILL.md`（Windows 絕對路徑）。這在 Ubuntu 上會壞 — 列為後續 tech debt，不在本次 scope。修法：改成 `~/.claude/skills/language-tutor/SKILL.md` 並讓 Claude Code 自動展開。

### M2 — clone-all.sh + repos.txt.example → `16a79c9`

新增 3 files / 改 1 file：
- `scripts/clone-all.sh`（POSIX bash，可執行）
- `scripts/repos.txt.example`（範例 + 格式說明）
- `.gitignore` 加 `scripts/repos.txt`（per-machine list 不入版控）

設計決策：
- 格式：`<git-url>` 或 `<git-url> <dest-path>` 兩種，`#` 註解、空白行 ignore
- 預設 dest 是 `$HOME/<basename>`（去 `.git` 副檔名）
- Idempotent：dest 已存在直接 skip（不 pull、不 merge）
- 容錯：單一 repo clone 失敗不中斷，最後印 summary（`cloned / skipped / failed`）有任何 failed 就 exit 1
- `DRY_RUN=1` 環境變數印出 action 不執行 — 與 night-shift script 一致風格
- 不寫 `.ps1` 版本：PowerShell 直接 `git clone` 就好，少維護成本

Smoke test：本機 `DRY_RUN=1 bash scripts/clone-all.sh` 跑通 5 行 example，正確識別已存在的 `~/quant-research-skill` 並 skip。

### M3 — README + 進度檔 → this commit

README 在 chezmoi quick-start 之後加兩節：
- 「What chezmoi does NOT clone — use `scripts/clone-all.sh`」（含 cp/edit/run 三步）
- 「Things chezmoi deliberately won't migrate」表格（credentials / SSH key / system config / 暫存）

## 未推送的 commits

```
<this>   M3: README clone-all section + cross-machine progress doc
16a79c9  M2: add scripts/clone-all.sh + repos.txt.example for batch repo clone
546de85  M1: commit language-tutor skill + slash command + sub-agent
371656b  M5: README chezmoi quick-start + progress doc  ← pre-existing, still unpushed
65c55e4  M4: Windows install.ps1 + chezmoi run_onchange bootstrap scripts  ← pre-existing
06832a4  M1-3: add quant-researcher + review-strategy subagents  ← pre-existing
de539eb  M3: chezmoi-source PowerShell profile + OS-conditional ignore  ← pre-existing
c21856b  chore: commit save-to-obsidian skill body  ← pre-existing
5658311  M2: extract personal CLAUDE.md as templates/CLAUDE.example.kevin.md  ← pre-existing
db3953f  M1: add chezmoi-source skeleton  ← pre-existing
d42e174  M0: add save-to-obsidian slash command  ← pre-existing
```

`origin/main` 目前落後 11 commits。Push 前需使用者確認（公開 repo `gsinvest017-ai/gs-claude-config`）。

## 後續建議（不在本次 scope）

1. **修 language-tutor 的 Windows 絕對路徑** — 改用 `~/.claude/skills/language-tutor/...`，讓 Ubuntu 也能 load
2. **語言教家教在 Linux 的 TTS 替代** — 可改用 `espeak-ng` 或 `piper`，加 `speak-linux.sh` 並讓 SKILL.md 依 OS 分派
3. **gs-claude-config 根目錄 CLAUDE.md** — 仍是 Kevin 個人專案列表（M2 of chezmoi-bootstrap 已標為 tech debt），公開 repo 暴露專案資訊。建議改成 generic skeleton，個人專案資訊全部走 chezmoi template
