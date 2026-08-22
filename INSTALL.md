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

Native to Claude Code. The marketplace ships **two** plugins so the invasive
bit (a hook) is opt-in:

| Plugin | Contains | Hook footprint |
|--------|----------|----------------|
| `gs-claude-toolkit` | 42 skills, 20 commands, 5 agents | **none** — fully passive |
| `gs-autopilot` | the `/autopilot` Stop-hook | registers a Stop hook that runs each turn-end |
| `gs-meta-harness` | `branch-guard` + `context-inject` (Node) | registers a PreToolUse hook (`Bash`/`PowerShell`) and a SessionStart hook |

Inside a Claude Code session:

```
/plugin marketplace add gsinvest017-ai/gs-claude-config
/plugin install gs-claude-toolkit@gs-claude-toolkit      # skills/commands/agents, zero hooks
/plugin install gs-autopilot@gs-claude-toolkit           # OPTIONAL — only if you want /autopilot
/plugin install gs-meta-harness@gs-claude-toolkit         # OPTIONAL — protected-branch guard + gs-harness context
```

Or run `/plugin`, pick **Browse marketplaces → gs-claude-toolkit**, and install
from the menu. Restart when prompted.

Plugins install into `~/.claude/plugins/` — **nothing** is copied into your
`~/.claude/skills` etc. and your `settings.json` is not rewritten. Plugin
commands/skills are namespaced (`/gs-claude-toolkit:safe-yolo`), so they never
collide with your own. Disable/remove anytime:

```
/plugin disable gs-autopilot@gs-claude-toolkit           # keep installed, stop the hook
/plugin uninstall gs-claude-toolkit@gs-claude-toolkit    # remove entirely
/plugin marketplace remove gs-claude-toolkit             # drop the whole catalog
```

**Autopilot caveat:** a plugin can't raise `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`,
so `/autopilot` continuations are capped at Claude Code's built-in limit. For
the full 50-round autopilot, either add `"env": {
"CLAUDE_CODE_STOP_HOOK_BLOCK_CAP": "60" }` to your `settings.json`, or use
Option B (which sets it for you).

### gs-meta-harness — what it does on a machine with no gs-harness

The plugin bundles two independent hooks, and only one of them has an external
dependency:

| Hook | Event | Needs `gs-harness`? | With no `gs-harness` |
|------|-------|---------------------|----------------------|
| `branch-guard.mjs` | `PreToolUse` (`Bash`, `PowerShell`) | **no** | works exactly the same — installed means live |
| `context-inject.mjs` | `SessionStart` (`startup\|clear\|compact`) | yes | **silently skips** — no output, exit 0, no error, no delay |

`context-inject` reads one pre-rendered file, `$GS_HARNESS_ROOT/state/context-agent.md`
(defaulting to `~/gs-harness/state/context-agent.md` when `GS_HARNESS_ROOT` is
unset). If that file is missing, empty, or unreadable, the hook prints **nothing**
and exits 0 — Claude Code treats a hook with no stdout as "nothing to inject" and
carries on. So installing `gs-meta-harness` without `gs-harness` is safe and
useful: you get the branch-protection gate, and the context hook stays dormant
until the day `gs-harness` shows up. Point it at a non-default checkout with:

```bash
export GS_HARNESS_ROOT=/path/to/gs-harness      # PowerShell: $env:GS_HARNESS_ROOT = 'C:\path\to\gs-harness'
```

Note the SessionStart matcher is `startup|clear|compact` on purpose — `resume`
and `fork` already carry the same context in the previous transcript, so
re-injecting there is pure duplicate spend.

### Testing this release safely (for you or a tester)

Test the plugin **without touching your real `~/.claude`**, pick one:

```bash
# 1. Load the local checkout directly — no marketplace, no install, no config writes:
claude --plugin-dir /path/to/gs-claude-config

# 2. Or a throwaway config dir (may prompt for login the first time):
CLAUDE_CONFIG_DIR=/tmp/cc-test claude
#   then inside:  /plugin marketplace add gsinvest017-ai/gs-claude-config  → install → test
#   cleanup:      rm -rf /tmp/cc-test
```

