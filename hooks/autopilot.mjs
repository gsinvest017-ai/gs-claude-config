#!/usr/bin/env node
// Cross-platform autopilot hook shim for the gs-claude-toolkit *plugin* path.
//
// One file handles BOTH hook events (it dispatches on hook_event_name from
// stdin), so a single portable `node` command in hooks/hooks.json works
// identically on Windows / macOS / Linux — no jq, no per-OS .ps1/.sh split.
// Node ships with Claude Code, so this has zero extra dependencies.
//
//   UserPromptSubmit  -> arm/disarm the control flag (was autopilot-arm.*)
//   Stop              -> keep the session working (was autopilot-continue.*)
//
// Behaviour mirrors hooks/autopilot-arm.sh and hooks/autopilot-continue.sh.
// Always exits 0 — a failure here must never wedge the session.
//
// NOTE (plugin limitation): a plugin cannot raise
// CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, so continuations are capped at Claude
// Code's built-in limit unless the user sets that env themselves. The script
// installer (install-toolkit.*) sets it to 60 for the full 50-round autopilot.

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const AUTOPILOT_DIR = join(homedir(), '.claude', '.autopilot');
const STATE_PATH = join(AUTOPILOT_DIR, 'state.json');
const DONE_PATH = join(AUTOPILOT_DIR, 'done');

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return {};
  }
}

function readState() {
  try {
    const raw = readFileSync(STATE_PATH, 'utf8');
    return raw.trim() ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function rmQuiet(p) {
  try {
    rmSync(p, { force: true });
  } catch {
    /* ignore */
  }
}

// --- UserPromptSubmit: arm / disarm ---------------------------------------
function handleUserPromptSubmit(input) {
  const prompt = String(input.prompt ?? '');
  const sessionId = String(input.session_id ?? '');

  const onMatch = prompt.match(/^\s*\/autopilot\s+on(?:\s+(.*))?$/s);
  if (onMatch) {
    const task = (onMatch[1] ?? '').trim();
    mkdirSync(AUTOPILOT_DIR, { recursive: true });
    rmQuiet(DONE_PATH);
    writeFileSync(
      STATE_PATH,
      JSON.stringify({ session_id: sessionId, iterations: 0, max_iterations: 50, task }),
    );
    const ctx =
      'autopilot 已武裝（session 已綁定，續跑上限 50）。立即開始執行任務，全程不要停、不要反問方向、' +
      `不要再自行建立 state.json。完成且驗證通過後執行 touch "${DONE_PATH}" 再結束。`;
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: ctx },
      }),
    );
    return;
  }

  if (/^\s*\/autopilot\s+off\b/.test(prompt)) {
    rmQuiet(STATE_PATH);
    rmQuiet(DONE_PATH);
  }
  // status / anything else -> no state change, no output.
}

// --- Stop: keep working ----------------------------------------------------
function handleStop(input) {
  // Valve 1: already looping under Claude Code's own machinery.
  if (input.stop_hook_active === true) return;

  const sessionId = String(input.session_id ?? '');

  // Valve 2: no flag file -> autopilot off.
  const state = readState();
  if (!state) return;

  // Valve 3: the flag must belong to THIS session.
  if (String(state.session_id ?? '') !== sessionId) return;

  // Valve 4: completion sentinel.
  if (existsSync(DONE_PATH)) {
    rmQuiet(DONE_PATH);
    rmQuiet(STATE_PATH);
    return;
  }

  // Valve 5: iteration ceiling.
  const iterations = Number(state.iterations ?? 0);
  let maxIter = Number(state.max_iterations ?? 50);
  if (!(maxIter > 0)) maxIter = 50;
  if (iterations >= maxIter) {
    rmQuiet(STATE_PATH);
    process.stderr.write(
      `[autopilot] 已達續跑上限 ${maxIter} 次，自動停止。如需續跑請重新 /autopilot on。\n`,
    );
    return;
  }

  // Continue: bump counter, block the stop, instruct next step.
  const next = iterations + 1;
  state.iterations = next;
  writeFileSync(STATE_PATH, JSON.stringify(state));

  const reason =
    `[autopilot 進行中 — 第 ${next}/${maxIter} 次續跑]\n` +
    '尚未偵測到完成訊號，繼續推進任務的下一步，不要停下來。\n' +
    '規則：\n' +
    '- 遇到分歧自行採用最合理的預設值繼續，把假設記進進度檔；不要反問方向。\n' +
    '- 禁止使用 AskUserQuestion，禁止用「要 A 還是 B？」結束回合。\n' +
    '- 沿用 /safe-yolo 紀律：milestone 式推進、每完成一個就 commit（繁中主體）、更新 docs/progress-*.md。\n' +
    '- 只有在同一錯誤連續 3 次仍無解、或操作不可逆且影響超出 working directory 時才停下回報。\n' +
    `- 當任務「真的完成且測試/驗證通過」時，執行：  touch "${DONE_PATH}"   然後才結束回合。`;

  process.stdout.write(JSON.stringify({ decision: 'block', reason }));
}

// --- dispatch --------------------------------------------------------------
try {
  const input = safeParse(readStdin());
  const event = input.hook_event_name ?? '';
  if (event === 'UserPromptSubmit') handleUserPromptSubmit(input);
  else if (event === 'Stop') handleStop(input);
  // Unknown event -> no-op.
} catch {
  // Never wedge the session.
}
process.exit(0);
