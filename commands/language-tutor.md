---
description: 一對一多語家教（CEFR A1–C2、五種模式、Windows TTS 發音）。用法：/language-tutor [語言] [模式] [時間]
---

# /language-tutor — 多語一對一家教

啟動使用者的私人外語家教 session，依 `~/.claude/skills/language-tutor/SKILL.md` 的完整 SOP 執行。

**使用者輸入的偏好設定（可全部省略）**：$ARGUMENTS

---

## 執行步驟

### Step 1：解析 $ARGUMENTS

`$ARGUMENTS` 可能是空字串、單一關鍵字、或多個 token。容許的詞：

- **語言**：`english` / `en` / `japanese` / `ja` / `french` / `fr` / `german` / `de` / `spanish` / `es` / `italian` / `it` / `korean` / `ko` / `mandarin` / `zh` / `cantonese` / `yue` / `indonesian` / `id`
- **模式**：`chat` / `vocab` / `grammar` / `dictation` / `quiz`
- **時間**：`5m` / `10m` / `20m` / `30m`
- **等級**：`a1` / `a2` / `b1` / `b2` / `c1` / `c2`

順序不限，大小寫不拘。例：
- `/language-tutor` → 全部問使用者
- `/language-tutor japanese b1 vocab 10m`
- `/language-tutor 法文 dictation`

未指定的欄位走 SKILL.md Phase 0 的對話問答。

### Step 2：載入 SKILL.md 並進入 Phase 0

完整讀取 `C:\Users\User\.claude\skills\language-tutor\SKILL.md`，依其 Phase 0–1 流程開始 session。把 Step 1 解析出的設定當作預先填好的答案，**不要重複問使用者已經給的欄位**。

### Step 3：呼叫 TTS

按 SKILL.md 的 §TTS 呼叫規則，於對應節點用 Bash tool 執行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\.claude\skills\language-tutor\scripts\speak.ps1" -Text "<句子>" -Lang <BCP-47> -Rate <-3~3>
```

### Step 4：Session 結束時

依 SKILL.md「進度記錄」段，**主動建議**使用者把本次摘要存到 Obsidian（呼叫 `/save-to-obsidian`）。

---

## 注意事項

- 不要把 TTS 失敗當成 fatal — 顯示錯誤訊息後繼續教學流程。
- 不要自動安裝 Python 套件；若 `edge-tts` 沒裝，告訴使用者 `pip install edge-tts` 即可，預設仍走 SAPI engine。
- 不要省略 Phase 0 的等級確認；level 對教材難度影響大。
