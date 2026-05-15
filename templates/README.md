# templates/

Reference material for new colleagues. **Not applied** by either install
path — these files are read-only examples.

## Files

| File | What it shows |
|---|---|
| `CLAUDE.example.kevin.md` | A fully-populated `~/.claude/CLAUDE.md` — what the file looks like once you've added 5–6 real projects with entry docs and "read on demand" pointers. |

## Why these aren't applied automatically

`~/.claude/CLAUDE.md` is **per-person** — your project list isn't ours.

- New colleague flow: `chezmoi init` renders a near-empty skeleton from
  `chezmoi-source/dot_claude/CLAUDE.md.tmpl`. Fill it in over the first
  week as you start working on actual repos.
- Old colleague flow (existing `install.sh` path): the symlink points at
  the repo-root `CLAUDE.md`. Override locally by `rm ~/.claude/CLAUDE.md`
  + creating your own.

## Known follow-up

The repo-root `CLAUDE.md` is currently Kevin's personal version (legacy
from before this template existed). It's still committed so the existing
`install.sh` symlink path keeps working without behavior change. Tracked
as tech debt — future PR: replace repo-root `CLAUDE.md` with a generic
skeleton matching the chezmoi template, and migrate Kevin's machine to
the chezmoi flow.
