#!/usr/bin/env bash
# Install gs-claude-config into ~/.claude/ via symlinks.
#
# Idempotent. If ~/.claude/{commands,skills,CLAUDE.md} already exist as
# regular files/dirs (not symlinks), they get moved to ~/.claude/backups/
# with a timestamp suffix before the symlink is created.
#
# settings.json is *not* symlinked. It gets rendered from
# settings.template.json (with __HOME__ → $HOME) only if no settings.json
# is present yet — existing settings are never overwritten.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BACKUP_DIR="$CLAUDE_DIR/backups/install-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CLAUDE_DIR"

# Some skills are relative symlinks pointing to a sibling repo at
# $HOME/quant-research-skill. Clone it on a fresh machine so the symlinks
# resolve. Edit QRS_REMOTE if you fork it.
QRS_REMOTE="https://github.com/gsinvest017-ai/quant-research-skill.git"
QRS_DIR="$HOME/quant-research-skill"
if [[ ! -d "$QRS_DIR" ]]; then
    echo "==> Cloning sibling repo quant-research-skill (skills/ symlinks depend on it)"
    git clone "$QRS_REMOTE" "$QRS_DIR"
fi

backup_if_exists() {
    local target="$1"
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -e "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        mv "$target" "$BACKUP_DIR/"
        echo "  backed up existing $(basename "$target") → $BACKUP_DIR/"
    fi
}

link() {
    local src="$1" dst="$2"
    backup_if_exists "$dst"
    ln -s "$src" "$dst"
    echo "  linked $(basename "$dst") → $src"
}

echo "==> Linking commands/, skills/, CLAUDE.md into $CLAUDE_DIR"
link "$REPO_DIR/commands"  "$CLAUDE_DIR/commands"
link "$REPO_DIR/skills"    "$CLAUDE_DIR/skills"
link "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# hooks/ is a real (non-symlinked) dir per machine — it mixes machine-specific
# scripts. Copy the portable autopilot hook by file so local hooks survive.
echo "==> Copying autopilot hooks into $CLAUDE_DIR/hooks/"
mkdir -p "$CLAUDE_DIR/hooks"
cp -f "$REPO_DIR/hooks/autopilot-continue.sh" "$CLAUDE_DIR/hooks/autopilot-continue.sh"
cp -f "$REPO_DIR/hooks/autopilot-arm.sh"      "$CLAUDE_DIR/hooks/autopilot-arm.sh"
cp -f "$REPO_DIR/hooks/context-inject.sh"     "$CLAUDE_DIR/hooks/context-inject.sh"
chmod +x "$CLAUDE_DIR/hooks/autopilot-continue.sh" "$CLAUDE_DIR/hooks/autopilot-arm.sh" \
         "$CLAUDE_DIR/hooks/context-inject.sh"
echo "  copied autopilot-continue.sh, autopilot-arm.sh, context-inject.sh"
# branch-guard 目前只有 PowerShell 版，POSIX 端沒有對應腳本，所以不複製也不註冊。
# 這是已知缺口而不是疏漏——見 hooks/README.md。

echo "==> settings.json"
AUTOPILOT_CMD="$CLAUDE_DIR/hooks/autopilot-continue.sh"
AUTOPILOT_ARM="$CLAUDE_DIR/hooks/autopilot-arm.sh"
CONTEXT_HOOK_CMD="$CLAUDE_DIR/hooks/context-inject.sh"
if [[ -e "$CLAUDE_DIR/settings.json" ]]; then
    echo "  exists already — left untouched. Diff against settings.template.json manually if you want to merge new keys."
    echo "  (autopilot Stop + UserPromptSubmit hooks + CLAUDE_CODE_STOP_HOOK_BLOCK_CAP must be merged by hand — see hooks/README.md)"
else
    sed -e "s|__HOME__|$HOME|g" \
        -e "s|__AUTOPILOT_HOOK_CMD__|$AUTOPILOT_CMD|g" \
        -e "s|__AUTOPILOT_ARM_CMD__|$AUTOPILOT_ARM|g" \
        -e "s|__CONTEXT_HOOK_CMD__|$CONTEXT_HOOK_CMD|g" \
        -e "s|__BRANCH_GUARD_CMD__|$CLAUDE_DIR/hooks/branch-guard.ps1|g" \
        "$REPO_DIR/settings.template.json" > "$CLAUDE_DIR/settings.json"
    echo "  rendered settings.template.json → $CLAUDE_DIR/settings.json"

    # settings.template.json 是 Windows 導向的，裡面有些 hook 只有 PowerShell 版
    # （目前是 branch-guard.ps1）。留著它們在 POSIX 端就是註冊一個永遠跑不起來
    # 的指令——hook 的失敗是靜默的，那正是一個假綠燈：設定裡看得到、實際從來沒動過。
    # 寧可不註冊也不要註冊一個死的。
    STRIPPER="$(command -v python3 || command -v python || true)"
    if [ -n "$STRIPPER" ]; then
        "$STRIPPER" - "$CLAUDE_DIR/settings.json" <<'PYSTRIP'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
removed = []
for event, entries in list((d.get("hooks") or {}).items()):
    kept = []
    for entry in entries:
        cmds = entry.get("hooks") or []
        if any(".ps1" in str(h.get("command", "")) for h in cmds):
            removed.append(f"{event}:{cmds[0].get('command','')[:60]}")
            continue
        kept.append(entry)
    if kept:
        d["hooks"][event] = kept
    else:
        del d["hooks"][event]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
for r in removed:
    print(f"  略過 PowerShell-only hook（本平台無對應腳本）：{r}")
PYSTRIP
    else
        echo "  ⚠️ 找不到 python3，無法剝除 PowerShell-only hook。"
        echo "     請手動從 ~/.claude/settings.json 移除任何 command 含 .ps1 的 hook，"
        echo "     否則每次觸發都會執行一個不存在的腳本。"
    fi
fi

echo
echo "Done. Verify with:  ls -la ~/.claude/ | grep -E 'commands|skills|CLAUDE'"
echo
echo "Optional — enable the 00:00–06:00 unattended /safe-yolo cron job:"
echo "  cp $REPO_DIR/scripts/targets.conf.example $REPO_DIR/scripts/targets.conf"
echo "  \$EDITOR $REPO_DIR/scripts/targets.conf      # one repo path per line"
echo "  $REPO_DIR/scripts/install-cron.sh"
echo "See README.md → 'Night Shift' for details, env vars, and disable instructions."
