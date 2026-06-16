# gs-claude-config

Version-controlled `~/.claude/` config — slash commands, skills, global instructions, and settings template. Two paths to onboard a new machine:

| Path | OS | One-liner | Best for |
|------|----|-----------|----------|
| **chezmoi** | Windows / macOS / Linux | `chezmoi init --apply https://github.com/gsinvest017-ai/gs-claude-config.git` | New colleagues — handles prompts, installs apps, sets fonts |
| install script | Linux / macOS (`.sh`), Windows (`.ps1`) | `git clone … && ./install.sh` (or `.\install.ps1`) | Existing setup, advanced users who want full symlink control |

Pick whichever fits — both can coexist on the same machine; only the contributor (Kevin) needs the symlink path.

## What's in here

```
gs-claude-config/
├── commands/                 # ~/.claude/commands/ — slash commands
│   ├── commit-push.md
│   ├── daily-summary.md
│   ├── gh-new.md
│   ├── git-config.md
│   ├── git-tag.md
│   ├── quant-researcher.md
│   ├── review-strategy.md
│   ├── safe-yolo.md
│   └── skill.md
├── agents/                   # ~/.claude/agents/ — subagent definitions
│   ├── daily-summary.md
│   ├── git-tag.md
│   ├── language-tutor.md
│   ├── quant-researcher.md
│   └── review-strategy.md
├── skills/                   # ~/.claude/skills/ — full SKILL.md prompts
│   ├── daily-summary/SKILL.md
│   ├── git-tag/SKILL.md
│   ├── quant-researcher/SKILL.md
│   ├── review-strategy/SKILL.md
│   └── safe-yolo/SKILL.md
├── scripts/                  # cron / night-shift automation (optional)
│   ├── night-shift.sh           # per-repo unattended /safe-yolo runner
│   ├── night-shift-runner.sh    # cron entry, iterates targets.conf
│   ├── install-cron.sh          # register the 00:00 cron job
│   ├── uninstall-cron.sh        # remove it
│   └── targets.conf.example     # template — copy to targets.conf per machine
├── docs/
│   └── progress-night-shift-cron.md
├── CLAUDE.md                 # ~/.claude/CLAUDE.md — global instructions
├── settings.template.json    # rendered → ~/.claude/settings.json on install
└── install.sh                # symlink everything into ~/.claude/
```

## How it works on the source machine

Everything in `commands/`, `skills/`, and `CLAUDE.md` is the *real* file. `~/.claude/commands`, `~/.claude/skills`, `~/.claude/CLAUDE.md` are symlinks pointing here. Edit files in this repo; Claude Code picks up changes immediately (symlinks are transparent).

`settings.json` is *not* symlinked because some keys are machine-specific (e.g. `additionalDirectories`). The template is the shared baseline; each machine keeps its own rendered copy.

## Migrating to a new machine — chezmoi path (recommended)

Single command on a fresh machine:

```powershell
# Windows (PowerShell 7+ recommended; comes with the bootstrap script anyway)
winget install --id twpayne.chezmoi --scope user -e
chezmoi init --apply https://github.com/gsinvest017-ai/gs-claude-config.git
```

```bash
# macOS / Linux
brew install chezmoi   # or: sh -c "$(curl -fsLS get.chezmoi.io)"
chezmoi init --apply https://github.com/gsinvest017-ai/gs-claude-config.git
```

You'll be prompted for **7 values** the first time (defaults in brackets):

| Prompt | Default | Used for |
|---|---|---|
| `name` | — | Header of your `~/.claude/CLAUDE.md` |
| `email` | — | Same |
| `githubUser` | — | Clone-from URL of sibling repo `quant-research-skill` |
| `role` | `dev` | Tag in CLAUDE.md (e.g. `quant-researcher`, `ml`, `dev`) |
| `editor` | `code` | chezmoi's `edit` command default |
| `installFonts` | `true` | Auto-install CaskaydiaCove Nerd Font during apply |
| `installCron` | `false` | (POSIX only) enable 00:00–06:00 night-shift cron |

What `chezmoi apply` does:
1. Renders `~/.claude/CLAUDE.md` from a per-user template (your name/role at top, a skeleton "## projects" section to fill in)
2. Renders `~/.claude/settings.json` from shared permission/plugin defaults
3. On Windows: writes `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` (fish-style: PSReadLine + oh-my-posh + PSFzf + zoxide)
4. Runs `run_onchange_install-deps.{ps1,sh}` → installs winget/brew/apt apps + Nerd Font + clones `quant-research-skill` + symlinks `commands/` and `skills/` from this repo
5. **Does NOT touch** your Windows Terminal `settings.json` — see `chezmoi-source/docs/windows-terminal-setup.md` for the one-click manual font setup

To update later: `cd ~/.local/share/chezmoi && git pull && chezmoi apply`.

### What chezmoi does NOT clone — use `scripts/clone-all.sh`

chezmoi only manages files under `$HOME`. Your actual project repos
(`gs-strategy`, `gs-zipline-tej`, `gs-auto-fix`, …) are heavy and personal,
so they live outside chezmoi's scope. After `chezmoi apply` finishes, run:

