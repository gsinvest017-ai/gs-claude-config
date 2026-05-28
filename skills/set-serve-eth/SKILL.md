---
name: set-serve-eth
description: 把當前 repo server 啟動時預設綁定的 IP 改成 LAN ethernet IP（自動偵測或 --ip 指定，例如 192.168.0.146），同時在防火牆（Windows Defender Firewall 或 Linux ufw / firewalld）開放該 server 預設使用的 port，讓內網其他使用者可以 access。偵測常見 server entry pattern（Flask app.run、uvicorn、Streamlit、Express app.listen、Go ListenAndServe、docker-compose ports、.env HOST/PORT、run.sh / run.ps1、.streamlit/config.toml），firewall 預設只開放 LocalSubnet（LAN-only）避免暴露到公網。當使用者輸入 /set-serve-eth、說「讓內網其他人連我的 dev server」、「把 server bind 到 LAN IP」、「開防火牆讓同事連我這台」、「expose to LAN」、「讓區網看得到這個 server」時啟動。預設 dry-run，需 --apply 才改檔 / 加防火牆規則，支援 --revert 還原。
---

# /set-serve-eth — 把 server bind 到 LAN IP + 開防火牆給內網

當使用者觸發時，把**當前 repo** server 啟動的綁定 IP 改成 ethernet（LAN）IP，並在系統防火牆開放該 server 預設使用的 port，讓內網其他機器可以連得到。全程繁體中文回報。

**預設 dry-run**（只印計畫 + 偵測結果）；需 `--apply` 才改檔與加防火牆規則。`--revert` 可還原成原本設定。

## 0. 解析使用者參數

從 `$ARGUMENTS` 解析：

| 參數 | 預設 | 說明 |
|------|------|------|
| `--ip <addr>` | `auto`（第一個非虛擬 ethernet IPv4） | LAN IP，例如 `192.168.0.146` |
| `--port <n>` | auto（從 server 設定偵測） | server 監聽的 port |
| `--script <path>` | auto（偵測 entry / 啟動腳本） | server 啟動腳本或設定檔 |
| `--bind-mode <specific\|all-interfaces>` | `specific` | `specific`=只 bind 到該 IP；`all-interfaces`=改成 `0.0.0.0` 監聽所有介面 |
| `--firewall <auto\|win\|linux\|none>` | `auto` | 要設定哪個系統防火牆；`none`=不動防火牆 |
| `--scope <lan-only\|any>` | `lan-only` | firewall 規則的 remote address 範圍（LAN-only=LocalSubnet；any=公開） |
| `--rule-name <n>` | `<repo>-<port>-lan` | firewall 規則名稱 |
| `--profile <name>` | 無 | 限定只動某個 profile 的設定（如 `.env.development`） |
| `--apply` | 否 | 真的改檔與加防火牆規則 |
| `--revert` | 否 | 還原：bind IP 改回 backup、刪掉本 skill 加的 firewall 規則 |
| `--force` | 否 | 允許 bind 到公網 IP（預設拒絕） |

範例 args：
- `""` → auto 偵測、dry-run，印出會做什麼
- `"--apply"` → 套用：改 bind + 開防火牆（LAN-only）
- `"--ip 192.168.0.146 --port 8766 --apply"` → 明確指定 IP / port
- `"--bind-mode all-interfaces --apply"` → 改成 `0.0.0.0` 監聽所有介面
- `"--revert"` → 還原所有變更

## 1. 前置檢查

- 確認在 git repo 內（或 `--script` 已指定）
- 偵測 OS（決定走 Windows / Linux 防火牆路線）
- 偵測權限（Windows: 是否 Administrator；Linux: 是否可 sudo）—— 若無權限改防火牆，會把指令印出讓使用者手動執行

## 2. 偵測 ethernet IP（`--ip auto` 時）

**Windows（PowerShell）**：
```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object {
    $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and
    $_.InterfaceAlias -notmatch '(Loopback|vEthernet|VMware|VirtualBox|WSL|Bluetooth|Tunnel)' -and
    $_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'Manual'
  } | Sort-Object -Property InterfaceMetric |
  Select-Object -First 1 -ExpandProperty IPAddress
```

**Linux**：
```bash
ip -4 -o addr show scope global | \
  awk '{print $2, $4}' | \
  grep -Ev '^(lo|docker|virbr|veth|br-|tun|tap)' | \
  awk -F/ '{print $1}' | awk '{print $2}' | head -n1
```

**驗證**：必須在私網範圍（`10.0.0.0/8` / `172.16.0.0/12` / `192.168.0.0/16` / `100.64.0.0/10` CGNAT）。否則拒絕，除非 `--force`。

候選多個 → 列出，使用者可 `--ip <addr>` 明指。

## 3. 偵測 server entry 與當前 bind / port

