# Network 管理

## 域名
- `detectviz.com` 尚未設定
- `argocd.detectviz.local` - ArgoCD UI 訪問域名，指向 NGINX Ingress LoadBalancer (192.168.0.11)

## 靜態 IP 配置
- **192.168.0.2**
  - 用途：Proxmox 管理介面 (web UI)
  - 範例：[https://192.168.0.2:8006](https://192.168.0.2:8006)

- **192.168.0.104**
  - 用途：KVM / IPMI 管理介面 (固定)
  - 範例：[https://192.168.0.104](https://192.168.0.104)

## Proxmox Bridge 對應

| Bridge  | IP / 角色          | 物理介面    | 備註                         |
| ------- | ------------------ | ----------- | ---------------------------- |
| `vmbr0` | 192.168.0.2 / 管理 | `enp4s0`    | 作為主要管理橋接、關閉 STP/FWD |
| —       | —                  | `enp5s0`    | 預留（未綁定至橋接）          |
| —       | —                  | `enx36fe0bfce7d0` | 預留（未綁定至橋接）          |

- Terraform `proxmox_bridge` 變數與樣板 (`terraform/variables.tf`, `terraform.tfvars.example`) 已預設為 `vmbr0`，與此對應表一致。
- 若調整物理介面映射，需同步更新 Terraform `proxmox_bridge` 參數與任何 Ansible/Argo Workflow 中引用的橋接名稱。

## 網路優化設置

### 解決 KVM/Bridge/Tap 網路封包遺失問題

#### rp_filter 設定
解決 KVM/Bridge/Tap 網路封包遺失問題，將 `rp_filter` 設為 `1` (Loose Mode) 而不是 `0` (Off)，這會同時覆蓋 `all` 和 `default` 的設定。

##### 步驟 1：建立新的設定檔

請在 Proxmox Host 的 shell 中執行以下指令。我們將建立一個名為 `98-pve-networking.conf` 的檔案：

```bash
cat << EOF | sudo tee /etc/sysctl.d/98-pve-networking.conf
# 修正 Proxmox KVM/Bridge/Tap 網路封包遺失 (ICMP Reply)
# 將 rp_filter 設為 1 (Loose Mode) 以允許橋接的非對稱路由
# 這是解決 ICMP 封包被 tap 介面丟棄的關鍵
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
```

##### 步驟 2：立即載入設定

建立檔案後，你需要讓核心立即重新讀取所有 `/etc/sysctl.d/` 下的設定：

```bash
sudo sysctl --system
```

> **說明：** 這個指令會重新載入所有 `.conf` 檔案，包含你剛剛建立的 `98-pve-networking.conf`。

##### 步驟 3：驗證

現在，再次檢查 `all.rp_filter` 的值：

```bash
sysctl net.ipv4.conf.all.rp_filter
```

**預期輸出：**
`net.ipv4.conf.all.rp_filter = 1`

##### 總結

完成上述步驟後，`all.rp_filter` 就會被正確設定為 `1` (寬鬆模式)。這將使 `tap111i0` 介面的**有效值**變為 `max(1, 0) = 1`，封包就不會再被丟棄了。

## 網域對應

| 網域                            | 對應 IP         | 用途               |
| ----------------------------- | ------------- | -------------------- |
| `ipmi.detectviz.internal`     | 192.168.0.104 | IPMI 管理介面         |
| `proxmox.detectviz.internal`  | 192.168.0.2   | Proxmox Web          |
| `k8s-api.detectviz.internal`  | 192.168.0.10  | K8s API VIP          |
| `master-1.detectviz.internal` | 192.168.0.11  | 控制平面 #1            |
| `master-2.detectviz.internal` | 192.168.0.12  | 控制平面 #2            |
| `master-3.detectviz.internal` | 192.168.0.13  | 控制平面 #3            |
| `app-worker.detectviz.internal` | 192.168.0.14  | Application Node     |
| `argocd.detectviz.local`      | 192.168.0.10  | ArgoCD UI            |

## DNS 伺服器設置

### 安裝 dnsmasq 並設定內部 DNS 區域

在 Proxmox 主機（例如 192.168.0.2）上，架設輕量級 DNS 伺服器以供 Detectviz 叢集使用。

#### 1. 安裝
```bash
apt update
apt install dnsmasq -y
```

#### 2. 建立設定檔
編輯 `/etc/dnsmasq.d/detectviz.conf`：

```ini
# Detectviz internal DNS zone
domain=detectviz.internal
expand-hosts
local=/detectviz.internal/

# 主機記錄
address=/proxmox.detectviz.internal/192.168.0.2
address=/k8s-api.detectviz.internal/192.168.0.10
address=/master-1.detectviz.internal/192.168.0.11
address=/master-2.detectviz.internal/192.168.0.12
address=/master-3.detectviz.internal/192.168.0.13
address=/app-worker.detectviz.internal/192.168.0.14

# 應用服務域名
address=/argocd.detectviz.local/192.168.0.10      # ArgoCD UI (指向運行 NGINX 的節點)

# 上游 DNS
server=8.8.8.8
server=1.1.1.1

# 開放 LAN 範圍查詢
listen-address=127.0.0.1,192.168.0.2
bind-interfaces
```

#### 3. 啟動並設為開機自動啟用
```bash
systemctl enable --now dnsmasq
systemctl restart dnsmasq
systemctl status dnsmasq
```

#### 4. 測試解析
```bash
# 測試內部域名
dig master-1.detectviz.internal @127.0.0.1
dig app-worker.detectviz.internal @192.168.0.2
dig argocd.detectviz.local @192.168.0.2

# 測試外部域名解析
dig google.com @192.168.0.2
```

---

### 讓叢集節點使用 Proxmox DNS

修改各節點 `/etc/resolv.conf`：
```bash
nameserver 192.168.0.2
search detectviz.internal
```

或以 Ansible Playbook 自動化設定：
```yaml
- name: Configure internal DNS for Detectviz
  hosts: all
  become: yes
  tasks:
    - name: Update resolv.conf
      copy:
        dest: /etc/resolv.conf
        content: |
          nameserver 192.168.0.2
          search detectviz.internal
```

---

### 驗證

確認節點皆可解析：
```bash
# 測試基礎設施域名
ping k8s-api.detectviz.internal
ping master-1.detectviz.internal

# 測試應用服務域名
ping argocd.detectviz.local
```

若解析正常，即代表 Proxmox DNS 伺服器運作成功。

## 重點原則
- KVM (IPMI) 與 Proxmox 管理層必須分離
- KVM 是硬體控制層（out-of-band）。
- Proxmox 與 K8s 屬於作業層（in-band）。
- 分離後可防止誤操作與安全風隟。
- IP 不可與叢集或 Pod 網段重疊。
