---
name: blender-physics-lint
description: Blender 場景物理 linter + 物理常識建模 SOP。當使用者輸入 /blender-physics-lint、說「檢查場景物理」、「物體穿模了 / 互相穿透」、「東西浮在空中」、「這個擺放合理嗎」、「建模完幫我驗證」、「讓場景更擬真」時啟動；同時只要用 blender-mcp 建模或大改場景，完成後就應主動跑一輪當 gate。三檢：BVHTree 穿透（含同截面互插）、ray_cast 懸空、rigid body settle 穩定度，輸出結構化違規清單後逐項修復到全綠；並附建模前的佈局約束語彙與 render 截圖自批 SOP。
---

# /blender-physics-lint — Blender 場景物理 linter + 建模 SOP

LLM 用 `execute_blender_code` 盲寫座標時最常犯三種物理常識錯誤：物體互相穿透、
懸空、擺放不穩。本 skill 用 Blender 內建能力（BVHTree + ray_cast + rigid body）
當「物理 linter」，建模後必跑；違規清單是結構化 JSON，照建議逐項修到全綠。

核心迴圈：**宣告約束 → 算座標建模 → 跑 lint → 修違規 → 重跑到 ok:true → render 自批**。

## 1. 跑 lint

腳本：本 skill 目錄下 `scripts/physics_lint.py`（零依賴，只用 Blender 內建模組）。

- **Blender MCP（常用）**：把 `physics_lint.py` 全文貼進 `execute_blender_code`
  執行（檔尾 `run_lint()` 會自動跑）；或先貼定義再呼叫
  `run_lint(checks=("intersect","floating"))` 客製。
- **headless**：`blender --background your.blend --python physics_lint.py`
- 結果在 stdout 的 `PHYSICS_LINT_RESULT: {...}` JSON：
  `ok`（全綠與否）、`checked`、`skipped_settle`（因 A/B 違規跳過穩定度模擬的物件）、
  `violations[]`（`check` / `objects` / `detail` / `suggestion`）。

## 2. 三檢與修復順序

| check | 意義 | 修法 |
|-------|------|------|
| `intersect` | 兩物件穿透（表面交疊或體積互滲） | 拉開位置/縮尺寸；並排貼合保留 >1mm 間隙 |
| `containment` | bbox 完全包在另一物件內（軟警告） | 房間殼裝家具屬正常可忽略；否則把物件移出來 |
| `floating` | 底面離下方支撐 >1cm 或下方無物 | 沿 -Z 下移貼到支撐面，或補支撐物 |
| `unstable` | 重力模擬 30 格後位移 >5cm 或轉動 >10° | 重心超出支撐面：擺正姿態、移到穩定支撐上 |

**先修 `intersect` / `floating`，再重跑看 `unstable`**——穿透/懸空物件會被
settle 自動跳過（列在 `skipped_settle`），所以全綠前至少要跑兩輪。

## 3. 建模前：佈局約束語彙（防患於未然）

不要直接噴座標。先用下列語彙宣告物件間關係，再由關係推導座標
（思路來自 LayoutVLM / Holodeck 的約束求解，此處以純 prompt 落地）：

- `on_top_of(A, B)`：`A.min_z = B.max_z`（誤差 <1mm），A 的 footprint 落在 B 頂面內。
- `against_wall(A, W)`：A 背面貼牆留 1~5mm，**不是**把 A 的中心放在牆平面上。
- `facing(A, B)`：A 的正面法向指向 B 中心（椅子朝桌、螢幕朝人）。
- `min_gap(A, B, d)`：走道/操作空間，AABB 最近距離 ≥ d（人行走道 ≥0.9m）。
- `aligned_row(A1..An, axis, pitch)`：等距成排（機櫃、書架），pitch ≥ 物寬。
- `centered_on(A, B)`：A 在 B 的頂面/區域置中（桌上的鍵盤、地毯上的茶几）。

尺寸用真實世界數值（公尺）：桌高 ~0.75、椅座 ~0.45、門 ~2.0×0.9、機櫃 0.6×1.2×2.0。
物件 origin 在幾何中心時，`min_z = center_z - height/2`——貼地即 `center_z = height/2`。

## 4. 擬真外觀 checklist（不要素色 primitive 交差）

- 材質：用 blender-mcp 的 PolyHaven 工具（`search_polyhaven_assets` /
  `download_polyhaven_asset` / `set_texture`）套 PBR 材質，或至少給 Principled BSDF
  設合理的 Metallic / Roughness（金屬 0.8+ / 木頭 rough 0.6~0.8）。
- 複雜物件：不要用 primitive 拼湊，改走 `generate_hyper3d_model_via_text` /
  `generate_hunyuan3d_model` 生成 asset 再 import，或 Sketchfab 現成模型。
- 光照：至少一盞主光 + 環境光（PolyHaven HDRI）；全黑或單點光都不擬真。
- 微差異：成排同物件加 ±1° 旋轉、±5mm 位置抖動，避免「複製貼上感」。

## 5. 視覺回饋 SOP（render → 自批 → 修）

1. **用 `bpy.ops.render.render(write_still=True)` 出 PNG 再 Read 檢視**；
   Blender 5.x EEVEE 的 offscreen viewport 截圖可能全黑（gs-thermal-sim 實測），
   `get_viewport_screenshot` 只當快速預覽、不當驗收依據。
2. 至少三視角：全景 45° 俯視、人眼高度平視、問題區域特寫。
3. 對每張圖自問：有沒有穿模/懸空看漏？比例對嗎（門比人高、椅子塞得進桌下）？
   材質像實物嗎？光影有沒有方向？——發現問題回到 §2 / §4 修。

## 6. 注意事項與已知限制

- lint 對場景**零污染**：settle 跑在烘平 scale 的臨時複製體上，原物件不掛
  rigid body、不改 transform；結束自動清理。
- settle 用 CONVEX_HULL 近似：凹形物件（弓形、鏤空）的穩定度判定偏保守。
- 大場景 O(n²) 兩兩檢查有 AABB 預過濾，數百物件內都夠快；更大場景先分區跑。
- 房間殼、地板、牆（命名含 floor/wall/ground/…）自動視為支撐物，不檢懸空。
- Blender MCP 舊坑：**不要**呼叫 `read_factory_settings`（會斷 MCP socket）；
  清場用 `bpy.data.objects.remove`。
- headless 自測（改過 `physics_lint.py` 後必跑）：
  `blender --background --python scripts/test_scene_lint.py` → 期望 `SELFTEST PASS`。

## 單一職責

本 skill 只管「物理合理性驗證 + 建模 SOP」。整房間程序化生成請用
Infinigen（BSD-3）獨立產出 .blend 再進 blender-mcp 細修；「一句話生成整個
世界」的世界模型（HunyuanWorld 等）不在本 skill 範疇（survey 結論：對逐物件
建模的物理常識缺口是殺雞用牛刀）。
