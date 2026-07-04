# progress — blender-physics-lint 全域 skill

## 目標

把 survey（2026-07-04，世界模型 vs. 物理驗證迴圈）的結論落地：**不引入重型世界模型**，
改為在 blender-mcp 建模工作流加一道「物理 linter」gate——Blender 內建 rigid body +
BVHTree 三檢（穿透 / 懸空 / settle 穩定度），輸出結構化違規清單讓 Claude 自己修，
並把佈局約束語彙 + 截圖自批 SOP 寫進 SKILL.md。

## 落地決策（/repo-or-integrate + /gs-common-lift 判定）

- **integrate 進 gs-claude-config，不開新 repo**：consumer 是「所有用 blender-mcp 的
  session」（gs-oboe-twin、gs-thermal-sim、未來任何建模場景），不綁單一專案；
  程式量 ~200 行 bpy + SKILL.md，開新 repo 過重；本 repo 已有 skills/<name>/ 載體
  （~/.claude/skills symlink，放好即全域生效）。
- **不上 gs-common**：physics_lint.py 依賴 bpy、只能在 Blender 直譯器內執行，與
  gs-common consumer（一般 venv 的 web/服務共用庫）環境不相容；目前僅此一份實作、
  無跨 repo 重複，不符 lift 條件。未來若 gs-oboe-twin / gs-thermal-sim 各自 vendor
  一份再重議。
- **世界模型不採用**（survey 結論）：HunyuanWorld / HY-World 2.0 / Cosmos 解決的是
  「整場景生成」（F），非逐物件建模的物理常識缺口；重量級 + 自訂授權。觀望即可。

## Milestones

- [x] M1 落地決策 + 進度檔
- [ ] M2 physics_lint.py（三檢）+ headless 測試場景驗證（Blender 5.1 --background）
- [ ] M3 SKILL.md（lint gate 流程 + 佈局約束語彙 + 截圖自批 SOP）打包全域 skill，push
- [ ] M4 收尾報告

## 日誌

### 2026-07-04 M1
- survey 全文見當日對話；三層架構：A+B 物理驗證（build thin）、C 佈局常識（prompt）、
  D+E 擬真與視覺回饋（adopt blender-mcp 既有 PolyHaven / Hyper3D / screenshot）。
- 測試場景沿用 gs-thermal-sim 機櫃尺寸（0.6×1.2×2.0，pitch 0.6），機櫃排列正是最容易
  穿透的案例；但 PoC 自建合成場景、不動 gs-thermal-sim repo（其 CLAUDE.md 約定骨架
  階段不代 commit）。
- 假設記錄：任務文明示「驗證有效再 /new-skill-push 上全域」→ 視為已授權對
  gs-claude-config 的 commit + push（僅新增檔案，不動既有 skill）。

## Fallback 指引

- headless 自測重跑：
  `& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --python skills/blender-physics-lint/scripts/test_scene_lint.py`
- MCP 互動場景使用：把 physics_lint.py 內容貼進 execute_blender_code 後呼叫
  `run_lint()`（SKILL.md 有完整流程）。
- 若 settle 誤報：先確認場景有支撐物（floor 命名），再調 move_eps / rot_eps_deg。
