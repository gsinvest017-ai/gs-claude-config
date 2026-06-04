# safe-yolo: hook 層 Top OCR diff

## 目標
在 autogo-prefetch.ps1 加入 Top OCR diff，讓高頻調用（< 10s）在畫面未變化時
無需 Claude 推理（直接路由到「畫面無變化」**STOP**），節省推理時間。

## 計畫 milestone

- [x] M1：autogo-prefetch.ps1 加 Top OCR diff（parse 表格 → 緩存到 %TEMP% → 注入 top_ocr_unchanged）
- [x] M2：SKILL.md 加 top_ocr_unchanged:true 路由規則
- [x] M3：進度檔 + commit

## 實作說明

### M1 — hook Top OCR diff

1. 捕捉 context_summary 完整輸出到 $hookOutput 變數
2. 用 regex 解析 [autogo-response] 表格的最後一欄（Top OCR）
3. 與 $TEMP\autogo-topcr.txt 緩存比對
4. 注入 `top_ocr_unchanged: true/false` 到 [autogo-meta] 塊
5. 輸出修改後的文字

驗證：連續兩次呼叫：
- Run 1: top_ocr_unchanged: false（無緩存）
- Run 2: top_ocr_unchanged: true（相同畫面）

### M2 — SKILL.md 路由

在路由決策表新增第二行（優先於 stub 和 text_blocks_total 規則）：
top_ocr_unchanged: true + 通用描述 → 「畫面無變化：Top OCR 與上次相同。」STOP

## Fallback 指引
- rollback hook: 本地非 tracked，手動改回舊版本
- rollback SKILL.md: git revert HEAD 在 gs-claude-config
