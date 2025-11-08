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

## 網域對應

| 網域                            | 對應 IP         | 用途               |
| ----------------------------- | ------------- | -------------------- |
| `ipmi.detectviz.internal`     | 192.168.0.104 | IPMI 管理介面         |
| `proxmox.detectviz.internal`  | 192.168.0.2   | Proxmox Web          |
| `k8s-api.detectviz.internal`  | 192.168.0.10  | K8s API VIP          |
| `master-1.detectviz.internal` | 192.168.0.11  | 控制平面 #1            |
| `master-2.detectviz.internal` | 192.168.0.12  | 控制平面 #2            |
| `master-3.detectviz.internal` | 192.168.0.13  | 控制平面 #3            |
| `app.detectviz.internal`      | 192.168.0.14  | Data/Monitoring Node |
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
address=/app.detectviz.internal/192.168.0.14

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
dig app.detectviz.internal @192.168.0.2
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