掃描下列 pattern（命中即記錄檔案 + 行號 + 當前值）：

| 載體 | 偵測 pattern |
|------|--------------|
| **Flask** | `app.run(host=<x>, port=<y>)`、`flask --host <x> --port <y>` |
| **FastAPI / Uvicorn** | `uvicorn.run("<m>:app", host=<x>, port=<y>)`、`uvicorn ... --host <x> --port <y>` |
| **Streamlit** | `.streamlit/config.toml` `[server] address` / `port`；CLI `streamlit run --server.address=<x> --server.port=<y>` |
| **Gunicorn** | `gunicorn -b <x>:<y>` |
| **Express / Node** | `app.listen(<port>, <host>)`、`server.listen(<port>, '<host>')` |
| **Vite / Next** | `vite --host <x> --port <y>`、`next dev --hostname <x> --port <y>` |
| **Go** | `http.ListenAndServe("<x>:<y>", ...)` |
| **Rust** | `axum::serve`、`Server::bind("<x>:<y>")` |
| **docker-compose** | `services.<svc>.ports: ["<host>:<container>"]` |
| **環境變數** | `.env` / `.env.*` 內 `HOST=` / `BIND=` / `BIND_ADDR=` / `PORT=` |
| **launcher** | `run.sh` / `run.ps1` / `package.json` `scripts.start|dev` / `Makefile` `run:` |

多個候選 → 列出，優先選擇被 `run.sh` / `run.ps1` / README quick-start 引用的那個。

**autogo 專案特記**：`web/app.py`（FastAPI/Flask）+ `web/dashboard.html`；常用 port `8766`（從 memory）。若偵測到此結構，直接以該 entry 為目標。

## 4. 計畫 / dry-run 輸出

印計畫表：

```
Repo: autogo
OS: Windows 11 (Administrator: yes)
Ethernet IP (auto): 192.168.0.146  (Interface: Ethernet, Metric: 25)
Server entry: web/app.py:142  (FastAPI / uvicorn)
Current bind: host="127.0.0.1"  port=8766

計畫變動（--apply 才會做）：
  [1] 改 web/app.py:142  host="127.0.0.1" → host="192.168.0.146"
  [2] 新增 Windows Firewall 規則
        Name:    autogo-8766-lan
        Dir:     Inbound  TCP  port 8766
        Action:  Allow
        Profile: Private,Domain
        Remote:  LocalSubnet
  [3] 寫 backup：.claude/local/set-serve-eth.json
        記錄原 host 值 + 規則名，供 --revert 用

Share URL（apply 後）: http://192.168.0.146:8766
```

無 `--apply` → 結束，回報「Dry-run 完成；確認後加 `--apply` 重跑」。

## 5. 套用變更（僅當 `--apply`）

### A. 改 bind IP

優先順序（侵入度由低到高）：
1. **CLI flag in launcher**（最不侵入）—— 改 `run.sh` / `run.ps1` 內的 `--host` 旗標
2. **環境變數 .env**—— 加 / 改 `HOST=192.168.0.146`（若 server 已 honor env var）
3. **設定檔**—— `.streamlit/config.toml`、`uvicorn` 設定
4. **直接改原始碼**（最後手段）—— 改 `app.run(host=...)` 等寫死的值

**`--bind-mode all-interfaces`** → 把 host 改成 `0.0.0.0` 而非具體 IP（更簡單，可承受 DHCP 換 IP）。

**Backup**：改動前把原值寫進 `.claude/local/set-serve-eth.json`：
```json
{
  "date": "2026-05-28",
  "changes": [
    { "file": "web/app.py", "line": 142, "field": "host", "old": "127.0.0.1", "new": "192.168.0.146" }
  ],
  "firewall_rules": ["autogo-8766-lan"]
}
```
（`.claude/local/` 已在 `.gitignore` 或新加進去；不 commit）

### B. 開防火牆

**Windows（需 Admin）**：
```powershell
$ruleName = "autogo-8766-lan"
$port = 8766
if (-not (Get-NetFirewallRule -DisplayName $ruleName -EA SilentlyContinue)) {
  New-NetFirewallRule -DisplayName $ruleName `
    -Direction Inbound -Protocol TCP -LocalPort $port `
    -Action Allow -Profile Private,Domain `
    -RemoteAddress LocalSubnet `
    -Description "Opened by /set-serve-eth for repo autogo"
}
```

`--scope any` → 拿掉 `-RemoteAddress LocalSubnet`（**警告：開到任何 remote，含網路上任何來源**）。
`--profile` 預設用 `Private,Domain`（**不**碰 Public profile，避免在咖啡店誤開）。

**Windows 非 Admin**：印出上面那串指令並提示「請以系統管理員身分執行；或重跑 `/set-serve-eth --apply` 在 elevated terminal」，不嘗試自動 elevate。