```bash
cp scripts/repos.txt.example scripts/repos.txt
$EDITOR scripts/repos.txt              # one repo URL per line
scripts/clone-all.sh                   # idempotent; DRY_RUN=1 to preview
```

`repos.txt` is gitignored — each machine keeps its own list. The script
skips repos that already exist locally and prints a summary at the end.

### Things chezmoi deliberately won't migrate

| Item | Why | What to do on the new machine |
|------|-----|-------------------------------|
| `~/.claude/.credentials.json` | OAuth token, machine-bound | Re-login via `claude` CLI on first run |
| SSH private keys | Security | Run `ssh-keygen`, add the new pubkey to GitHub |
| System config (`/etc/`, locale, timezone) | Outside `$HOME` | Configure manually (`sudo dpkg-reconfigure tzdata` etc.) |
| Per-session state (`~/.claude/sessions/`, `history.jsonl`, caches) | Regenerated by Claude Code | Nothing — fresh state is fine |

## Migrating to a new machine — legacy symlink path

```bash
git clone https://github.com/<owner>/gs-claude-config.git ~/gs-claude-config
cd ~/gs-claude-config
./install.sh        # POSIX
# or:
.\install.ps1       # Windows (PowerShell)
```

`install.sh` is idempotent and does the following:

- **Clones sibling repo `quant-research-skill`** into `~/quant-research-skill` if it isn't there yet. Two of the skills (`quant-researcher`, `review-strategy`) are relative symlinks pointing into that repo — they break without it.
- Backs up any existing `~/.claude/{commands,skills,CLAUDE.md}` to `~/.claude/backups/install-<timestamp>/` before symlinking
- Renders `settings.template.json` → `~/.claude/settings.json` **only if** no settings.json is present (never overwrites)
- After running, edit `~/.claude/settings.json` to add/remove project paths under `additionalDirectories`

Verify:

```bash
ls -la ~/.claude/ | grep -E 'commands|skills|CLAUDE'
# should show 3 symlinks pointing to ~/gs-claude-config/
```

## Day-to-day workflow

Editing a skill or command:

```bash
$EDITOR ~/.claude/commands/quant-researcher.md   # symlink → repo file
cd ~/gs-claude-config
git add commands/quant-researcher.md
git commit -m "tweak quant-researcher phase 2"
git push
```

Pull updates on another machine:

```bash
cd ~/gs-claude-config && git pull
# nothing else needed — symlinks already point here
```

## What's NOT in here (and why)

The following live under `~/.claude/` but are deliberately excluded:

| Path | Why excluded |
|------|--------------|
| `.credentials.json` | OAuth tokens — never commit |
| `sessions/`, `history.jsonl`, `file-history/`, `projects/` | Per-session state, regenerated by Claude Code |
| `cache/`, `paste-cache/`, `downloads/`, `shell-snapshots/`, `session-env/` | Ephemeral runtime data |
| `plugins/` | Managed by Claude Code's plugin system |
| `policy-limits.json`, `mcp-needs-auth-cache.json`, `.last-cleanup` | Machine-local state |
| `tasks/`, `plans/`, `backups/`, `ide/` | Local working state |
| `settings.json` (the rendered copy) | Machine-specific; only the template is tracked |

## Night Shift — unattended `/safe-yolo` via cron

Optional feature for the 00:00–06:00 unattended window. A user-level cron job
fires at midnight, walks through every repo listed in `scripts/targets.conf`,
opens a fresh `claude/nightly-YYYY-MM-DD` branch in each, and runs
`/safe-yolo` against that repo's TODO / refactor / issue docs. Everything is
hard-killed at 06:00 so it can never run into your workday.

Why it lives here: this repo already owns global Claude config + the install
script for new machines, so adding `scripts/` keeps the migration story to a
single `git clone && ./install.sh && scripts/install-cron.sh`.

### Setup on a new machine

```bash
# (1) ~/.claude/ symlinks
cd ~/gs-claude-config && ./install.sh

# (2) Tell night shift which repos to work on
cp scripts/targets.conf.example scripts/targets.conf
$EDITOR scripts/targets.conf      # one repo path per line

# (3) Register the cron job
scripts/install-cron.sh
crontab -l                        # verify the >>> gs-claude-config night-shift <<< block
```

That's it. From the next 00:00 onward the runner will fire automatically.

### What happens each night

