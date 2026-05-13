# Superpowers Skills 使用指南

> Plugin：`superpowers@claude-plugins-official` v5.1.0
> 安裝方式：在 Claude Code 內打 `/plugin` 挑 marketplace `claude-plugins-official` → superpowers → `user` scope
> 確認安裝：`grep superpowers ~/.claude/plugins/installed_plugins.json` 應看到 `"scope": "user"`

---

## TL;DR

Superpowers 提供 14 個「工程紀律」skill，**不是 slash command**（沒有 `/brainstorming` 可以打）。
它們由 Claude 看你訊息的語意**自動觸發**，在開始幹活前先載入相應的工作流程指引。

---

## 三種觸發方式

### 1. 講你的任務，Claude 自動觸發（90% 情境）

每個 skill 的描述裡寫了「Use when...」條件，Claude 偵測到匹配就在回應前先呼叫該 skill。

| 你說 | Claude 會自動拉進來的 skill |
|------|---------------------------|
| 「我想加一個 X 功能」/「幫我做 Y 元件」 | `brainstorming` →（視情況）`writing-plans` |
| 「這個測試掛了」/「行為跟預期不一樣」 | `systematic-debugging` |
| 「幫我把這個分支收掉」/「準備 merge 了」 | `finishing-a-development-branch` |
| 「審一下這個 PR」 | `requesting-code-review` |
| 「我覺得 reviewer 講的不對」 | `receiving-code-review` |
| 「跑這幾個獨立任務」 | `dispatching-parallel-agents` |
| Claude 自己宣稱「完成了」/「修好了」之前 | `verification-before-completion`（自帶安全網） |

### 2. 直接點名

當 Claude 判斷錯了，或你想強制某個流程：

```
用 systematic-debugging 來查這個錯
請先 brainstorming 一下這個功能的範圍
跑 dispatching-parallel-agents 同時做 A 和 B
跑 test-driven-development 寫這個 feature
```

### 3. Meta skill（你通常不用主動叫）

- `using-superpowers` — Claude 自己用的「使用其他 superpower 前的查表規則」
- `writing-skills` — 你想自己寫新 skill 時用，跟既有 `/skill` (commands skill) 互補

---

## 14 個 Skill 角色一覽

```
創意 / 設計階段
├── brainstorming             把模糊需求拆成具體規格
└── writing-plans             把規格寫成多步驟實作計畫

執行階段
├── executing-plans                  分階段執行 plan，checkpoint review
├── subagent-driven-development     在當前 session 派 subagent 跑獨立任務
├── dispatching-parallel-agents     一次派多個 agent 跑互不相依任務
├── using-git-worktrees             開隔離 worktree
├── test-driven-development         先寫 test 再寫 code
└── systematic-debugging            bug / 行為異常時逐步排查

收尾階段
├── verification-before-completion  宣稱完成前必跑驗證指令
├── requesting-code-review          自我 review
├── receiving-code-review           被 review 後怎麼回應
└── finishing-a-development-branch  merge / PR / cleanup 結構化決策

Meta
├── using-superpowers               skill 之間如何串
└── writing-skills                  寫新 skill
```

---

## 與你自家 Skill 的搭配

你既有的 `/safe-yolo`、`/quant-researcher`、`/review-strategy` 都還在，**優先級不變**：

| 觸發機制 | 你自家的 | Superpowers |
|----------|---------|-------------|
| Slash command (`/...`) | ✅ | ❌ |
| 語意自動觸發 | ❌（要打 `/`） | ✅ |
| 衝突？ | 不會，兩套互補 | |

**實用組合範例**：

```
1. /quant-researcher 設計一個動量策略
   → 出 strategy_XXX_YYYYMMDD.md

2. /review-strategy strategy_XXX_YYYYMMDD.md
   → 出 review_XXX_YYYYMMDD.md（含 PASS/FAIL 判定）

3. 「幫我把這個策略加入波動度過濾」
   → Claude 自動：brainstorming → writing-plans → 視情況 git-worktrees → 實作

4. 「完成了，準備 commit」
   → Claude 自動：verification-before-completion → 跑驗證 → 才能宣稱完成

5. /safe-yolo 重構 utils/rate-limit
   → safe-yolo skill 接管，全程不停下來確認
```

---

## 同步到其他機器

`~/.claude/settings.json` 因為 machine-specific **沒被 symlink**（只有 `settings.template.json` 在 repo 內）。
要讓新機器跑完 `install.sh` 也直接享受 superpowers，兩步：

### Step 1: 改 settings.template.json（一次性）

```bash
$EDITOR ~/gs-claude-config/settings.template.json
```

把 `enabledPlugins` 區塊改成：

```json
"enabledPlugins": {
    "typescript-lsp@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true
}
```

Commit + push。

### Step 2: 新機器安裝完 install.sh 後，仍要拉檔

`enabledPlugins` 只是 flag，plugin 本體還是要從 marketplace 拉下來。新機器流程：

```bash
git clone https://github.com/gsinvest017-ai/gs-claude-config.git ~/gs-claude-config
cd ~/gs-claude-config && ./install.sh

# 開 Claude Code，然後：
/plugin    # 挑 superpowers → install scope: user
```

> 若想徹底免互動（讓 `install.sh` 自動拉所有 plugin），可以再寫一支 `scripts/install-plugins.sh` 跑 `claude plugin install superpowers@claude-plugins-official`——但目前 plugin 系統的 CLI 介面還在演進，沒做。

---

## 確認你目前的狀態

```bash
# 1. Plugin 已安裝？
grep -A2 'superpowers' ~/.claude/plugins/installed_plugins.json | head -5

# 2. 已 enabled？
grep -A5 enabledPlugins ~/.claude/settings.json

# 3. Skill 名單可用（在 Claude Code session 內看 system reminder）
#    應該看到 14 條以 superpowers: 開頭的 skill
```

預期：

```
"superpowers@claude-plugins-official": [
  {
    "scope": "user",
    ...
  }
]

"enabledPlugins": {
  "typescript-lsp@claude-plugins-official": true,
  "superpowers@claude-plugins-official": true
}
```

---

## 故障排除

| 問題 | 處理 |
|------|------|
| `/plugin` 找不到 superpowers | `/plugin update-marketplace claude-plugins-official` 後重試 |
| 安裝完沒 skill 出現 | Claude Code 內跑 `/reload-plugins`（裝完會提示你跑） |
| 想停用 | `/plugin disable superpowers`，或編 `settings.json` 把 enabledPlugins 設 false |
| 想升級到新版 | `/plugin upgrade superpowers@claude-plugins-official` |
| Plugin 行為跟預期不符 | 檢查 `~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>/skills/<skill-name>/SKILL.md` 看實際 prompt |

---

## 參考

- 你自家 skill 文件：[`add-new-skill.md`](https://github.com/gsinvest017-ai/quant-research-skill/blob/master/add-new-skill.md)
- Claude Code plugin 系統官方文件：在 Claude Code 內打 `/help plugin`
- Superpowers 上游：marketplace `claude-plugins-official` → `superpowers`
