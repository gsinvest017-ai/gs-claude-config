# safe-yolo: autogo-meta 路由塊 + SKILL.md 精簡

## 目標
把 SKILL.md 裡五段 JSON 解析判斷移進 context_summary.py，
輸出 [autogo-meta] 預計算 signals，讓 SKILL.md 從「思考者」變「路由器」，
縮短 agent command response time。

## 計畫 milestone

- [x] M1：context_summary.py 新增 [autogo-meta] 塊輸出（filter_applied / filter_unmatched / stub / cache_hit_all）
- [x] M2：SKILL.md 1b 改為 meta 路由決策表，移除五段重複判斷邏輯
- [x] M3：進度檔 + commit

## 進度日誌

### M1 — context_summary.py [autogo-meta] 塊

新增：
- META_OPEN/CLOSE 常數、_STUB_MARKERS 清單
- parse_full_json 擴充提取 filter_applied / filter_unmatched / stub / cache_hit_all
- format_meta_block(parsed) 函式
- main() 在 [autogo-response] 後、[autogo-json] 前輸出 [autogo-meta]

驗證輸出：
```
[autogo-meta]
filter_applied: true
filter_unmatched: []
stub: true
cache_hit_all: false
[/autogo-meta]
```

### M2 — SKILL.md 精簡

Step 1 從 5 個判斷段落（cache_meta / 快捷路徑 / filter 透明度 / stub 偵測 / preview-first）
壓縮成一張「路由決策表」+ 「FULL PATH 規則」清單。
SKILL.md 字數大幅減少，路由邏輯變為線性 switch。

## Fallback 指引
- autogo repo rollback: `git revert HEAD` 在 C:\Users\User\autogo
- gs-claude-config rollback: `git revert HEAD` 在 C:\Users\User\gs-claude-config
- 影響檔案：
  - autogo: src/autogo_dash/context_summary.py
  - gs-claude-config: skills/autogo/SKILL.md
