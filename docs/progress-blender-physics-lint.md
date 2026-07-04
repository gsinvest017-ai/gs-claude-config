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
- [x] M2 physics_lint.py（三檢）+ headless 測試場景驗證（Blender 5.1 --background）
- [x] M3 SKILL.md（lint gate 流程 + 佈局約束語彙 + 截圖自批 SOP）打包全域 skill，push
- [x] M4 收尾報告

## 日誌

### 2026-07-04 M1
- survey 全文見當日對話；三層架構：A+B 物理驗證（build thin）、C 佈局常識（prompt）、
  D+E 擬真與視覺回饋（adopt blender-mcp 既有 PolyHaven / Hyper3D / screenshot）。
- 測試場景沿用 gs-thermal-sim 機櫃尺寸（0.6×1.2×2.0，pitch 0.6），機櫃排列正是最容易
  穿透的案例；但 PoC 自建合成場景、不動 gs-thermal-sim repo（其 CLAUDE.md 約定骨架
  階段不代 commit）。
- 假設記錄：任務文明示「驗證有效再 /new-skill-push 上全域」→ 視為已授權對
  gs-claude-config 的 commit + push（僅新增檔案，不動既有 skill）。

### 2026-07-04 M2
- `skills/blender-physics-lint/scripts/physics_lint.py`：三檢實作；
  `scripts/test_scene_lint.py` 合成機房自測場景（floor + 合法貼合 rack_ok +
  穿透對 rack_overlap_a/b + 懸空 rack_float + 傾斜 35° rack_tilt），六條
  assert 全過（SELFTEST PASS，Blender 5.1 headless）。
- 自測抓到兩個真 bug（證明「先驗證再上全域」流程有價值）：
  1. **同截面互插盲點**：兩等高機櫃沿 x 互插時表面只在邊緣線相交，收縮後
     BVH surface overlap 為零 → 補「體積互滲」判定（AABB 三軸互滲 > 2mm 且
     交集中心點以射線奇偶性驗證同時在兩物件內部）。
  2. **預設 collision margin 0.04 彈射**：「剛好貼地」的物件開場即嵌入 4cm，
     貼地箱被彈到位移 0.28m + 轉 31°（誤報 unstable）；雙邊 margin 收到 1mm
     後殘餘抖動 2mm。另發現 PASSIVE plane 用 CONVEX_HULL 退化（物件直接穿地
     自由落體），靜態支撐一律改 MESH shape。
- settle 改跑「烘平 scale 的臨時複製體」（非均勻 object scale 會讓 Bullet 碰撞
  形狀失真），量測後整批刪除——原物件全程不掛 rigid body、不改 transform，
  零場景污染。

### 2026-07-04 M3/M4
- `skills/blender-physics-lint/SKILL.md`（CRLF）：核心迴圈「宣告約束 → 建模 →
  lint → 修到全綠 → render 自批」；三檢修復順序（先 intersect/floating 再
  unstable，至少跑兩輪）；佈局約束語彙 on_top_of / against_wall / facing /
  min_gap / aligned_row / centered_on（LayoutVLM / Holodeck 思路、純 prompt
  落地）；PolyHaven / Hyper3D 擬真 checklist；render 自批 SOP（EEVEE offscreen
  viewport 全黑坑 → 用 bpy.ops.render.render 出 PNG）。
- skill 放進 skills/ 載體即全域生效（~/.claude/skills symlink），已確認出現在
  session 可用 skill 清單。
- commit 鏈：ac8be4c(M1) → c56a974(M2) → 181ca52(chore) → 783b6f5(M3)，push 至
  gsinvest017-ai/gs-claude-config main。

## Fallback 指引

- headless 自測重跑：
  `& 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe' --background --python skills/blender-physics-lint/scripts/test_scene_lint.py`
- MCP 互動場景使用：把 physics_lint.py 內容貼進 execute_blender_code 後呼叫
  `run_lint()`（SKILL.md 有完整流程）。
- 若 settle 誤報：先確認場景有支撐物（floor 命名），再調 move_eps / rot_eps_deg。
