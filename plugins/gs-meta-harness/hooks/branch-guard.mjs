#!/usr/bin/env node
// PreToolUse hook：受保護分支的硬閘門（hooks/branch-guard.ps1 的跨平台移植版）。
//
// 為什麼需要這支腳本（不是「多一層保險」，是前三層都證實無效）：
//
// 1. 全域 CLAUDE.md 寫「main/master 禁止直接 push（不可協商）」——那只是 prompt，
//    模型可以忽略、agent 可能沒讀到、loop 的 fresh context 可能根本不載入。
//
// 2. permissions 的 deny 規則是**前綴比對，不是語義解析**。
//    `Bash(git push --force:*)` 擋得到 `git push --force origin x`，
//    但擋不到 `git push origin main --force`（參數順序顛倒）。
//    而且規則是 **tool-scoped**：寫 `Bash(...)` 只命中 Bash tool，
//    同一條指令改用 PowerShell tool 跑就直接放行（2026-08 實測確認）。
//
// 3. permission_mode = "bypassPermissions" 的 loop 會**整個繞過** allow/ask/deny。
//    gs-harness 的 nightly-verify 就是這樣設的。
//
// PreToolUse hook 是唯一同時解決這三點的層級：它拿得到**完整指令字串**、
// 對所有 tool 生效、而且在 bypassPermissions 下照樣執行。
//
// 2026-08-21 事故背景：29 個 repo 的 45 個已合併 PR 被 force push 抹除，
// 而「分支保護政策」的文件本身也在被抹掉的那一批裡面。詳見
// gs-harness/docs/incident-forgejo-mirror-2026-08-21.md
//
// ── 為什麼是 Node 而不是 PowerShell ─────────────────────────
// plugin 必須跨平台。Node 隨 Claude Code 附帶，使用者不必額外裝東西；
// .ps1 版只能靠 install.ps1 裝到單一台 Windows 機器上。
// 本檔為 hooks/branch-guard.ps1 的**行為等價**移植，規格由
// tests/test-branch-guard.ps1 的 38 個案例定義（見 branch-guard.test.mjs）。
//
// ── 設計約束 ─────────────────────────────────────────────────
// * **寧可漏擋也不要誤擋。** 誤擋會讓人把整支 hook 關掉，那等於沒有防線。
//   所以用 **token 解析**而不是大正則：`git push origin main-experiment`
//   這種名字裡剛好有 main 的分支絕不能被擋。
// * 不猜當前分支。裸 `git push`（main 已設 upstream 時同樣危險）刻意不擋——
//   要擋就得跑 git 去問當前分支，那會讓每次工具呼叫都付出 subprocess 成本，
//   而且在非 repo 目錄下會噴錯。這個缺口由 permissions 的 ask 規則補。
// * 解析失敗、非 git 指令、任何例外 → 一律放行（exit 0），不吵。
// * 逃生門：指令內含 `#allow-protected-push` 時放行，讓真的需要時可以明示意圖，
//   而不是把整支 hook 停掉。
//
// ── 移植備註（PowerShell 語意，刻意照搬）────────────────────
// PowerShell 的 -eq / -in / -contains / -like / -match / -replace 對字串
// **預設不分大小寫**。為了與 .ps1 版逐字元等價，這裡所有對應比較一律
// 以小寫正規化或加 /i 旗標處理，不要「順手」改成區分大小寫。

import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

/** 讀 stdin；讀不到就回空字串（等同 .ps1 的 Console::In.ReadToEnd 失敗路徑）。 */
function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

/** PowerShell 的 [string]::IsNullOrWhiteSpace。 */
function isNullOrWhiteSpace(s) {
  return typeof s !== 'string' || s.trim() === '';
}

/**
 * PowerShell 的 String.Trim('"', "'")：把頭尾**所有**屬於 { " ' } 的字元剝掉
 * （不是只剝一層、也不要求成對）。
 */
