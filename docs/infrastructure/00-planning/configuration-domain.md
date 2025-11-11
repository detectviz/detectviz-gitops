# 域名映射配置

本文件說明 DetectViz 集群的域名映射配置，作為網路規劃和 DNS 配置的參考。

## 目錄

- [DNS 架構](#dns-架構)
  - [服務範圍](#服務範圍)
  - [網路範圍](#網路範圍)
- [網路架構](#網路架構)
  - [IP 分配總覽](#ip-分配總覽)
- [內部域名 (.detectviz.internal)](#內部域名-detectvizinternal)
  - [基礎設施域名](#基礎設施域名)
  - [Kubernetes 集群域名](#kubernetes-集群域名)
- [應用服務域名](#應用服務域名)
  - [主要服務](#主要服務)
  - [觀測與應用服務](#觀測與應用服務)
- [網路服務端口](#網路服務端口)
  - [基礎設施服務](#基礎設施服務)
  - [應用服務](#應用服務)
- [DNS 伺服器設置 (proxmox)](#dns-伺服器設置-proxmox)
  - [1. 安裝 dnsmasq](#1-安裝-dnsmasq)
  - [2. 備份 dnsmasq 配置 (proxmox)](#2-備份-dnsmasq-配置-proxmox)
  - [3. 配置 dnsmasq](#3-配置-dnsmasq)
  - [4. 啟動服務](#4-啟動服務)
- [集群節點 DNS 配置](#集群節點-dns-配置)
  - [方法一：手動更新 resolv.conf](#方法一手動更新-resolvconf-)
  - [方法二：使用 Ansible 自動化配置](#方法二使用-ansible-自動化配置)
- [集群 VM 的 /etc/hosts 配置](#集群-vm-的-etchosts-配置)
  - [集群節點 /etc/hosts（Terraform 自動生成）](#集群節點-etchoststerraform-自動生成)
  - [本機開發 /etc/hosts（可選）](#本機開發-etchosts可選)
- [域名解析測試](#域名解析測試)
  - [基本測試命令](#基本測試命令)
  - [批量測試](#批量測試)

---

## DNS 架構

> [!TIP]
> 未來若啟用 VLAN 隔離，可於 vmbr1 上設定 bridge-ports enp5s0.100，並於 Switch 側設對應 VLAN。

### 服務範圍
- **內部域名**：`detectviz.internal` 區域
- **外部域名**：轉發到上游 DNS (8.8.8.8, 1.1.1.1)
- **服務對象**：Proxmox 主機、所有 VM、集群節點

### 網路範圍
- **管理網路**：192.168.0.0/24 (vmbr0 - 外部網路)
- **集群網路**：10.0.0.0/24 (vmbr1 - Kubernetes 內部網路)
- **Pod 網路**：10.244.0.0/16 (Pod CIDR)
- **服務網路**：10.96.0.0/12 (Service CIDR)

## 網路架構

### IP 分配總覽
| 角色 | 主機名稱 | 外部網路 IP | 內部網路 IP | 用途 |
|------|----------|-------------|-------------|------|
| Proxmox | proxmox | 192.168.0.2 | 10.0.0.2 | 虛擬化平台管理 |
| IPMI | ipmi | 192.168.0.4 | - | 硬體管理介面 |
| K8s VIP | k8s-api | 192.168.0.10 | - | Kubernetes API 負載均衡 |
| Master-1 | master-1 | 192.168.0.11 | 10.0.0.11 | 控制平面節點 #1 |
| Master-2 | master-2 | 192.168.0.12 | 10.0.0.12 | 控制平面節點 #2 |
| Master-3 | master-3 | 192.168.0.13 | 10.0.0.13 | 控制平面節點 #3 |
| Worker | app-worker | 192.168.0.14 | 10.0.0.14 | 應用工作節點 |

## 內部域名 (.detectviz.internal)

### 基礎設施域名
| 域名 | IP 位址 | 說明 |
|------|---------|------|
| `proxmox.detectviz.internal` | 192.168.0.2 | Proxmox Web UI |
| `ipmi.detectviz.internal` | 192.168.0.4 | IPMI 管理介面 |

### Kubernetes 集群域名
| 域名 | IP 位址 | 說明 |
|------|---------|------|
| `k8s-api.detectviz.internal` | 192.168.0.10 | Kubernetes API Server VIP |
| `master-1.detectviz.internal` | 192.168.0.11 | Master 節點 #1 |
| `master-2.detectviz.internal` | 192.168.0.12 | Master 節點 #2 |
| `master-3.detectviz.internal` | 192.168.0.13 | Master 節點 #3 |
| `app-worker.detectviz.internal` | 192.168.0.14 | Application Worker 節點 |

## 應用服務域名

> [!TIP]
> 所有應用 UI (ArgoCD / Grafana / Prometheus / Loki / Tempo / PgAdmin) 
> 均透過 Kubernetes Ingress 暴露，並使用 VIP 192.168.0.10。

### 主要服務
| 服務 | 域名 | IP 位址 | 說明 |
|------|------|---------|------|
| ArgoCD | `argocd.detectviz.internal` | 192.168.0.10 | GitOps 控制面板 |

### 觀測與應用服務
| 服務 | 域名 | IP 位址 | 說明 |
|------|------|---------|------|
| Grafana | `grafana.detectviz.internal` | 192.168.0.10 | 監控儀表板與整合可視化介面 |
| Prometheus | `prometheus.detectviz.internal` | 192.168.0.10 | 指標收集與查詢介面 |
| Loki | `loki.detectviz.internal` | 192.168.0.10 | 日誌查詢介面 |
| Tempo | `tempo.detectviz.internal` | 192.168.0.10 | 分散式追蹤查詢介面 |
| PgAdmin | `pgadmin.detectviz.internal` | 192.168.0.10 | PostgreSQL 資料庫管理介面 |

## 網路服務端口

### 基礎設施服務
| 服務 | 端口 | 協議 | 訪問方式 |
|------|------|------|----------|
| Proxmox Web UI | 8006 | HTTPS | https://proxmox.detectviz.internal:8006 |
| IPMI Web UI | 443 | HTTPS | https://ipmi.detectviz.internal |
| SSH | 22 | TCP | ssh user@hostname.detectviz.internal |
| Kubernetes API | 6443 | HTTPS | https://k8s-api.detectviz.internal:6443 |

### 應用服務
| 服務 | 端口 | 協議 | 說明 |
|------|------|------|------|
| ArgoCD UI | 80/443 | HTTP/HTTPS | GitOps 管理介面 (通過 Ingress) |
| Grafana | 3000 | HTTP | 監控儀表板 |
| Prometheus | 9090 | HTTP | 指標收集 |
| Loki | 3100 | HTTP | 日誌查詢服務 |
| Tempo | 3200 | HTTP | 分散式追蹤服務 |
| PgAdmin | 5050 | HTTP | PostgreSQL 管理介面（預設 80，可覆寫為 5050）|

## DNS 伺服器設置 (proxmox)

內部網路 (10.0.0.0/24) 僅供 Kubernetes 節點間通訊，dnsmasq 不直接監聽該橋接介面。

### 1. 安裝 dnsmasq
```bash
apt update
apt install dnsmasq -y
```

### 2. 備份 dnsmasq 配置 (proxmox)
```bash
cp /etc/dnsmasq.d/detectviz.conf /etc/dnsmasq.d/detectviz.conf.backup
```

### 3. 配置 dnsmasq

```ini
# /etc/dnsmasq.d/detectviz.conf
domain=detectviz.internal
expand-hosts
local=/detectviz.internal/

# 主機記錄 (外部網路)
address=/proxmox.detectviz.internal/192.168.0.2
address=/ipmi.detectviz.internal/192.168.0.4
address=/k8s-api.detectviz.internal/192.168.0.10
address=/master-1.detectviz.internal/192.168.0.11
address=/master-2.detectviz.internal/192.168.0.12
address=/master-3.detectviz.internal/192.168.0.13
address=/app-worker.detectviz.internal/192.168.0.14

# 內部集群網路域名
local=/cluster.internal/

# 內部網路記錄 (Kubernetes 節點間通訊)
address=/master-1.cluster.internal/10.0.0.11
address=/master-2.cluster.internal/10.0.0.12
address=/master-3.cluster.internal/10.0.0.13
address=/app-worker.cluster.internal/10.0.0.14

# 應用服務
address=/argocd.detectviz.internal/192.168.0.10

# 觀測與應用服務
address=/grafana.detectviz.internal/192.168.0.10
address=/prometheus.detectviz.internal/192.168.0.10
address=/loki.detectviz.internal/192.168.0.10
address=/tempo.detectviz.internal/192.168.0.10
address=/pgadmin.detectviz.internal/192.168.0.10

# 上游 DNS
server=8.8.8.8
server=1.1.1.1

listen-address=127.0.0.1,192.168.0.2
bind-interfaces
```

### 4. 啟動服務
```bash
systemctl enable --now dnsmasq
systemctl restart dnsmasq
systemctl status dnsmasq
```

## 集群節點 DNS 配置

### 方法一：手動更新 resolv.conf 

> 若系統使用 systemd-resolved，請在 /etc/systemd/resolved.conf 中設置：
> [Resolve]
> DNS=192.168.0.2
> Domains=detectviz.internal
> 並執行 systemctl restart systemd-resolved

在所有集群節點上配置 DNS：

```bash
# 備份原始配置
cp /etc/resolv.conf /etc/resolv.conf.backup

# 編輯 resolv.conf
vi /etc/resolv.conf

# 配置內容
nameserver 192.168.0.2
search detectviz.internal
```

### 方法二：使用 Ansible 自動化配置
```yaml
---
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

## 集群 VM 的 /etc/hosts 配置

### 集群節點 /etc/hosts（Terraform 自動生成）
```bash
# Detectviz Platform Hosts (Terraform 自動生成 VM 的 /etc/hosts)
# 外部網路 (vmbr0 - 192.168.0.0/24)
192.168.0.11 master-1.detectviz.internal master-1
192.168.0.12 master-2.detectviz.internal master-2
192.168.0.13 master-3.detectviz.internal master-3
192.168.0.14 app-worker.detectviz.internal app-worker
192.168.0.10 k8s-api.detectviz.internal k8s-api

# 內部集群網路 (vmbr1 - 10.0.0.0/24 - Kubernetes 節點間通訊)
10.0.0.11 master-1.cluster.internal master-1-cluster
10.0.0.12 master-2.cluster.internal master-2-cluster
10.0.0.13 master-3.cluster.internal master-3-cluster
10.0.0.14 app-worker.cluster.internal app-worker-cluster
```

### 本機 /etc/hosts（可選）
如果您需要在個人電腦上訪問集群服務（開發測試時），請在本地 `/etc/hosts` 中添加：

> [!NOTE]
> 生產環境請使用 Cloudflare DNS 或其他外部 DNS 配置，而非修改本機 hosts。
```bash
# 管理
192.168.0.2 proxmox.detectviz.internal
192.168.0.4 ipmi.detectviz.internal

# Detectviz 應用服務 (Kubernetes VIP)
192.168.0.10 k8s-api.detectviz.internal argocd.detectviz.internal grafana.detectviz.internal prometheus.detectviz.internal loki.detectviz.internal tempo.detectviz.internal pgadmin.detectviz.internal
```

## 域名解析測試

執行以下測試即可確認所有設定有效：

```bash
# DNS 外部域名測試
dig grafana.detectviz.internal @192.168.0.2 +short
# 預期: 192.168.0.10

# DNS 集群內部域名測試
dig master-1.cluster.internal @192.168.0.2 +short
# 預期: 10.0.0.11

# 外部解析測試
dig google.com @192.168.0.2 +short
# 預期: Google IP 位址

# 確認 VM hosts 生效
ssh ubuntu@192.168.0.11 'getent hosts app-worker.detectviz.internal'
# 預期: 192.168.0.14

ssh ubuntu@192.168.0.11 'getent hosts app-worker.cluster.internal'
# 預期: 10.0.0.14
```

預期結果：
- 正確返回對應 IP。
- 外部轉發正常。
- 無重複定義、無 NXDOMAIN。
