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
