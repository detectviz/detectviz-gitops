# Tailscale 整合設定指南

### 目的
在外部網路（公司、手機熱點、其他地點）安全地連回家中 LAN，能直接存取 Proxmox、VM、NAS、SSH 等內部設備，**不需暴露公網 Port，也不修改防火牆規則**。  
本指南描述如何在 Detectviz 基礎架構中整合 Tailscale 作為安全遠端管理通道。

---

## 架構概要

| 組件 | 角色 | 網段 |
|------|------|------|
| Proxmox Host | Tailscale Subnet Router | 192.168.0.0/24 |
| Detectviz Cluster | Kubernetes 叢集 (vmbr1, 10.0.0.0/24) | 內部專用 |
| 外部裝置 | Mac / Notebook / 手機 | 透過 Tailscale VPN 存取 |

---

## 1. 在 Proxmox 安裝 Tailscale

在宿主機 Shell 執行：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

若出現 apt 401 錯誤，請確認來源：

```bash
nano /etc/apt/sources.list.d/pve-no-subscription.list
```

加入：

```
deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription
```

更新套件：

```bash
apt update
```

---

## 2. 登入並啟用服務

```bash
tailscale up
```

系統將顯示登入連結，例如：

```
https://login.tailscale.com/a/xxxxxx
```

登入後確認連線狀態：

```bash
tailscale status
```

---

## 3. 啟用 Subnet Router

允許外部設備透過 Tailscale 存取內部 LAN：
```bash
tailscale up --advertise-routes=192.168.0.0/24 --accept-dns=false
```

> [!NOTE]
> - 僅廣播 **192.168.0.0/24** 管理網段。
> - **不要** 廣播 10.0.0.0/24（K8s 內部網），以避免與 Overlay 網段衝突。
> - `--accept-dns=false` 會保留本機 `dnsmasq` 的解析設定。

---

## 4. 啟用路由於 Tailscale Admin Console

登入 [https://login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines)

- 找到 Proxmox Host（例如 `detectviz-proxmox`）
- 點擊 **Edit route settings**
- 勾選：
  - Subnet routes → `192.168.0.0/24`
  - Exit node → *(可選，不建議啟用)*

儲存設定後，該節點即成為子網路路由。

---

## 5. 外部裝置設定

在外部裝置安裝 Tailscale（macOS、Windows、Linux、iOS、Android 皆可）：
```bash
tailscale up
```

登入與 Proxmox 相同帳號後，應能直接連線至：
- `192.168.0.2` → Proxmox Web UI  
- `192.168.0.11` → K8s Master-1  
- `192.168.0.10` → ArgoCD / Grafana / Prometheus 等服務

---

## 6. 驗證連線

```bash
tailscale status
```

若顯示：
```
detectviz-proxmox active; direct <public-ip>:41641
```
表示直連成功。  
若出現 `relay`，則為中繼路由（延遲較高，可稍後調整）。

---

## 7. 安全性注意事項

| 項目 | 建議 |
|------|------|
| DNS | 使用 `--accept-dns=false`，保留內部解析 |
| rp_filter | 設為 `2`（寬鬆模式）確保非對稱路由封包不被丟棄 |
| Advertise routes | 僅限 192.168.0.0/24 |
| 監控 | 可使用 `tailscale status --json` 導出至 Grafana |
| 防火牆 | 確保 UDP 41641、3478 未被封鎖 |

---

## 8. 驗證命令

```bash
# 檢查路由是否註冊成功
tailscale netcheck
tailscale ip -4

# 測試連線
ping 192.168.0.11
ssh ubuntu@192.168.0.11
```

> 採用 Tailscale 作為 Detectviz 基礎架構的安全遠端接入方案，可大幅簡化防火牆與 VPN 管理，並與現有雙橋接網路設計（vmbr0 / vmbr1）完全相容。
