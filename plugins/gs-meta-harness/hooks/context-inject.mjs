#!/usr/bin/env node
// SessionStart hook（Node 版）：把跨 repo 的專案 context 注入每個新 session。
//
// 這是 hooks/context-inject.ps1 與 hooks/context-inject.sh 的跨平台移植版。
// 前兩份只能靠 install.ps1 / install.sh 安裝；plugin 要能在 Windows / macOS /
// Linux 都跑起來，所以改用 Node —— Node 隨 Claude Code 附帶，使用者不必額外裝
// 東西，也不必再維護一份 .ps1 一份 .sh。
//
// hooks.json 裡這樣掛（路徑一律走 ${CLAUDE_PLUGIN_ROOT}，不要 hardcode）：
//   "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/context-inject.mjs\""
//
// ── 為什麼這支腳本什麼邏輯都不做 ──
//
// SessionStart hook **同步阻塞 session 開場**，而且預算只有約 1.5s。跨 repo
// 全掃要 20 秒，超時的 hook 會被**靜默丟棄**——設定裡有 hook、實際從來沒注入
// 過，而且沒有任何錯誤訊息。那正是這整套稽核在對付的「假綠燈」。
//
// 所以採集與 render 都挪到 `harness context --refresh`（由 nightly loop 跑，
// 那時有的是時間），本腳本只做兩件事：讀一個預渲染好的檔、算它多舊。
// 沒有 python 啟動、沒有 git、沒有網路。
//
// 新鮮度：cache 是 nightly 產的，所以「昨天的」是正常狀態，不該吵。
// 只有超過 STALE_DAYS 才在注入內容最上方加一行警告——**過期也照樣注入**，
// 因為舊 context 仍遠勝於沒有 context，但必須讓 agent 知道它是舊的。
//
// 契約：stdin 收 JSON payload；要注入就往 stdout 印一行
// {"hookSpecificOutput":{...}}；不注入就什麼都不印。任何錯誤一律吞掉並 exit 0
// ——hook 壞掉不該讓 session 起不來，也不該吵。

import { readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const STALE_DAYS = 3;

// 尾註：指路到需要完整資料時該跑什麼。內容逐字對齊 .ps1 的 here-string。
// （.ps1 那份因為原始檔是 CRLF，here-string 會帶出 \r\n；這裡統一用 \n。）
const FOOTER =
  '\n\n---\n' +
  '需要更完整的資料（registry 全表、各 artifact 路徑、原始 JSON）就跑：\n' +
  '  harness context --mode agent --json\n' +
  '  harness validate            # 檢查文件宣稱與現實是否一致\n' +
  '  harness skills status       # skill 分佈、重名遮蔽、未提升為全域的';

/**
 * 把 payload 從 stdin 讀掉。本 hook 不需要 payload 裡的任何欄位（.ps1 版根本
 * 沒讀），但契約要求 hook 從 stdin 收 JSON，讀掉才不會讓上游卡在寫入。
 * 掛在 TTY 上（人手動執行）時直接跳過，否則 readFileSync(0) 會永遠等下去。
 */
function drainStdin() {
  try {
    if (process.stdin.isTTY) return null;
    const raw = readFileSync(0, 'utf8');
    return raw.trim() ? JSON.parse(raw) : null;
  } catch {
    return null; // payload 壞掉不影響注入
  }
}

/**
 * 模擬 .NET 的 `"{0:N0}" -f $x`：四捨五入到整數（.5 取偶，banker's rounding）
 * 並加千分位逗號。.ps1 用的就是 N0，天數顯示要跟它一模一樣。
 */
function formatN0(value) {
  const neg = value < 0;
  const n = Math.abs(value);
  const floor = Math.floor(n);
  const frac = n - floor;
  let rounded;
  if (frac > 0.5) rounded = floor + 1;
  else if (frac < 0.5) rounded = floor;
  else rounded = floor % 2 === 0 ? floor : floor + 1; // 正好 .5 → 取偶
  const grouped = String(rounded).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg && rounded !== 0 ? '-' : '') + grouped;
}

function main() {
  drainStdin();

  // 外部資源走環境變數；未設時預設家目錄下的 gs-harness。
  // （.ps1 用 $env:USERPROFILE、.sh 用 $HOME，Node 的 homedir() 兩邊都對。）
  const root = process.env.GS_HARNESS_ROOT || join(homedir(), 'gs-harness');
  const file = join(root, 'state', 'context-agent.md');

  let raw;
  try {
    raw = readFileSync(file, 'utf8'); // 中文內容：一律 UTF-8
  } catch {
    return; // 還沒 refresh 過就安靜跳過
  }

  // Get-Content -Encoding UTF8 會吃掉 BOM，Node 不會——手動去掉才對得起來。
  const body = raw.replace(/^\uFEFF/, '');

  // 檔案是空的 / 只有空白 → 同樣安靜跳過。
  // 注入空內容比不注入更糟：agent 會把「有這個區塊但裡面沒東西」讀成「沒事」。
  if (!body || /^\s*$/.test(body)) return;

  let ageDays = 0;
  try {
    ageDays = (Date.now() - statSync(file).mtimeMs) / 86400000;
  } catch {
    ageDays = 0; // 量不到年紀就當新鮮的，寧可少吵也不要不注入
  }

  let header = '# 專案 context（gs-harness，自動注入）';
  if (ageDays > STALE_DAYS) {
    header += `\n> ⚠️ 這份 context 已 ${formatN0(ageDays)} 天沒更新，內容可能過時。`;
    header += '\n> 重建：`harness context --refresh`';
  }

  const text = header + '\n\n' + body.trimEnd() + FOOTER;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'SessionStart',
        additionalContext: text,
      },
    }) + '\n',
  );
}

try {
  main();
} catch {
  // hook 壞掉不該讓 session 起不來，也不該吵
}
process.exitCode = 0;
