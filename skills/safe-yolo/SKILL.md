---
name: safe-yolo
description: 不停下來的執行模式。當使用者輸入 /safe-yolo <任務描述> 時啟動：把任務拆成 2~5 個 milestone，每完成一個就 commit + 更新進度檔，全程不向使用者確認方向，直到完成或真的卡死為止。適用情境包括「直接做不要停」、「一口氣把 X 做完」、「自動推進到能跑為止」等指令。
---

# /safe-yolo — 不停執行 + 安全網模式

當使用者觸發 `/safe-yolo <任務描述>`，按下列規則執行任務，直到完成或真的卡死為止。

## 執行守則

1. **不要停下來問問題**。除非觸發以下「強制停下」條件，否則持續推進到任務完成：
   - 即將執行不可逆且影響範圍超出 working directory 的操作（`git push --force`、刪 remote branch、發 PR、寄訊息等）
   - 觸碰到 `.claude/settings.json` 的 `permissions.deny` 範圍
   - 對使用者隱含意圖有重大歧義，且選錯方向後無法輕易回滾

2. **Milestone-based commit**。把任務拆成 2~5 個邏輯里程碑，每完成一個就立刻 `git commit`（不要等全部做完才一次 commit）。Commit message 用 `Mn: <短描述>` 開頭，讓事後 `git log` 一眼看出進度。

3. **進度 markdown**。在任務開始時於 `docs/progress-<task-slug>.md`（或專案內合適位置）建立進度檔，內容至少包含：
   - **目標**：一段話講清楚要達成什麼
   - **計畫 milestone**：列表 + 每項預期產出
   - **進度日誌**：每完成一個 milestone 追加 `## Mn — <title>` 段落，記錄做了什麼、commit hash、遇到的問題與決策
   - **Fallback 指引**：若中途要被人接手或 rollback 到某個 milestone，最少需要的指令與檔案清單

   進度檔每完成一個 milestone 就更新並 commit 進去。

4. **卡關處理**：若同一個錯誤嘗試 3 次以上仍未解決，或某個操作預估超過 10 分鐘且無進展：
   - 先 commit 目前可工作的狀態（即使不完整也標 WIP）
   - 在進度檔記錄卡關點、嘗試過的方法、可能的後續方向
   - 才停下來向使用者報告

5. **完成後的最終報告**：用 3~5 行說明做了什麼、commit 範圍、進度檔位置、後續建議。

## 不要做的事

- 不要中途請使用者「確認方向」；既然他叫了 /safe-yolo，方向已確認。
- 不要把所有變動塞進一個 commit。
- 不要省略進度檔（即使任務很小也至少留一段紀錄）。
- 不要在 commit message 裡寫小說；標題 ≤ 72 字，需要細節寫在進度檔。

## 觸發範例

```
/safe-yolo 把 strategies/ 接到 zipline-tej 期貨回測框架
/safe-yolo 重構 crawler/utils 把重複的 rate-limit 邏輯收斂
/safe-yolo 加 GitHub Actions CI 跑 pytest
```
