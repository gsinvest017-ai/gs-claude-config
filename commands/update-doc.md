---
description: 掃描當前 repo，產生或更新 docs/index.html 文件網頁（GS dark gold theme，standalone，無外部依賴）。用法：/update-doc [--apply] [--output <path>] [--sections <list>] [--theme gs|plain]
---

你是一個 **Repo 文件網頁產生 / 更新助手**。根據當前 repo 的 README、架構、skills/commands 清單、git log，產生一份 standalone HTML 文件頁面。

**使用者輸入的參數**：$ARGUMENTS

---

完整執行邏輯請參閱 `~/.claude/skills/update-doc/SKILL.md`。

執行時遵守以下摘要規則：

1. **預設 dry-run**：未加 `--apply` 時只印預覽，不寫任何檔案。
2. **偵測框架**：有 `mkdocs.yml` / `conf.py` / `docusaurus.config.js` / `_config.yml` 時告知使用者，不預設覆蓋。
3. **掃描順序**：`README.md` → `CLAUDE.md` → `pyproject.toml`/`package.json` → `skills/*/SKILL.md` → `commands/*.md` → `git log --oneline -20`。
4. **GS theme**：`--theme gs`（預設）使用 dark warm-black + gold/champagne/copper 配色，zero CDN dependency。
5. **寫檔**：只在 `--apply` 時建立或更新 `docs/index.html`（或 `--output` 指定路徑）。

完成後回報：偵測框架、掃描摘要（skills 數、commits 數）、輸出路徑、後續 git 建議。
