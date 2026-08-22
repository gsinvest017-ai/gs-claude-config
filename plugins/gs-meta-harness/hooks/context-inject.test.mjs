// context-inject.mjs 的行為測試（node:test + node:assert，零外部依賴）。
//
// 規格來源是 tests/test-context-inject.ps1 的 11 個案例——那份測的是 .ps1 版，
// 這份把同樣的斷言逐條移植到 Node 版，另外補上 .ps1 測不到的邊界
// （只有空白的 cache、壞掉的 stdin payload、GS_HARNESS_ROOT 未設時的預設路徑）。
//
// 跑法：node --test plugins/gs-meta-harness/hooks/context-inject.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HOOK = join(dirname(fileURLToPath(import.meta.url)), 'context-inject.mjs');
const PAYLOAD = JSON.stringify({ hook_event_name: 'SessionStart', session_id: 'test' });

/** 用臨時 GS_HARNESS_ROOT 隔離，不動真實的 state/ */
function makeRoot() {
  const root = mkdtempSync(join(tmpdir(), 'ctxhook-'));
  mkdirSync(join(root, 'state'), { recursive: true });
  return root;
}

function cacheFile(root) {
  return join(root, 'state', 'context-agent.md');
}

/** 跑 hook，回傳 { stdout, stderr, status } */
function runHook({ root, env = {}, input = PAYLOAD } = {}) {
  const childEnv = { ...process.env, ...env };
  if (root === undefined) delete childEnv.GS_HARNESS_ROOT;
  else childEnv.GS_HARNESS_ROOT = root;
  const r = spawnSync(process.execPath, [HOOK], { input, encoding: 'utf8', env: childEnv });
  return { stdout: r.stdout ?? '', stderr: r.stderr ?? '', status: r.status };
}

function parse(stdout) {
  return JSON.parse(stdout);
}

function setMtimeDaysAgo(file, days) {
  const when = new Date(Date.now() - days * 86400000);
  utimesSync(file, when, when);
}

const SAMPLE = '## workspace\n- root: X\n\n## learnings（2 條）\n- 某個坑';