function trimQuotes(s) {
  let a = 0;
  let b = s.length;
  while (a < b && (s[a] === '"' || s[a] === "'")) a++;
  while (b > a && (s[b - 1] === '"' || s[b - 1] === "'")) b--;
  return s.slice(a, b);
}

/**
 * 把一個 refspec 正規化成「目的地分支名」，判斷是否為受保護分支。
 *   main                      -> main        受保護
 *   +main                     -> main        受保護（+ 是 force 的另一種寫法）
 *   HEAD:main                 -> main        受保護
 *   HEAD:refs/heads/master    -> master      受保護
 *   dev/foo                   -> dev/foo     放行
 *   main-experiment           -> main-exp…   放行  ← 這是不能誤擋的關鍵案例
 *   feature/main              -> feature/main 放行
 */
export function testProtectedRef(spec) {
  if (isNullOrWhiteSpace(spec)) return false;
  let s = spec.replace(/^\++/, ''); // TrimStart('+') 會剝掉連續的 +
  const colon = s.lastIndexOf(':');
  if (colon >= 0) s = s.slice(colon + 1); // 取目的地那半
  s = s.replace(/^refs\/heads\//i, ''); // PS 的 -replace 不分大小寫
  const lower = s.toLowerCase(); // PS 的 -eq 不分大小寫
  return lower === 'main' || lower === 'master';
}

const FORCE_FLAGS = ['--force', '-f', '--force-with-lease'];

/**
 * 核心判定：回傳阻擋理由字串；無需阻擋則回傳 null。
 * 抽成純函式是為了讓測試能同時走「函式層」與「子程序層」兩種驗證。
 */
export function evaluateCommand(cmd) {
  if (isNullOrWhiteSpace(cmd)) return null;

  // 快速路徑：這支 hook 每次工具呼叫都會跑，沒有 push 就立刻結束
  if (!/push/i.test(cmd)) return null;
  if (/#\s*allow-protected-push/i.test(cmd)) return null;

  // ── 先剝掉 heredoc 內文 ──────────────────────────────────────
  // 沒有這一步會有一整類誤擋：用 heredoc 寫的 commit message／文件內容
  // 只要「引用」了 git 指令（例如本 hook 自己的 commit message 就寫了
  // `git push origin main --force`），就會被當成真的要執行。
  // 這是實際踩到的——本 hook 上線第一次就把自己的 commit 擋掉了。
  const cmdForScan = cmd.replace(
    /<<-?\s*['"]?(\w+)['"]?\r?\n[\s\S]*?\r?\n\1\b/g,
    ' <<HEREDOC_STRIPPED> ',
  );

  // 一條指令可能串了好幾段。除了 ; && || | 之外，**換行也要切**——
  // 多行 Bash 區塊裡每一行是獨立指令，不切的話 `git add` 那行的 git
  // 會跟好幾行之後的 push 被湊成同一條指令。
  for (const segment of cmdForScan.split(/(?:;|&&|\|\||\||\r?\n)/)) {
    if (!/\bgit\b/i.test(segment)) continue;

    // 切 token（引號內的空白不切）
    const tokens = (segment.match(/"[^"]*"|'[^']*'|\S+/g) || []).map(trimQuotes);
    if (tokens.length === 0) continue;

    // 找 "git ... push"（中間可能夾 -C <path> 這類全域選項）
    const gi = tokens.findIndex((t) => /(^|[\\/])git(\.exe)?$/i.test(t));
    if (gi < 0) continue;
    let pi = -1;
    for (let i = gi + 1; i < tokens.length; i++) {
      if (tokens[i].toLowerCase() === 'push') {
        pi = i;
        break;
      }
    }
    if (pi < 0) continue;

    const args = tokens.slice(pi + 1).filter((t) => t);
    const lowerArgs = args.map((a) => a.toLowerCase());

    // ── 規則 1：force（不論出現在哪個位置）──────────────────
    if (lowerArgs.some((a) => FORCE_FLAGS.includes(a) || a.startsWith('--force-with-lease='))) {
      return 'force push';
    }

    // ── 規則 2：--mirror（會同步刪除遠端多出來的 ref）────────
    if (lowerArgs.includes('--mirror')) {
      return '--mirror（會覆蓋並刪除遠端 ref）';
    }

    const positional = args.filter((a) => !a.startsWith('-'));

    // ── 規則 3：刪除遠端的 main/master ─────────────────────
    if (
      (lowerArgs.includes('--delete') || lowerArgs.includes('-d')) &&
      positional.some(testProtectedRef)
    ) {
      return '刪除遠端受保護分支';
    }

    // ── 規則 4：refspec 帶 + 前綴（等同 force）─────────────
    if (positional.some((p) => p.startsWith('+') && p.length > 1)) {
      return '帶 + 前綴的 refspec（等同 force push）';
    }

    // ── 規則 5：明確指名推到 main / master ─────────────────
    // positional[0] 是 remote，之後才是 refspec，所以從第 2 個起算
    if (positional.length >= 2 && positional.slice(1).some(testProtectedRef)) {
      return '直接推到受保護分支 main/master';
    }
  }

  return null;
}

/** 組出阻擋訊息（與 .ps1 版逐字相同）。 */
export function buildMessage(reason, cmd) {
  return `已由 branch-guard hook 阻擋：${reason}

偵測到的指令：
  ${cmd}

分支保護是不可協商的政策（見全域 CLAUDE.md）。請改走 PR：
  git checkout -b dev/<主題> origin/main
  git push -u origin dev/<主題>
  gh pr create --base main

2026-08-21 事故紀錄：29 個 repo 的 45 個已合併 PR 曾被 force push 抹除，
其中包含分支保護政策的文件本身。復原一律走 PR，不要用 force push 還原——
被覆蓋之後遠端通常也有新 commit，force 回去會造成第二次資料損失。

若這次確實必須執行，在指令尾端加上 #allow-protected-push 明示意圖。`;
}

function main() {
  const stdin = readStdin();
  if (!stdin) return;

  let payload = null;
  try {
    payload = JSON.parse(stdin.replace(/^﻿/, ''));
  } catch {
    return;
  }
  if (!payload || typeof payload !== 'object') return;

  // PS 的 -notin 不分大小寫，照搬
  const toolName = payload.tool_name == null ? '' : String(payload.tool_name);
  if (!['bash', 'powershell'].includes(toolName.toLowerCase())) return;

  const rawCmd = payload.tool_input == null ? null : payload.tool_input.command;
  const cmd = rawCmd == null ? '' : String(rawCmd);
  if (isNullOrWhiteSpace(cmd)) return;

  const reason = evaluateCommand(cmd);
  if (!reason) return;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: buildMessage(reason, cmd),
      },
    }),
  );
}

// 直接執行時才跑 main（被 import 當函式庫時不執行）。
//
// 比對前先 realpath：Windows 的碟符大小寫、正斜/反斜、以及 symlink 安裝路徑
// （`~/.claude/plugins` 常是 symlink）都會讓兩邊字串長得不一樣。
// 判不出來時**預設當作直接執行**——閘門失效比多跑一次 main() 危險得多，
// 而 main() 在沒有 stdin 的情況下本來就是靜默 return。
let invokedDirectly = false;
if (process.argv[1]) {
  // hook 一定是 `node <本檔路徑>` 這樣被叫起來的，argv[1] 必然有值；
  // 沒有 argv[1] 代表是 `node -e` / REPL / import，那就不能跑 main()
  // （會卡在讀 stdin）。
  try {
    const norm = (p) => pathToFileURL(realpathSync(p)).href.toLowerCase();
    invokedDirectly = norm(process.argv[1]) === norm(fileURLToPath(import.meta.url));
  } catch {
    invokedDirectly = true;
  }
}
if (invokedDirectly) {
  try {
    main();
  } catch {
    /* 吞掉：不印任何東西，靜默放行 */
  }
  process.exitCode = 0;
}
