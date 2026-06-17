# Progress — README SSH key prerequisite for clone-all.sh

Started: 2026-05-18
Trigger: `/safe-yolo ok`（cross-machine 移植實戰後發現 README 沒把 SSH key 列為 `clone-all.sh` 的明顯前置條件）

## 目標

把「SSH key 必須先設定好並加到 GitHub」這個前置條件，從現在埋在 README line 104 表格的位置，提升到 `clone-all.sh` 段落的開頭，讓新機器使用者照流程做不會卡在 `Permission denied (publickey)`。

## 背景

實戰時的踩坑紀錄：
- 在這台 Ubuntu 上 `chezmoi apply` 成功後，跑 `scripts/clone-all.sh` 全 5 個 repo 都失敗，錯誤是 `git@github.com: Permission denied (publickey)`
- 原因：新機器還沒有 SSH key，repos.txt 內全是 `git@github.com:` SSH URL
- 解法：`ssh-keygen` → 加 pubkey 到 GitHub → 重跑 `clone-all.sh` 成功

README 現況：
- Line 84-97：`clone-all.sh` 使用說明（cp/edit/run 三步）
- Line 104：「SSH private keys | Security | Run ssh-keygen, add the new pubkey to GitHub」— 藏在「Things chezmoi deliberately won't migrate」表格，新使用者不一定會看到那邊就先去跑 `clone-all.sh`

## 計畫 milestone

- **M1** — 建立此進度檔
- **M2** — 編輯 `README.md`，在 `clone-all.sh` 段落前加 **Prerequisite** 區塊（含三行 ssh-keygen 指令）
- **M3** — 更新此進度檔記錄最終結果，commit

## Fallback 指引

若要 rollback：

```bash
cd ~/gs-claude-config
git log --oneline | head -5      # 找 M1 之前的 commit
git reset --hard <hash>          # 危險：丟掉 M1~M3 commit
```

無須額外復原檔案（只動 README + 此進度檔）。

## 進度日誌

### M1 — 進度檔 → `64039d2`

只新增本檔，沒動到其他內容。

### M2 — README SSH prerequisite block → `bd01340`

在 `README.md` `### What chezmoi does NOT clone` 段落最末（line 97 之後、`### Things chezmoi deliberately won't migrate` 之前）插入一個 **Prerequisite** 小段：

- 一句話說明為什麼會踩 `Permission denied (publickey)`
- 三行 ssh-keygen / 貼 pubkey / `ssh -T` 驗證指令
- 補充一條 HTTPS rewrite 備案（給只 clone 公開 repo 的使用者）

決策：
- 不動「Things chezmoi deliberately won't migrate」表格 line 104 的 SSH 條目 — 那邊講的是「不會 migrate 什麼」，本次新增的是「跑 clone-all.sh 之前要先有什麼」，兩個觀點互補不衝突
- 沒有把 SSH 設定拉到 chezmoi quick-start 最上面 — chezmoi 本身用 HTTPS 拉 gs-claude-config，不需要 SSH；只有後續的 `clone-all.sh` 才需要

### M3 — 收尾 → this commit

無額外變動，只把本進度檔的進度日誌補完。

## 後續建議（不在本次 scope）

1. **`repos.txt.example` 加註解**：建議在 example 檔頂部寫一行 `# If you use git@github.com:... URLs, set up SSH key first (see README)`，雙重保險。
2. **`clone-all.sh` 自動偵測**：可在腳本開頭跑 `ssh -T -o BatchMode=yes -o ConnectTimeout=5 git@github.com 2>&1 | grep -q "successfully authenticated"`，失敗就提示「SSH not set up, see README」再 exit。等下次有人再次踩到時再加。
