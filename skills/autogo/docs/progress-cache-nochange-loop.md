# safe-yolo: autogo SKILL.md — cache 無變化偵測 + /loop 用法

## 目標
FULL PATH 時若所有 watcher 的 `cache_meta.hit=true` 且 `phash_distance=0`，
跳過詳細 OCR 輸出並回覆「畫面無變化（cached）」；
同時在 SKILL.md 補充 `/loop` 搭配用法範例。

## 計畫 milestone

- [x] M1：在 1b FULL PATH 加入 cache_meta 前置判斷邏輯（全無變化 / 部分有變化兩條分支）
- [x] M2：在 SKILL.md 末尾加「搭配 /loop 做定期監控」章節 + 建本進度檔 + commit

## 進度日誌

### M1 — cache_meta 無變化前置判斷

在 `1b` 的欄位說明列表後、「用這些結構化資料」段落前插入三條規則：
1. 判斷條件：`hit=true` 且 `phash_distance=0`（或欄位不存在）
2. 全部無變化 → 輸出「畫面無變化（cached）」並停止
3. 部分無變化 → 只對有變化的 watcher 展開 OCR，其餘一行摘要

### M2 — /loop 用法區塊 + 進度檔

在「不要做的事」章節後追加新章節，說明：
- `/loop` 與 `/autogo` 的組合方式
- Watcher tick interval 與 /loop 間隔的關係
- 三個常用場景範例表格

## Fallback 指引

若需要 rollback：
```
git revert HEAD
```
或直接 `git diff HEAD~1 HEAD -- SKILL.md` 查看本次改動後手動復原。