On a **clean machine** you can also just install normally — a fresh user has no
pre-existing copies, so there are no duplicate skills and (installing only the
base plugin) no hooks at all.

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

- **A. Claude Code plugin（推薦、最一鍵）**：marketplace 提供**兩個** plugin，把有
  侵入性的 hook 拆成 opt-in：
  - `gs-claude-toolkit` — 42 skills / 20 commands / 5 agents，**零 hook**（完全被動）
  - `gs-autopilot` — `/autopilot` 的 Stop hook，**想要才裝**
  - `gs-meta-harness` — `branch-guard`（PreToolUse 受保護分支硬閘門）＋
    `context-inject`（SessionStart 跨 repo context 注入），兩支都是跨平台 Node，**想要才裝**
  ```
  /plugin marketplace add gsinvest017-ai/gs-claude-config
  /plugin install gs-claude-toolkit@gs-claude-toolkit   # 零 hook
  /plugin install gs-autopilot@gs-claude-toolkit        # 選用
  /plugin install gs-meta-harness@gs-claude-toolkit     # 選用
  ```
  plugin 檔案進 `~/.claude/plugins/`，**不動**你的 `~/.claude/skills` 與
  `settings.json`；command 有命名空間（`/gs-claude-toolkit:*`）不會衝突。移除：
  `/plugin uninstall …`、`/plugin marketplace remove gs-claude-toolkit`。
  限制：plugin 無法調高 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`，`/autopilot` 續跑受內建上限；
  要跑滿 50 次請自行加該 env 或改用 B。
  **測試 release**：用 `claude --plugin-dir <本地 checkout>` 或乾淨的
  `CLAUDE_CONFIG_DIR=/tmp/cc-test claude` 測，真實 `~/.claude` 完全不碰。

  **裝了 `gs-meta-harness` 但機器上沒有 `gs-harness` 會怎樣？**
  兩支 hook 互相獨立，只有一支有外部依賴：
  - `branch-guard`（PreToolUse，matcher `Bash|PowerShell`）— **不需要任何外部依賴**，
    裝了就生效。擋 push 到 `main`/`master`、force push、`--mirror`、刪受保護分支；
    在 `bypassPermissions` 下照樣執行（permissions 的 deny 規則在那個模式會被整個繞過）。
  - `context-inject`（SessionStart，matcher `startup|clear|compact`）— 只讀
    `$GS_HARNESS_ROOT/state/context-agent.md`（未設 `GS_HARNESS_ROOT` 時退回
    `~/gs-harness/state/context-agent.md`）。檔案不存在／是空檔／讀不到 →
    **安靜跳過**：不印任何東西、exit 0、不報錯、不拖慢開場。

  所以沒有 `gs-harness` 也可以安心裝：你拿到分支保護閘門，context 那支就一直休眠，
  等哪天真的 clone 了 `gs-harness` 才會開始注入。checkout 不在預設位置就設
  `GS_HARNESS_ROOT`（PowerShell：`$env:GS_HARNESS_ROOT = 'C:\path\to\gs-harness'`）。

- **B. 安裝腳本（通用、遠端一行）**：
  - macOS/Linux/WSL：`curl -fsSL .../install-toolkit.sh | bash`
  - Windows：`irm .../install-toolkit.ps1 | iex`
  - 預設 **copy 模式**（不需 Dev Mode）；把 commands/skills/agents 複製進
    `~/.claude/`，並把 autopilot hook **安全併入** `settings.json`（不覆蓋你既有設定、
    不裝 `CLAUDE.md`）。同名項目先備份到 `~/.claude/backups/`。
  - 解除安裝：`./uninstall-toolkit.sh`（或 `.\uninstall-toolkit.ps1`）。

需求：`git` 與 `node`（Claude Code 已內建）。不需要 `jq`、不需要管理員權限。
