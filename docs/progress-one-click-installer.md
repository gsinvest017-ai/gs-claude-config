# 進度：一鍵安裝 — 給其他使用者的 gs-claude-toolkit 分發

## 目標
把本 repo（`~/.claude/` 的 skill / command / agent / hook library）包裝成**其他使用者可一鍵安裝**的兩條路徑：

1. **Claude Code 原生 plugin + marketplace**（最「一鍵」）：`/plugin marketplace add` → `/plugin install`。
2. **跨平台安裝腳本 + 遠端一行**：`curl … | bash`（POSIX）、`irm … | iex`（Windows）。

使用者決策（2026-07-08）：**兩者都做**、**全部打包**（39 支 skill 全含）。

## 關鍵設計約束
- 既有 `install.ps1` / `install.sh` 是**作者本人跨機同步**用（symlink + 個人 CLAUDE.md + clone 個人 fork + 個人 `additionalDirectories`）。**不動它們**，另開 consumer-facing 入口，避免陌生人跑到作者專用腳本。
- `skills/quant-researcher`、`skills/review-strategy` 是指向 sibling repo `quant-research-skill` 的 **symlink**。
  - Script 路徑：可 clone sibling 解析 symlink；但為了讓 plugin 也能用，改為 **vendor（實體複製）**。
  - 保留作者在 sibling repo 的 live-edit：新增 `scripts/sync-vendored-skills.{sh,ps1}` 由 sibling 回灌。
- Plugin 路徑的 hook 必須是**單一跨平台指令**（plugin hooks.json 無法依 OS 切換）→ 用 Node shim `hooks/autopilot.mjs`（不需 jq，Node 隨 Claude Code 附帶）。
- Script 路徑的 hook 沿用既有 `.ps1` / `.sh` + OS-correct settings 注入。
- Consumer 安裝**預設 copy 模式**（非 symlink），不需 Windows Dev Mode；`--link` 供進階者。
- **絕不** 覆蓋使用者既有 `settings.json`；有 `jq` 就安全 merge，否則印出 snippet 讓其手動併。
- Consumer 安裝**不裝**個人 `CLAUDE.md`（那是作者私有專案感知）。

## Milestones
- [x] **M1**：Plugin scaffolding — `.claude-plugin/marketplace.json`、`.claude-plugin/plugin.json`、`hooks/autopilot.mjs`、`hooks/hooks.json`
- [x] **M2**：Vendor 兩支 sibling skill + `scripts/sync-vendored-skills.{sh,ps1}`
- [x] **M3**：Consumer 安裝腳本 — `install-toolkit.{sh,ps1}`（copy-mode + 遠端一行 + 安全 settings merge）+ `uninstall-toolkit.{sh,ps1}` + `scripts/merge-settings.mjs`
- [x] **M4**：文件 — `INSTALL.md`（雙語）+ README quickstart + 本進度檔收尾

## 進度日誌
- 2026-07-08 起案。盤點：39 skills / 20 commands / 5 agents / autopilot hooks；無既有 plugin manifest；sibling repo 本機存在可 vendor。
- M1：plugin manifest + 跨平台 Node hook shim（`autopilot.mjs` 依 `hook_event_name` 分派 arm/Stop，不需 jq）。smoke test 通過：arm 建旗標、Stop 對同 session block、外來 session 不劫持、disarm 清除。
- M2：`skills/quant-researcher`、`skills/review-strategy` 由 symlink 改為 vendored 實體檔（各一支 SKILL.md）；新增 sync 腳本從 sibling 回灌。
- M3：consumer 安裝／解除安裝腳本 + Node 版 settings 安全 merge。sandbox HOME 全流程驗證：安裝 20 cmd/39 skill/5 agent、保留使用者自有 skill 與 model/theme、hooks 併入且冪等（3× 不重複）、uninstall 完整還原。
- M4：`INSTALL.md`（EN + 中文，含 plugin env-cap 限制說明）、README 新增「for other users」區塊並把作者 symlink 路徑標為 contributor-only。

## 尚待人工確認
- **commit**：依 harness 規則「使用者未明說前不自動 commit」，本次變更尚未 commit，等使用者確認。
- **plugin `/plugin install` 實測**：manifest 已 JSON 驗證，但尚未在真實 Claude Code marketplace 流程跑過一次（需 push 到 GitHub 後由外部使用者端驗證）。
- 真正對外發布前，`marketplace.json` / `plugin.json` / `install-toolkit.*` 的 owner、repo URL（`gsinvest017-ai/gs-claude-config`）請確認無誤。
