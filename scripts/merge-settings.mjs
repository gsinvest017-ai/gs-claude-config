#!/usr/bin/env node
// Idempotently merge the gs-claude-toolkit autopilot hooks + block-cap env into
// an existing (or new) ~/.claude/settings.json WITHOUT clobbering the user's
// other keys or hooks. Used by install-toolkit.{sh,ps1} — Node is guaranteed
// present with Claude Code, so this needs no jq/sed.
//
// Usage:
//   node merge-settings.mjs <settings.json> <hookCommand> [capValue]
//   node merge-settings.mjs <settings.json> --remove          # uninstall
//
// <hookCommand> is the single command Claude Code runs for BOTH the
// UserPromptSubmit(^/autopilot) and Stop hooks — autopilot.mjs dispatches on
// the event itself. Entries are tagged so install is idempotent and uninstall
// can find exactly what we added.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const [settingsPath, arg2, arg3] = process.argv.slice(2);
if (!settingsPath) {
  console.error('usage: merge-settings.mjs <settings.json> <hookCommand> [capValue] | --remove');
  process.exit(2);
}
const remove = arg2 === '--remove';
const hookCommand = remove ? null : arg2;
const capValue = arg3 || '60';
// Identify our own entries by the shim filename in their command — no custom
// JSON keys, so we never fight Claude Code's settings schema.
const MARK = 'autopilot.mjs';
const isOurs = (e) =>
  e && Array.isArray(e.hooks) && e.hooks.some((h) => h && typeof h.command === 'string' && h.command.includes(MARK));

let settings = {};
if (existsSync(settingsPath)) {
  try {
    const raw = readFileSync(settingsPath, 'utf8');
    settings = raw.trim() ? JSON.parse(raw) : {};
  } catch (e) {
    console.error(`refusing to touch unparseable ${settingsPath}: ${e.message}`);
    process.exit(1);
  }
}

settings.hooks = settings.hooks || {};
const ups = (settings.hooks.UserPromptSubmit = settings.hooks.UserPromptSubmit || []);
const stop = (settings.hooks.Stop = settings.hooks.Stop || []);

// Drop any entry we previously added (detected by the shim filename) so both
// install (re-add below) and uninstall (leave dropped) are idempotent.
settings.hooks.UserPromptSubmit = ups.filter((e) => !isOurs(e));
settings.hooks.Stop = stop.filter((e) => !isOurs(e));

if (remove) {
  if (settings.env && settings.env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP) {
    delete settings.env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP;
    if (Object.keys(settings.env).length === 0) delete settings.env;
  }
  if (settings.hooks.UserPromptSubmit.length === 0) delete settings.hooks.UserPromptSubmit;
  if (settings.hooks.Stop.length === 0) delete settings.hooks.Stop;
  if (settings.hooks && Object.keys(settings.hooks).length === 0) delete settings.hooks;
  writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
  console.log('removed autopilot hooks + block-cap env from settings.json');
  process.exit(0);
}

settings.env = settings.env || {};
if (!settings.env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP) {
  settings.env.CLAUDE_CODE_STOP_HOOK_BLOCK_CAP = capValue;
}

settings.hooks.UserPromptSubmit.push({
  matcher: '^/autopilot',
  hooks: [{ type: 'command', command: hookCommand, timeout: 10 }],
});
settings.hooks.Stop.push({
  matcher: '',
  hooks: [{ type: 'command', command: hookCommand, timeout: 30 }],
});

writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');
console.log('merged autopilot hooks + CLAUDE_CODE_STOP_HOOK_BLOCK_CAP into settings.json');
