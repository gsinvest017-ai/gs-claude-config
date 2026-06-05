# safe-yolo: autogo auto-trigger（選項 A）

## 目標
讓 Claude session 在不需要使用者手動輸入 `/autogo` 的情況下，
根據可插拔的觸發政策自動決定是否注入 autogo screen context。

觸發政策來自 test bench A/B 實驗結論，需保持模組化與可擴充性。

## A/B 實驗核心結論（初始 policy 依據）

- ✅ **pytest 短輸出（≤30 行）+ 正在 debug** → 注入，省 2 turn
- ❌ **pytest 長輸出（≥100 行）** → 不注入，OCR 噪音 +77% token
- 🎯 **安全預設**：帶 `--tail 20`，消除長輸出懲罰
- 不注入條件：無 active watcher、Batch CI、用戶明確跳過

## 架構（選項 A）

```
新 hook：autogo-auto-trigger.ps1（matcher: ".*"，排除 /autogo 開頭）
   ↓
載入 ~/.claude/autogo-trigger-policy.json
   ↓
評估觸發規則 → 決定 action（inject | suggest | skip）
   ↓
若 inject/suggest：輸出 [autogo-suggest] 塊（附 triggered_by / confidence）
   ↓
SKILL.md 處理 [autogo-suggest]：
  - inject → 自動帶入 top_ocr 摘要
  - suggest → 顯示 "需要螢幕 context 嗎？" 提示
  - skip → 靜默
```

## 計畫 milestone

- [x] M1：建立 autogo-trigger-policy.json（初始 policy，基於 A/B 結論）
- [x] M2：autogo-auto-trigger.ps1（hook 腳本，評估 policy 並輸出 [autogo-suggest]）
- [x] M3：settings.json 加 hook 配置（matcher: "^(?!/autogo)"）
- [x] M4：SKILL.md 加 [autogo-suggest] 處理邏輯（Step 0.5）
- [x] M5：進度檔更新 + commit

## Fallback 指引
- rollback branch: `git checkout main`
- 觸發政策只需改 autogo-trigger-policy.json，無需改 hook 或 SKILL.md