1. **00:00** — cron fires `night-shift-runner.sh` wrapped in `timeout 6h`
2. For each repo in `targets.conf`, in order:
   - Skip if the path doesn't exist
   - Refuse to act on a dirty working tree (no auto-stash)
   - Create `claude/nightly-YYYY-MM-DD` (suffix `-HHMMSS` if today's already exists)
   - Gather a prompt from: explicit `|file` from targets.conf → `TODO.md` / `docs/TODO.md` / `docs/refactor*.md` / `docs/issue*.md` / `docs/progress-*.md` → `gh issue list` fallback
   - Invoke `claude -p --dangerously-skip-permissions --permission-mode bypassPermissions --add-dir <repo> --model opus` with that prompt prefixed by `/safe-yolo`
   - Each repo gets `min(remaining_budget − 60s, 2h)`
   - If Claude makes no new commits, the empty branch is deleted
3. **06:00** — outer `timeout` SIGTERMs everything; `SIGKILL` 120s later as a safety net
4. Branches stay local — **nothing is pushed, no PR is opened**. Review them at your leisure with `git branch | grep claude/nightly`.

### Logs

- Per-repo: `~/.claude/night-shift-logs/<repo>-<YYYY-MM-DD-HHMMSS>.log`
- Per-night dispatcher summary: `~/.claude/night-shift-logs/_runner-<YYYY-MM-DD-HHMMSS>.log`

Old logs are not rotated automatically; prune with `find ~/.claude/night-shift-logs -mtime +14 -delete` in your own crontab if it grows.

### Customizing

| Env var                            | Default | Where to set | What it does |
|------------------------------------|---------|--------------|--------------|
| `NIGHT_SHIFT_START_HOUR`           | `0`     | `install-cron.sh` invocation | Cron hour (e.g. `23` to start at 11 PM) |
| `NIGHT_SHIFT_WINDOW_HOURS`         | `6`     | `install-cron.sh` invocation | Total budget; also the outer `timeout` |
| `NIGHT_SHIFT_PER_REPO_TIMEOUT`     | dynamic | targets.conf line / per call | Override per-repo cap (`2h`, `45m`, …) |
| `NIGHT_SHIFT_MODEL`                | `opus`  | env at cron time              | `opus` / `sonnet` / full model ID |
| `DRY_RUN=1`                        | unset   | manual smoke test             | Build the prompt + print the command but don't invoke claude |

Examples:

```bash
# Start at 23:00, run for 7 hours instead of 6
NIGHT_SHIFT_START_HOUR=23 NIGHT_SHIFT_WINDOW_HOURS=7 scripts/install-cron.sh

# Dry-run a single repo right now (no cron, no claude call)
DRY_RUN=1 scripts/night-shift.sh ~/gs-strategy

# Dry-run the whole dispatcher
DRY_RUN=1 scripts/night-shift-runner.sh
```

### Disabling

```bash
scripts/uninstall-cron.sh         # remove the crontab block
# or just: $EDITOR scripts/targets.conf and comment everything out — cron will still fire but exit immediately
```

### Safety notes

- **Branches only, no push.** The script never pushes to remote, never opens PRs, never sends messages. Worst case: you wake up to N junk local branches you `git branch -D`.
- **Dirty trees are skipped.** A repo with uncommitted changes is refused, not stashed. The runner moves on.
- **Subscription quota.** Each night burns Claude Pro/Max quota. With a typical 5-target setup over 6h you may hit rate limits; the per-repo `timeout` cap absorbs this.
- **`--dangerously-skip-permissions` is on.** Inside the nightly branch Claude can run arbitrary tools without prompting. The `--add-dir` flag limits filesystem access to the target repo, and the dirty-tree check prevents clobbering work-in-progress.
- **WSL2 caveat.** If your `cron` daemon doesn't run automatically on Windows boot, the job won't fire. Confirm with `service cron status` and arrange to auto-start it (`sudo systemctl enable cron`, or a Windows scheduled task that runs `wsl service cron start`).

### Migration to another machine

Same flow as the rest of this repo. After `git clone` + `install.sh` on the new PC:

```bash
cp scripts/targets.conf.example scripts/targets.conf
$EDITOR scripts/targets.conf      # different machine may want different repos
scripts/install-cron.sh
```

`targets.conf` is `.gitignore`d on purpose — each machine keeps its own list.

## autopilot — 互動 session 內硬性不停

Night Shift 是 **headless 跨-session** 的無人迴圈；`/autopilot` 是它在**互動 session 內**的對應物：靠 `hooks/autopilot-continue.{ps1,sh}` 這支 **Stop hook**，每次 Claude 想結束回合時把它擋回去繼續做，連 yes/no 都不必按，直到任務完成或達續跑上限（預設 50）。

```
/autopilot on <任務>     # 啟用 + 立即開始，沿用 safe-yolo 的 milestone/commit/進度紀律
/autopilot status        # 看目前第幾次 / 上限 / 任務
/autopilot off           # 隨時中止
```

- skill 定義：`skills/autopilot/SKILL.md`；hook 與安全閥說明：`hooks/README.md`。
- 預設**關閉**（無旗標檔時 hook 一律放行），且旗標**綁定 session**，不會影響其他視窗。
- `settings.json` 已把 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` 提到 `60` 以容納 50 次續跑（繞過 Claude Code 內建 8 次硬煞車）。
- autonomy 三件套：`safe-yolo`（軟 prompt）→ `autopilot`（硬 hook，本機互動）→ `night-shift`（headless 跨-session）。

## Adding a new slash command or skill

1. Drop it under `commands/<name>.md` or `skills/<name>/SKILL.md` in this repo
2. `git add` + `commit` + `push`
3. On other machines: `git pull` — it appears automatically because the parent dir is symlinked

No need to re-run `install.sh` after adding individual commands/skills.
