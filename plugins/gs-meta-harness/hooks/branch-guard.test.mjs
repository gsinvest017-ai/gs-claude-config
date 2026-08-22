// branch-guard.mjs 的行為規格測試（node:test + node:assert，零外部依賴）。
//
//   node --test plugins/gs-meta-harness/hooks/
//
// 這 38 個案例逐條移植自 tests/test-branch-guard.ps1，順序與內容都刻意保持一致，
// 方便兩版並排比對。**不要為了讓實作通過而改動案例**——這些案例就是規格本身，
// 尤其 mustAllow 那批：誤擋會讓人把整支 hook 關掉，那等於沒有防線。
//
// 每個案例都真的 spawn 一次子程序（`node branch-guard.mjs` 餵 stdin JSON），
// 走的是 Claude Code 實際呼叫 hook 的同一條路徑：
//   stdin JSON → stdout 一行 JSON（或什麼都不印）→ exit 0。

import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HOOK = join(dirname(fileURLToPath(import.meta.url)), 'branch-guard.mjs');

/**
 * 跑一次 hook，回傳 { denied, stdout, status }。
 * 判定方式與 .ps1 版一致：輸出內含 permissionDecision 就算擋下。
 */
function invokeHook(cmd, tool = 'Bash') {
  const payload = JSON.stringify({ tool_name: tool, tool_input: { command: cmd } });
  const res = spawnSync(process.execPath, [HOOK], { input: payload, encoding: 'utf8' });
  const stdout = res.stdout || '';
  return {
    denied: stdout.includes('permissionDecision'),
    stdout,
    status: res.status,
  };
}

function expectDeny(cmd, tool = 'Bash') {
  const { denied, stdout, status } = invokeHook(cmd, tool);
  assert.equal(denied, true, `漏擋 -> ${cmd}`);
  // hook 壞掉不該讓 session 起不來：任何情況都 exit 0
  assert.equal(status, 0, 'hook 必須 exit 0');
  const out = JSON.parse(stdout);
  assert.equal(out.hookSpecificOutput.hookEventName, 'PreToolUse');
  assert.equal(out.hookSpecificOutput.permissionDecision, 'deny');
  assert.match(out.hookSpecificOutput.permissionDecisionReason, /branch-guard hook 阻擋/);
}

function expectAllow(cmd, tool = 'Bash') {
  const { denied, stdout, status } = invokeHook(cmd, tool);
  assert.equal(denied, false, `誤擋 -> ${cmd}`);
  // 放行時什麼都不印
  assert.equal(stdout, '', '放行時不該有任何輸出');
  assert.equal(status, 0, 'hook 必須 exit 0');
}

// ── 必須擋下（deny）：17 條單行 + 1 條多行 ─────────────────────
const mustDeny = [
  'git push --force origin main',
  'git push origin main --force',
  'git push -f',
  'git push origin main',
  'git push upstream master',
  'git push origin +main:main',
  'git push --mirror origin',
  'git push origin HEAD:main',
  'git push origin HEAD:refs/heads/master',
  'git push origin --delete main',
  'git push --force-with-lease origin main',
  'git push --force-with-lease=main:abc123 origin main',
  'git -C /c/Users/User/gs-harness push origin main',
  'cd /tmp && git push origin master',
  'git push origin dev/foo && git push origin main',
  'git push -u origin main',
  'git push origin refs/heads/main',
];

// 多行 + heredoc 的必擋案例：真的要推 main，只是寫在多行區塊裡
const denyMultiline = [
  'cd /c/Users/User/gs-harness',
  'git add .',
  'git commit -m "wip"',
  'git push origin main',
].join('\n');

// ── 必須放行（allow）：16 條單行 + 2 條多行 ────────────────────
const mustAllow = [
  'git push -u origin dev/phase0-fix',
  'git push origin dev/incident-forgejo-mirror',
  'git push',
  'git push origin main-experiment',
  'git push origin feature/main',
  'git push origin mainline',
  'git push origin master-notes',
  'git status',
  'npm run push-docs',
  'echo "do not push to main"',
  'git log --oneline -1',
  'git push origin dev/x --set-upstream',
  'git fetch origin main',
  'git push origin main #allow-protected-push',
  'gh pr create --base main --head dev/x',
  'git commit -m "fix: 別再用 git push --force"',
];

// 迴歸案例：commit message 用 heredoc 寫，內文「引用」了 git 指令。
// 這是本 hook 上線第一次就踩到的誤擋——它把自己的 commit 擋掉了。
const allowHeredoc = [
  'cd /c/Users/User/gs-claude-config',
  'git add hooks/branch-guard.ps1',
  "git commit -F - <<'EOF'",
  'feat: 新增 branch-guard hook',
  '',
  'deny 規則是前綴比對，`Bash(git push --force:*)` 擋不到',
  '`git push origin main --force` 這種參數順序顛倒的寫法。',
  'EOF',
  'git push origin dev/phase0-fix-dead-imports',
].join('\n');

// 多行但每一行都合法
const allowMultiline = [
  'git fetch origin',
  'git checkout -b dev/foo origin/main',
  'git push -u origin dev/foo',
].join('\n');

test('必須擋下（deny）', async (t) => {
  for (const cmd of mustDeny) {
    await t.test(cmd, () => expectDeny(cmd));
  }
  await t.test('[多行區塊內真的 push main]', () => expectDeny(denyMultiline));
});

test('必須放行（allow）', async (t) => {
  for (const cmd of mustAllow) {
    await t.test(cmd, () => expectAllow(cmd));
  }
  await t.test('[heredoc commit message 引用 git push --force]', () =>
    expectAllow(allowHeredoc));
  await t.test('[多行區塊，每行都合法]', () => expectAllow(allowMultiline));
});

test('PowerShell tool 也要生效（tool-scoped 缺口的重點）', () => {
  expectDeny('git push origin main', 'PowerShell');
});

test('不相干的 tool 要放行', () => {
  expectAllow('git push origin main', 'Read');
});

// ── 以下為移植時補的健全性檢查，不屬於原 38 案例 ────────────────
// 原測試在 CRLF 檔案裡用 here-string，多行內容其實是 \r\n；plugin 在
// Linux/macOS 收到的則是 \n。兩種換行都要走得通，所以各驗一次。
test('補充：多行案例在 CRLF 換行下行為相同', async (t) => {
  await t.test('CRLF 多行 push main 仍被擋', () =>
    expectDeny(denyMultiline.replace(/\n/g, '\r\n')));
  await t.test('CRLF heredoc 仍被放行', () =>
    expectAllow(allowHeredoc.replace(/\n/g, '\r\n')));
  await t.test('CRLF 合法多行仍被放行', () =>
    expectAllow(allowMultiline.replace(/\n/g, '\r\n')));
});

test('補充：hook 契約的退化輸入一律靜默放行', async (t) => {
  const cases = [
    ['空 stdin', ''],
    ['非 JSON', 'not json at all'],
    ['JSON 但不是物件', '"just a string"'],
    ['缺 tool_input', '{"tool_name":"Bash"}'],
    ['command 為空字串', '{"tool_name":"Bash","tool_input":{"command":"   "}}'],
  ];
  for (const [name, input] of cases) {
    await t.test(name, () => {
      const res = spawnSync(process.execPath, [HOOK], { input, encoding: 'utf8' });
      assert.equal(res.stdout, '');
      assert.equal(res.status, 0);
    });
  }
});
