# 進度：新增 /apply-gs-templete 全域 slash command

## 目標

新增一個 system-level global agent command **`/apply-gs-templete`**：當在任一 repo 觸發時，從 `C:\Users\User\gs-trading-portal`（**Genesis gold theme** 來源）抽取整體配色與設計 tokens（`:root` CSS variables、字體、漸層、邊框風格、卡片陰影等），並 apply 到當前 repo 的 dashboard UI，讓所有專案 dashboard 視覺一致。完成後安裝到 user-scope（全域）。

注意：skill 名稱**沿用使用者原始拼寫 `apply-gs-templete`**（templete）以與 slash command 對應；body 內可以用 template 正確拼寫。

## 計畫 milestone

| Milestone | 內容 | 預期產出 |
|-----------|------|----------|
| **M1** | 進度檔 + `/apply-gs-templete` skill（含實際從 `gs-trading-portal/style.css` 抽出的 token 結構） | `docs/progress-apply-gs-templete-command.md`、`skills/apply-gs-templete/SKILL.md` |
| **M2** | 驗證全域註冊 + 收尾 | frontmatter 解析通過、出現在 skill 清單、進度檔收尾 |

## 進度日誌

<!-- 每完成一個 milestone 在此追加一段 -->

### M1 — 進度檔 + /apply-gs-templete

- 偵察 `C:\Users\User\gs-trading-portal\style.css`：確認是 **Genesis gold theme**（dark warm-black `--bg-0..2` + gold/champagne/copper/bronze accent family + Inter sans / JetBrains Mono mono + 漸層品牌字 + radial-gradient body 背景 + dim 冷色 grid）。`:root` 約 30 個 CSS vars。
- 新增 `skills/apply-gs-templete/SKILL.md`：frontmatter（含完整觸發語清單）+ 8 段流程：
  1. 解析參數（`--source` / `--target` / `--scope` / `--mode` / `--include-3d` / `--include-brand` / `--preserve`）
  2. 前置檢查 source 結構
  3. **token 抽取核心**：A palette（從 `:root` 用 regex 抽全部 `--*`）、B body 背景（radial-gradient 疊層原樣搬）、C 品牌漸層文字（opt-in）、D 元件 token（卡片 / toolbar / header / 陰影慣例）
  4. 偵測 target 載體（HTML / Streamlit / Gradio / Plotly Dash / React / Vue / Tailwind，含 autogo 特記）
  5. Plan / dry-run 表
  6. apply 三 mode（`inject` 預設 / `override` / `fork`）+ Streamlit 變體（`.streamlit/config.toml [theme]` + CSS 補強）
  7. 驗證（CSS 文法 + 可選 Chrome DevTools 截圖前後比對）
  8. 完成回報
- 關鍵設計決策：
  1. **不 hard-code 配色值**——每次從 source 即時抽，主題更新自然帶入
  2. **預設 dry-run**，需 `--apply` 才寫檔
  3. **品牌字 / logo 預設不套**（`--include-brand` 才動），避免別 repo 也叫 GS 引起衝突
  4. **不動 a11y / JS 邏輯 / data 流**，只動 layout 樣式
  5. **inject mode** 用 `<!-- BEGIN apply-gs-templete --> ... <!-- END -->` 標籤包圍，重跑只更新內部
  6. **保留 skill 名稱拼寫 `apply-gs-templete`**（templete）配合使用者 slash command 拼法
- 兩檔正規化為 CRLF。

## Fallback 指引

- Git repo：`C:\Users\User\gs-claude-config`（透過 `~/.claude` symlink 存取），分支 `main`。
- 本任務只 commit 到本機 main，不 push。
- Rollback：`git -C C:\Users\User\gs-claude-config log --oneline` 找 `Mn:` commit，`git reset --hard <hash>` 回退。
- 整個撤掉：刪 `skills/apply-gs-templete/`、本進度檔，再 `git checkout -- .`。