// ── cache 不存在時：安靜跳過，不可輸出任何東西 ──────────────────────────────
test('無 cache → 無輸出', () => {
  const root = makeRoot();
  try {
    const { stdout, status } = runHook({ root });
    assert.equal(stdout.trim(), '');
    assert.equal(status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── cache 是空檔：同樣安靜跳過（別注入空 context 假裝有東西）────────────────
test('空 cache → 無輸出', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), '', 'utf8');
    const { stdout, status } = runHook({ root });
    assert.equal(stdout.trim(), '');
    assert.equal(status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('只有空白的 cache → 無輸出', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), '\r\n  \t\n\n', 'utf8');
    const { stdout, status } = runHook({ root });
    assert.equal(stdout.trim(), '');
    assert.equal(status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── 正常 cache ─────────────────────────────────────────────────────────────
test('正常 cache：輸出合法 JSON、事件名、本文、指路、無過期警告', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), SAMPLE, 'utf8');
    const { stdout, status } = runHook({ root });
    assert.equal(status, 0);

    let json;
    assert.doesNotThrow(() => {
      json = parse(stdout);
    }, '輸出是合法 JSON');

    const ctx = json.hookSpecificOutput.additionalContext;
    assert.equal(json.hookSpecificOutput.hookEventName, 'SessionStart');
    assert.match(ctx, /某個坑/, '內容含 cache 本文');
    assert.match(ctx, /harness context --mode agent --json/, '內容含後續指令指路');
    assert.doesNotMatch(ctx, /沒更新/, '新鮮時不加過期警告');
    // 標頭在最上方、本文接在後面（順序不能反）
    assert.ok(ctx.startsWith('# 專案 context（gs-harness，自動注入）\n\n## workspace'));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('輸出是單行 JSON（Claude Code 逐行解析 hook 輸出）', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), SAMPLE, 'utf8');
    const { stdout } = runHook({ root });
    assert.equal(stdout.trimEnd().split('\n').length, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── 過期 cache：照樣注入，但必須標出天數 ────────────────────────────────────
test('過期 cache：仍然注入、標出警告與天數、告知重建方式', () => {
  const root = makeRoot();
  try {
    const file = cacheFile(root);
    writeFileSync(file, SAMPLE, 'utf8');
    setMtimeDaysAgo(file, 9);

    const { stdout, status } = runHook({ root });
    assert.equal(status, 0);
    const ctx = parse(stdout).hookSpecificOutput.additionalContext;

    assert.match(ctx, /某個坑/, '過期仍然注入（舊 context 勝於沒有）');
    assert.match(ctx, /沒更新/, '標出過期警告');
    assert.match(ctx, /harness context --refresh/, '告知重建方式');
    assert.match(ctx, /已 9 天沒更新/, '天數要正確');
    // 警告必須在最上方，agent 一眼就看到
    assert.ok(ctx.split('\n')[1].startsWith('> ⚠️'));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('剛好 3 天內不算過期（門檻是 > 3 天）', () => {
  const root = makeRoot();
  try {
    const file = cacheFile(root);
    writeFileSync(file, SAMPLE, 'utf8');
    setMtimeDaysAgo(file, 2.9);
    const ctx = parse(runHook({ root }).stdout).hookSpecificOutput.additionalContext;
    assert.doesNotMatch(ctx, /沒更新/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── 預設路徑：GS_HARNESS_ROOT 未設時退回家目錄下的 gs-harness ───────────────
test('GS_HARNESS_ROOT 未設 → 讀家目錄下的 gs-harness/state/context-agent.md', () => {
  const home = makeRoot();
  try {
    mkdirSync(join(home, 'gs-harness', 'state'), { recursive: true });
    writeFileSync(join(home, 'gs-harness', 'state', 'context-agent.md'), SAMPLE, 'utf8');
    // Node 的 homedir()：Windows 看 USERPROFILE、POSIX 看 HOME
    const { stdout } = runHook({ root: undefined, env: { HOME: home, USERPROFILE: home } });
    const ctx = parse(stdout).hookSpecificOutput.additionalContext;
    assert.match(ctx, /某個坑/);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});

// ── 韌性：任何錯誤都吞掉並 exit 0，絕不讓 session 起不來 ────────────────────
test('stdin payload 不是 JSON → 照樣注入且 exit 0', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), SAMPLE, 'utf8');
    const { stdout, status } = runHook({ root, input: 'not json at all{{{' });
    assert.equal(status, 0);
    assert.match(parse(stdout).hookSpecificOutput.additionalContext, /某個坑/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('stdin 是空的 → 照樣注入且 exit 0', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), SAMPLE, 'utf8');
    const { stdout, status } = runHook({ root, input: '' });
    assert.equal(status, 0);
    assert.match(parse(stdout).hookSpecificOutput.additionalContext, /某個坑/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('cache 路徑是目錄（讀不了）→ 無輸出且 exit 0', () => {
  const root = makeRoot();
  try {
    mkdirSync(cacheFile(root), { recursive: true });
    const { stdout, status } = runHook({ root });
    assert.equal(stdout.trim(), '');
    assert.equal(status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── 效能：必須遠低於 SessionStart 的 ~1.5s 預算 ─────────────────────────────
test('單次執行 < 1200 ms', () => {
  const root = makeRoot();
  try {
    writeFileSync(cacheFile(root), SAMPLE, 'utf8');
    const t0 = Date.now();
    runHook({ root });
    const elapsed = Date.now() - t0;
    console.log(`  耗時 ${elapsed} ms`);
    assert.ok(elapsed < 1200, `耗時 ${elapsed} ms 超過 1200 ms 預算`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