**Linux (ufw)**：
```bash
sudo ufw allow from 192.168.0.0/16 to any port 8766 proto tcp  # lan-only
# 或 --scope any:
sudo ufw allow 8766/tcp
```

**Linux (firewalld)**：
```bash
sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=192.168.0.0/16 port port=8766 protocol=tcp accept"
sudo firewall-cmd --reload
```

**Linux (iptables fallback)**：用 `-s 192.168.0.0/16` + `-p tcp --dport 8766 -j ACCEPT`，並提示這不會持久化。

### C. 寫 backup metadata

`.claude/local/set-serve-eth.json` 已寫在 §5.A。

## 6. 驗證

- 讀回改後的檔，確認 host 已是目標 IP
- 防火牆規則存在：
  - Windows: `Get-NetFirewallRule -DisplayName "<name>"` 印出規則
  - Linux: `sudo ufw status numbered` / `sudo firewall-cmd --list-all`
- 連通性（不啟動長時服務）：
  - 同機端：`Test-NetConnection -ComputerName 192.168.0.146 -Port 8766`（Windows）/ `nc -zv 192.168.0.146 8766`（Linux）
  - **跨機驗證需使用者在另一台機器手動跑**，print 一行：「請從同網段另一台機器：`curl http://192.168.0.146:8766/`」
- 印分享 URL：`http://192.168.0.146:8766`

## 7. `--revert` 模式

讀 `.claude/local/set-serve-eth.json`：
1. 逐 file/line 把 host 還原成 `old` 值
2. `Remove-NetFirewallRule -DisplayName <each rule>` / `sudo ufw delete allow ...`
3. 刪 backup metadata
4. 回報還原項目；找不到 backup → 拒絕並提示手動處理

## 8. 完成回報

3~5 行：
1. 改了哪個檔的 bind（before → after）
2. 加了什麼 firewall 規則（名稱 / port / scope）
3. 分享 URL（含 ethernet IP + port）
4. 驗證結果（本機端口可達 / 規則已存在）
5. 後續：`--revert` 怎麼撤；DHCP 環境提示 IP 可能變動

## 不要做的事

- ❌ 沒 `--apply` 就改檔 / 加 firewall 規則
- ❌ Bind 到公網 IP（非私網範圍）—— 拒絕，除非 `--force`
- ❌ Firewall 預設開到 `Any` remote —— 預設 `LocalSubnet`
- ❌ 動 Windows **Public** profile —— 預設只動 Private + Domain
- ❌ 寫 secrets 進 `.env`；只動 HOST / PORT / BIND_ADDR
- ❌ commit `.env` 或 `.claude/local/set-serve-eth.json`（兩者都應該在 `.gitignore`）
- ❌ 自動 UAC elevate；若非 admin，把指令印出讓使用者跑
- ❌ 改 production profile（除非 `--profile prod` 並明示 `--apply`）

## 邊界情況

- **多張網卡**（Wi-Fi + Ethernet + VPN + virtual）→ 偵測後列出全部，預設選第一張非虛擬 ethernet；使用者可 `--ip` 明指
- **DHCP 環境 IP 會變** → 提示「下次 IP 變了要重跑 `/set-serve-eth`」；或改用 `--bind-mode all-interfaces`（bind `0.0.0.0`），對 IP 變動免疫
- **無偵測到 server entry** → 提示用 `--script <path>` 指定
- **port 已被別的 process 佔用** → 偵測但不解，回報衝突
- **同名 firewall 規則已存在** → 不重複建，回報已存在
- **docker container 內的 server** → host bind 應為 `0.0.0.0`（container 內），firewall 開在 host；提示用 `--bind-mode all-interfaces`
- **HTTPS server cert CN 寫 localhost** → 換 IP 後瀏覽器會擋；提示重發 cert 或 dev 用 HTTP
- **公司 group policy 鎖防火牆** → New-NetFirewallRule 會失敗；回報並印手動工作流

## 與其他 skill 協作

- **`/one-button-launch`**：本 skill 改動的 launcher 就是它產生的；通常一起用
- **`/platform-compatible`**：firewall / host 偵測天生跨平台，可順手檢查 cross-OS 路徑
- **`/copy-commits-button`**：dashboard 對外開放後，連到 LAN URL 就可以給其他人複製 commits
- **`/run`** / **`/verify`**：套用後跑起 server 並從另一台機器測連通

## 全域註冊（apply globally）

本 skill 安裝在 user-scope：`~/.claude/skills/set-serve-eth/SKILL.md` → 對**所有**專案可用。在此環境中 `~/.claude` 是 chezmoi 管理的 `gs-claude-config` symlink，新增此檔即等於全域註冊；新 session 啟動時載入。
