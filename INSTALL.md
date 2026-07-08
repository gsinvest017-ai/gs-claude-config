# Installing gs-claude-toolkit

Two ways for **anyone** to install this library of Claude Code skills, slash
commands, subagents, and the autopilot hooks. Pick whichever fits — they can
coexist.

> These are the **consumer** install paths. The repo's `install.sh` /
> `install.ps1` and the chezmoi flow are the **author's** personal
> cross-machine sync (they symlink a personal `CLAUDE.md`, clone a personal
> fork, and set personal `additionalDirectories`) — not what you want as a new
> user. Use the two paths below instead.

**Requirements:** `git`, and `node` (bundled with Claude Code — already on your
machine). No `jq`, no admin, no Windows Developer Mode.

---

## Option A — Claude Code plugin (recommended, most "one-click")

Native to Claude Code. Inside a Claude Code session:

```
/plugin marketplace add gsinvest017-ai/gs-claude-config
/plugin install gs-claude-toolkit@gs-claude-toolkit
```

Or run `/plugin`, pick **Browse marketplaces → gs-claude-toolkit**, and install
from the menu. Restart when prompted.

This registers all skills, commands, agents, and the autopilot hooks under the
plugin — **without** copying anything into your `~/.claude/` or touching your
`settings.json`. Disable/remove anytime from the `/plugin` menu.

**One caveat:** a plugin can't raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, so
`/autopilot` continuations are capped at Claude Code's built-in limit. If you
want the full 50-round autopilot, either add `"env": {
"CLAUDE_CODE_STOP_HOOK_BLOCK_CAP": "60" }` to your `settings.json`, or use
Option B (which sets it for you).

---

## Option B — install script (universal, remote one-liner)

Copies the skills/commands/agents into `~/.claude/` and wires the autopilot
hook into your `settings.json`. Works outside a Claude Code session and doesn't
require the plugin system.

**macOS / Linux / WSL:**

```bash
curl -fsSL https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-toolkit.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-toolkit.ps1 | iex
```

Or clone first and run locally with flags:

```bash
git clone https://github.com/gsinvest017-ai/gs-claude-config.git
cd gs-claude-config
./install-toolkit.sh              # or:  .\install-toolkit.ps1
```

### What it does — and what it never touches

- **Copies** each item in `commands/`, `skills/`, `agents/` into the matching
  `~/.claude/` folder (default; use `--link` / `-Link` to symlink instead).
- Copies `autopilot.mjs` into `~/.claude/hooks/` and **merges** its two hook
  entries + the block-cap env into `settings.json` — idempotently, preserving
  every other key and any hooks you already have.
- Any pre-existing same-named item is **backed up** to
  `~/.claude/backups/toolkit-<timestamp>/` first.
- **Never** overwrites your `settings.json` wholesale and **never** installs a
  `CLAUDE.md` — your global instructions stay yours.

### Flags

| POSIX | Windows | Effect |
|-------|---------|--------|
| `--link` | `-Link` | Symlink instead of copy (for contributors; Windows needs Dev Mode) |
| `--no-hooks` | `-NoHooks` | Skip the autopilot hook + settings merge |
| `--dir <path>` | `-Dir <path>` | Install from a local checkout instead of cloning |
| `--repo-url <url>` | `-RepoUrl <url>` | Override the clone URL (e.g. your fork) |
| `--branch <name>` | `-Branch <name>` | Branch to clone (default `main`) |

Passing flags over the pipe on Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/gsinvest017-ai/gs-claude-config/main/install-toolkit.ps1))) -NoHooks
```

### Uninstall

```bash
./uninstall-toolkit.sh            # or:  .\uninstall-toolkit.ps1
```

Removes only the items this toolkit installed (matched by name), the
`autopilot.mjs` hook, and the autopilot entries in `settings.json`. Your
backups under `~/.claude/backups/` are left in place.

---

## 中文摘要

兩條「一鍵安裝」路徑，二選一或並存：

- **A. Claude Code plugin（推薦、最一鍵）**：在 Claude Code 內執行
  `/plugin marketplace add gsinvest017-ai/gs-claude-config` 再
  `/plugin install gs-claude-toolkit@gs-claude-toolkit`。skills/commands/agents/hooks
  全由 plugin 管理，**不動**你的 `~/.claude/` 與 `settings.json`。唯一限制：plugin
  無法調高 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`，`/autopilot` 續跑會受 Claude Code 內建
  上限；要跑滿 50 次請自行在 `settings.json` 加該 env，或改用 B。

- **B. 安裝腳本（通用、遠端一行）**：
  - macOS/Linux/WSL：`curl -fsSL .../install-toolkit.sh | bash`
  - Windows：`irm .../install-toolkit.ps1 | iex`
  - 預設 **copy 模式**（不需 Dev Mode）；把 commands/skills/agents 複製進
    `~/.claude/`，並把 autopilot hook **安全併入** `settings.json`（不覆蓋你既有設定、
    不裝 `CLAUDE.md`）。同名項目先備份到 `~/.claude/backups/`。
  - 解除安裝：`./uninstall-toolkit.sh`（或 `.\uninstall-toolkit.ps1`）。

需求：`git` 與 `node`（Claude Code 已內建）。不需要 `jq`、不需要管理員權限。
