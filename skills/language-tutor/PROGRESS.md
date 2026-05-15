# language-tutor skill — Progress

## 目標

打造一個能在 Claude Code 內以 slash command（`/language-tutor`）或 sub-agent 方式啟動的「多語一對一家教」。功能涵蓋：

- 自我介紹 + 等級診斷（CEFR A1–C2）
- 五種教學模式：自由對話、單字抽考、文法演練、聽寫、口說/翻譯抽考
- 呼叫 Windows TTS（PowerShell SAPI 為基礎，edge-tts 為高品質選項）讓使用者隨時聽外語發音
- 支援英、日、法、德、西、義、韓、中（普通話）等常見語言

## 計畫 milestone

| M | 內容 | 預期產出 |
|---|------|---------|
| M1 | Skill scaffold | `skills/language-tutor/`、`SKILL.md` skeleton、`PROGRESS.md`、`scripts/`、`data/` |
| M2 | 教學流程主體 | `SKILL.md` 含五種模式 SOP、TTS 呼叫規則、CEFR 等級評估表 |
| M3 | TTS 腳本 | `scripts/speak.ps1`（SAPI 多語）、`scripts/speak-edge.py`（neural voice，可選） |
| M4 | 入口與 sub-agent | `commands/language-tutor.md`、`agents/language-tutor.md` |
| M5 | 實機測試 + 結算 | TTS smoke test 結果、PROGRESS.md 完成段落、使用範例 |

## 進度日誌

### M1 — Skill scaffold（2026-05-15）

- 建立目錄 `skills/language-tutor/`、`scripts/`、`data/`
- 寫入 SKILL.md skeleton（含完整 frontmatter description）
- 寫入本 PROGRESS.md
- Skill 已被 Claude Code 偵測到（system reminder 出現 language-tutor 條目）

### M2 — 教學流程主體（2026-05-15）

- 完整 SKILL.md：Phase 0（啟動 4 設定 + 三句快速等級診斷）+ Phase 1（chat / vocab / grammar / dictation / quiz 五種模式 SOP）
- TTS 呼叫規則表（時機、語言碼對照、語速、engine 切換）
- 進度記錄串接 `/save-to-obsidian`
- 禁止事項列表（不過度誇讚、不 spoiler、不一次出超過 10 題等）

### M3 — TTS 腳本（2026-05-15）

- `scripts/speak.ps1`：Windows SAPI 主路徑，culture exact match → language family fallback；`-Engine edge` 切到 neural；`-ListVoices` 列出已裝 voice
- `scripts/speak-edge.py`：edge-tts neural voice helper，輸出 mp3 到 tempfile 並透過 MediaPlayer 播放
- 環境變數 `LANGTUTOR_EDGE_VOICE_<LANG>` 可覆蓋預設 voice

### M4 — Slash command + sub-agent（2026-05-15）

- `commands/language-tutor.md`：解析 $ARGUMENTS（語言/模式/等級/時間），轉交 SKILL.md SOP
- `agents/language-tutor.md`：tools=Read,Write,Edit,Bash,Glob,Grep，model=sonnet（5–20 分鐘 session 用 sonnet 比較划算）
- 全部檔案以 CRLF 換行寫入（符合既有 skill 慣例）

### M5 — 實機測試 + 結算（2026-05-15）

- `-ListVoices` 結果：本機 SAPI 安裝 en-US (Zira) + zh-TW (Hanhan / Yating / Zhiwei)
- en-US 播音 ✓（Microsoft Zira Desktop, rate=0）
- zh-TW 播音 ✓（Microsoft Hanhan Desktop, rate=-1）
- ja-JP 預期失敗 → 觸發 fallback error 並建議使用者切 `-Engine edge`，文字清楚 ✓
- 修 bug：原本 `-ListVoices` 與 `-Text`/`-Lang` mandatory 衝突 → 改用 ParameterSetName=`Speak`/`List` 分組
- edge-tts 模組未安裝（Python 可用）。要 ja/fr/de/ko/es 等本機沒裝 SAPI voice 的語言，使用者執行 `pip install edge-tts` 即可（SKILL.md 與 command 都已寫明，不自動安裝）

#### 已知限制

1. 本機 Windows 預設只裝 en-US + zh-TW SAPI voice。要練其他語言，**任一**：
   - 安裝對應 Windows 語言包（控制台 → 時間和語言 → 語言 → 新增 → 啟用「語音」）
   - 或 `pip install edge-tts` 後在呼叫時加 `-Engine edge`（推薦：neural voice 品質明顯較好）
2. 沒有自動安裝任何套件 — 完全照 SKILL.md「禁止事項」執行。
3. `.claude` 在 Windows 端不是 git repo，因此本次跳過 `git commit` 部分（/safe-yolo 的精神改以 PROGRESS.md 落實里程碑追蹤）。

### M6–M9 — Edge TTS 安裝與全語言解鎖（2026-05-15，第二次 /safe-yolo）

**動機**：本機 SAPI 只有 en-US + zh-TW，使用者實際想練的日/法/德/韓/西都沒覆蓋。執行第一輪結尾建議的 `pip install edge-tts`。

#### M6 環境調查

- Python 3.12.10（`C:\Users\User\AppData\Local\Programs\Python\Python312\python.exe`，per-user，不需 admin）
- pip 25.0.1
- PyPI `pypi.org/simple/edge-tts/` 回 200，網路通

#### M7 安裝

- `python -m pip install --upgrade edge-tts` → `edge-tts 7.2.8` 連同 aiohttp / tabulate / certifi 等 13 個依賴一併裝入 site-packages
- `import edge_tts` ✓、`edge-tts --help` CLI ✓

#### M8 三語 + 韓文 neural voice smoke test

| Lang | Voice | Rate | 結果 |
|------|-------|------|-----|
| ja-JP | `ja-JP-NanamiNeural` | +0% | ✓ |
| fr-FR | `fr-FR-DeniseNeural` | +0% | ✓ |
| de-DE | `de-DE-KatjaNeural` | -10% | ✓（修 bug 後） |
| ko-KR | `ko-KR-SunHiNeural` | +0% | ✓ |

**修一個 bug**：原本 `speak.ps1` 把 `--rate -10%` 用空白分隔傳給 `speak-edge.py`，Python argparse 把 `-10%` 誤判為新 flag。改成 `--rate=$rateArg`（用 `=` 連在一起）後 OK。

#### M9 文件更新

- 本段 PROGRESS 紀錄
- SKILL.md 加一行 edge engine ready 標記
- CRLF normalize 全部修改過的檔

#### 現況

- SAPI engine：en-US / zh-TW 可離線（預設）
- Edge engine：日 / 法 / 德 / 韓 / 西 / 義 / 葡 / 俄 / 泰 / 越 等已預先 mapping，呼叫時加 `-Engine edge` 即啟用 neural voice，需要網路
- 預設仍是 SAPI（離線、零依賴）；要用 neural voice 由 tutor 在 dictation / 重點句時自行決定切換

## Fallback 指引

如需中途接手或 rollback：

1. Skill 主檔位置：`C:\Users\User\.claude\skills\language-tutor\SKILL.md`
2. 對應 slash command：`C:\Users\User\.claude\commands\language-tutor.md`
3. 對應 sub-agent：`C:\Users\User\.claude\agents\language-tutor.md`
4. TTS 腳本：`C:\Users\User\.claude\skills\language-tutor\scripts\speak.ps1`
5. 如果要完全移除：刪除上述四個檔案 + skill 目錄即可，無任何外部依賴需清理
