---
name: kan
description: 用 kan CLI 操作團隊的 Jira 看板（gsinvest.atlassian.net 專案 KAN）——查看板、看單張、開單、回覆、轉狀態。當使用者輸入 /kan、提到「ticket」「工單」「看板」「Jira」「開單」「這張單」「誰在做什麼」「我今天做了什麼」、貼出 `KAN-123` 這種編號、或說「幫我開一張單」「把 KAN-443 轉完成」「回覆那張單」「看一下 chihao 手上有什麼」時啟動。團隊 ticket 在 Jira 不在 GitHub Issues，所以任何跟工單/任務指派/進度回報有關的請求都走這裡。純讀取可直接做；任何寫入都要有使用者明確指示。
---

# kan — Jira 看板 CLI

團隊的 task ticket 在 **Jira**（`gsinvest.atlassian.net`，專案 `KAN`），**不在 GitHub Issues**（全 org 160+ repo 只有 1 張機器人開的 issue）。要動 ticket 一律用 `kan`。

`kan` 是 PowerShell 函式，安裝在 `~/.kan/kan.ps1`，由 `$PROFILE` 載入。用 **PowerShell tool** 呼叫。若回報 `kan: The term 'kan' is not recognized`，先跑 `. $PROFILE`；仍然沒有就是沒安裝，指路 `gsinvest017-lab/gs-kan-cli`。

---

## 最高原則：寫入掛的是使用者的名字

`kan` 用的是使用者本人的 Jira API token。**你做的任何建立/留言/轉狀態，在稽核紀錄與 changelog 上跟使用者親手做的完全無法區分**，而且看板上其他 6 位同事都看得到。

因此：

- **讀取**（`kan`、`kan me`、`kan today`、`kan v`、`kan who`、`kan jql`）→ 隨時可做，不必問。
- **寫入**（`new` / `say` / `mv` / `done`）→ **必須有使用者明確指示**。不要「順手幫忙開一張」、不要為了讓進度好看而補單。
- **絕不虛構內容。** ticket 的描述只能來自實際證據——commit、PR、測試輸出、使用者親口說的。要寫「已驗證」就得先有驗證輸出。查不到證據就說查不到，不要用推測填。
- **動別人的單一定帶 `-Say` 說明原因**（`kan` 只會提醒不會擋）。無聲改掉同事的狀態，在 standup 上會變成沒人知道原因的懸案。
- **批次寫入前先講你要做什麼**，列出清單再動手，不要一次噴 10 張出去。

---

## 指令

| 指令 | 做什麼 |
|---|---|
| `kan` | 全看板未完成，依人分組 |
| `kan me` | 我的未完成 |
| `kan today` / `kan today 7` | 我今天（或最近 N 天）動過的，**含已完成**，依狀態分組 |
| `kan <人名片段>` | 某人的未完成。模糊比對：`kan chihao`、`kan 陳` |
| `kan v KAN-443` | 看單張，含描述與所有評論 |
| `kan new "標題"` | 開單。`-To 誰` `-Type task\|epic\|sub` `-Desc "..."` `-Parent KAN-1` |
| `kan say KAN-443 "留言"` | 回覆 |
| `kan mv KAN-443 wip` | 轉狀態 `todo` / `wip` / `done`，可加 `-Say "原因"` |
| `kan done KAN-443 "說明"` | 轉完成並留言，一步 |
| `kan who` | 可指派的人 |
| `kan jql "<JQL>"` | 任意 JQL，help 表達不了的查詢走這裡 |
| `kan doctor` | 診斷設定與連線 |

`k` 是短別名。

---

## 三個會讓你判斷錯的地方

**1. `kan me` 濾掉已完成。** JQL 帶 `statusCategory != Done`。剛轉完成的單會立刻從 `kan me` 消失——這是設計，不是 bug。使用者問「我剛開的單怎麼不見了」時，答案通常是這個，改用 `kan today` 或 `kan me -All`。

**2. 狀態與類型的名稱是簡體中文在地化的**（`待办` / `正在进行` / `完成`；`任務` / `大型工作` / `Subtask`）。**你不需要知道這些字**——`kan` 只收 `todo|wip|done` 與 `task|epic|sub`，內部用語言無關的 `statusCategory.key` 反查。**永遠不要直接下 `acli --status "Done"`**，那一定失敗。

**3. `-To` 用顯示名片段。** 不要去查 accountId——`kan` 會模糊比對。對到多人會報錯要你講精確，對不到會叫你看 `kan who`。本站 9 個可指派的人裡只有 1 個公開 email，所以 email 這條路對同事行不通。

---

## 典型任務怎麼做

**「幫我把今天做完的事開成 ticket」** —— 先取**實際證據**再開單：

1. `git log --since=midnight` 或 `gh pr list --state merged --search "merged:>=<今天>"` 找出真的做了什麼。
2. 把結果**列給使用者看**，講清楚你打算開幾張、標題是什麼。
3. `kan new` 建立，描述寫「做了什麼 / 關鍵決定 / 驗證數字 / PR 連結」。
4. 要標完成才 `kan done <key> "<合併時間與證據>"`。
5. **PR 還開著的不算完成**，留在 `todo` 或 `wip`。

**「KAN-443 現在怎樣」** —— `kan v KAN-443`，直接讀出狀態、負責人、描述與評論。

**「誰卡住了」** —— `kan jql "project = KAN AND statusCategory = \"In Progress\" AND updated <= -3d ORDER BY updated"`。注意用工作天思考，週五更新、週一看，日曆天算 3 天但只過了 1 個工作天。

---

## 邊界

- **本 skill 只管 ticket。** 每日看板摘要推 Slack 是 `gs-pmo` 的 `pmo standup`，那條路是**唯讀**的，不要往裡面加寫入。
- Atlassian 的 MCP server 目前回 `403 The app is not installed on this instance`（需要 org admin 啟用）。**那跟 `kan` 無關**——`kan` 走 API token + REST 的獨立路徑，照常可用。看到那個 403 不要以為 `kan` 壞了。
- 工具本體在 `gsinvest017-lab/gs-kan-cli`。要改 `kan` 的行為改那個 repo 的 `src/kan.ps1` 再重跑 `install.ps1`；直接編輯 `~/.kan/kan.ps1` 會在下次安裝時被覆蓋。
