# DetectViz GitOps 部署指南

**基於架構**: `README.md` (4 VM 混合負載模型 + 雙網路架構)

本文件提供完整的部署流程，從 Proxmox 網路配置到 Kubernetes 集群啟動的所有步驟。

---

## 部署流程概覽

```
┌─────────────────────────────────────────────────────────────────────┐
│                          前置作業 (一次性)                           │
├─────────────────────────────────────────────────────────────────────┤
│ 1. Proxmox 雙網路配置 (vmbr0 + vmbr1)                               │
│ 2. DNS 伺服器配置 (dnsmasq)                                         │
│ 3. VM 模板準備 (Ubuntu 22.04)                                       │
│ 4. SSH 金鑰準備                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 1: Terraform 基礎設施                      │
├─────────────────────────────────────────────────────────────────────┤
│ • 建立 4 台 VM (3 master + 1 worker)                                │
│ • 配置雙網路 (192.168.0.0/24 + 10.0.0.0/24)                         │
│ • 配置雙磁碟架構 (worker: 100GB system + 250GB data)                │
│ • 生成 Ansible inventory                                            │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 2: 網路配置驗證                            │
├─────────────────────────────────────────────────────────────────────┤
│ • 驗證雙網路連通性                                                   │
│ • 驗證 DNS 解析 (detectviz.internal + cluster.internal)             │
│ • 驗證 MTU 設定                                                      │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                   Phase 3: Ansible 自動化部署                        │
├─────────────────────────────────────────────────────────────────────┤
│ Phase 3.1: Common Role (系統初始化)                                 │
│ Phase 3.2: Network Role (雙網路配置)                                │
│ Phase 3.3: Master Role (Kubernetes 控制平面 + HA)                   │
│ Phase 3.4: Worker Role (加入集群 + LVM 自動配置)                    │
│ Phase 3.5: Node Labels (工作負載標籤)                               │
│ Phase 3.6: ArgoCD 部署 + Git SSH 認證自動化 🤖                      │
│ Phase 3.7: 最終驗證                                                  │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                 Phase 4: GitOps 基礎設施同步                         │
├─────────────────────────────────────────────────────────────────────┤
│ 4.1: 檢查 ArgoCD 狀態                                                │
│ 4.2: 獲取 ArgoCD 密碼                                                │
│ 4.3: 訪問 ArgoCD UI                                                 │
│ 4.4: Git Repository SSH 認證 (🤖 已自動化)                         │
│ 4.5: 理解 Bootstrap 分階段部署                                      │
│      ├─ Phase 1: Namespaces (立即部署) ✅                           │
│      └─ Phase 2: Certificates, Ingress (等待 CRDs) ⏳              │
│ 4.6: 驗證 ApplicationSet 同步                                       │
│ 4.7: 手動同步基礎設施 Applications 👉 您在這裡                      │
│      ├─ infra-cert-manager (提供 CRDs)                              │
│      ├─ infra-ingress-nginx                                          │
│      ├─ infra-metallb                                                │
│      ├─ infra-external-secrets-operator                              │
│      ├─ infra-vault                                                  │
│      └─ infra-topolvm                                                │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 5: Vault 初始化                            │
├─────────────────────────────────────────────────────────────────────┤
│ • 初始化 Vault (生成 Unseal Keys + Root Token)                      │
│ • 解封所有 Vault 實例 (vault-0, vault-1, vault-2)                   │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 6: 應用部署                                │
├─────────────────────────────────────────────────────────────────────┤
│ • PostgreSQL (資料庫)                                                │
│ • Prometheus (指標收集)                                              │
│ • Loki (日誌聚合)                                                    │
│ • Tempo (分散式追蹤)                                                 │
│ • Mimir (長期指標儲存)                                               │
│ • Grafana (可視化)                                                   │
└─────────────────────────────────────────────────────────────────────┘
                                 ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 7: 最終驗證                                │
├─────────────────────────────────────────────────────────────────────┤
│ • 集群健康檢查 (Nodes, Pods, Events)                                │
│ • 網路驗證 (雙網路, MetalLB, Ingress)                               │
│ • DNS 驗證 (內外部域名解析)                                          │
│ • 服務 UI 訪問 (ArgoCD, Grafana, Prometheus, etc.)                  │
└─────────────────────────────────────────────────────────────────────┘
```

**關鍵提示**:
- 🤖 = 已自動化,無需手動操作
- ⏳ = 需要等待前置步驟完成
- 👉 = 當前需要執行的步驟

---

## 已解決的"雞生蛋"依賴問題

本部署流程已完整解決以下循環依賴問題（詳見[故障排除](#故障排除)章節）：

### 問題 #1: ApplicationSet 路徑配置
- **症狀**: ArgoCD 無法找到應用路徑
- **解決方案**: ✅ 所有 ApplicationSet 路徑已包含 `argocd/` 前綴
- **驗證**: `argocd/appsets/appset.yaml` 已修正

### 問題 #2: AppProject 權限白名單
- **症狀**: 基礎設施應用無法創建 Namespace 或 IngressClass
- **解決方案**: ✅ `platform-bootstrap` 項目已包含所有必要資源權限
- **驗證**: `argocd/bootstrap/argocd-projects.yaml` 已配置完整

### 問題 #3: CRD 依賴順序
- **症狀**: cluster-bootstrap 嘗試創建 Certificate 但 cert-manager CRD 尚未安裝
- **解決方案**: ✅ 使用 Sync Wave 分階段部署 + `SkipDryRunOnMissingResource=true`
- **預期行為**: cluster-bootstrap Phase 2 會先失敗，待基礎設施同步後自動重試成功
- **驗證**: 基礎設施同步後 cluster-bootstrap 自動變為 Synced

### 問題 #4: TopoLVM 調度模式
- **症狀**: Vault pods 顯示 "Insufficient capacity" 但實際有足夠空間
- **根本原因**: Scheduler Extender 模式未完整配置
- **解決方案**: ✅ 改用 Storage Capacity Tracking 模式（Kubernetes 1.21+ 原生）
- **驗證**: `argocd/apps/infrastructure/topolvm/overlays/values.yaml` 已啟用 `storageCapacityTracking`

### 問題 #5: Vault Pod Anti-Affinity 與單 Worker Node
- **症狀**: vault-1/vault-2 pods 持續 Pending，錯誤 "didn't match pod anti-affinity rules"
- **根本原因**: Vault Helm chart 默認使用 `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity，要求每個 pod 在不同 node 上，但測試環境只有 1 個 worker node
- **解決方案**: ✅ 改用 `preferredDuringSchedulingIgnoredDuringExecution` (weight: 100)
  - 允許多個 Vault pods 在同一 node 上運行（測試環境）
  - 當有多個 worker nodes 時仍會嘗試分散（生產環境）
- **驗證**: `argocd/apps/infrastructure/vault/overlays/values.yaml` 已添加 `server.affinity` 配置
- **生產建議**: 多 worker node 環境可考慮改回 `required` 以提高可用性

### 問題 #6: ArgoCD Server URL 配置未生效
- **症狀**: ArgoCD UI 無法正確顯示 `https://argocd.detectviz.internal` URL,影響 SSO 回調和狀態徽章
- **根本原因**: ArgoCD 由 Ansible 通過 Helm chart 安裝,`argocd-cm.yaml` 配置從未被應用到實際運行的 ConfigMap
- **解決方案**: ✅ 啟用 ArgoCD 自我管理配置
  - 添加 ArgoCD 到 ApplicationSet (`argocd/appsets/appset.yaml`)
  - 創建 config-only 管理模式（不重新部署 ArgoCD 本身）
  - 只管理配置文件 (`argocd-cm.yaml`)，避免與 Ansible 安裝衝突
- **臨時修復**: 已手動 patch ConfigMap: `kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"url":"https://argocd.detectviz.internal"}}'`
- **驗證**: `argocd/apps/infrastructure/argocd/overlays/kustomization.yaml` 已改為 config-only 模式
- **影響**: 未來配置變更可通過 GitOps 管理,無需手動操作

### 問題 #7: Ingress-Nginx LoadBalancer 無法分配 IP
- **症狀**: ingress-nginx-controller 服務 EXTERNAL-IP 為 `<pending>`，無法訪問 https://argocd.detectviz.internal
- **根本原因**:
  1. MetalLB IP 池配置不完整（缺少 192.168.0.10）
  2. 使用 deprecated `spec.loadBalancerIP` 欄位與註解衝突
  3. `externalTrafficPolicy: Local` 導致健康檢查失敗，IP 被撤回
- **解決方案**: ✅ 完整修復配置
  - 添加 `192.168.0.10/32` 到 MetalLB IPAddressPool
  - 移除 deprecated `spec.loadBalancerIP` 欄位
  - 使用 `externalTrafficPolicy: Cluster` 模式
  - 通過 strategic merge patch 正確配置服務
- **驗證**: EXTERNAL-IP 成功分配為 192.168.0.10，HTTPS 正常訪問
- **相關文件**: `ingress-nginx-loadbalancer-fix.md`
- **Commits**: bbab4f2, 16bb52d, 8bafac7, 959332d

**部署建議**:
- ⚠️ **cluster-bootstrap 顯示 OutOfSync 是正常的**，在基礎設施同步前會持續此狀態
- ✅ **所有配置文件已修正**，無需手動調整
- 📋 **遵循本文件步驟**，問題會自動解決

---

## 目錄

- [前置作業](#前置作業)
  - [1. Proxmox 雙網路配置](#1-proxmox-雙網路配置)
  - [2. DNS 伺服器配置](#2-dns-伺服器配置)
  - [3. VM 模板準備](#3-vm-模板準備)
  - [4. SSH 金鑰準備](#4-ssh-金鑰準備)
- [部署流程](#部署流程)
  - [Phase 1: Terraform 基礎設施佈建](#phase-1-terraform-基礎設施佈建)
  - [Phase 2: 網路配置驗證](#phase-2-網路配置驗證)
  - [Phase 3: Ansible 自動化部署](#phase-3-ansible-自動化部署)
  - [Phase 4: GitOps 基礎設施同步](#phase-4-gitops-基礎設施同步)
  - [Phase 5: Vault 初始化](#phase-5-vault-初始化)
  - [Phase 6: 應用部署](#phase-6-應用部署)
  - [Phase 7: 最終驗證](#phase-7-最終驗證)
- [故障排除](#故障排除)

---

## 前置作業

### 1. Proxmox 雙網路配置

DetectViz 使用雙網路架構以分離管理流量與集群內部通訊。

**參考文件**: `docs/infrastructure/00-planning/configuration-network.md`

#### 1.1 配置網路橋接器

編輯 `/etc/network/interfaces`：

```bash
# 備份現有配置
cp /etc/network/interfaces /etc/network/interfaces.backup

# 編輯網路配置
vi /etc/network/interfaces
```

**配置內容**：

```bash
# 外部網路橋接器 (vmbr0 - enp4s0)
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.2/24
    gateway 192.168.0.1
    bridge-ports enp4s0
    bridge-stp off
    bridge-fd 0
    mtu 1500

# 內部集群網路橋接器 (vmbr1 - enp5s0)
auto vmbr1
iface vmbr1 inet static
    address 10.0.0.2/24
    bridge-ports enp5s0
    bridge-stp off
    bridge-fd 0
    mtu 1500
```

> **MTU 設定說明**:
> - **預設 1500**: 適用於所有標準網卡和交換機，建議使用
> - **進階 9000**: 需要網卡、交換機、線材全部支援巨型幀（Jumbo Frames），否則會導致連線失敗
> - **診斷方法**: 如果設定 9000 後無法連線，請改回 1500

#### 1.2 配置 sysctl 參數

```bash
cat <<EOF | tee /etc/sysctl.d/99-proxmox-network.conf
# Proxmox Host Network Configuration
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.disable_ipv6 = 1
EOF

sysctl --system
```

#### 1.3 重啟網路服務

```bash
systemctl restart networking
```

#### 1.4 驗證配置

```bash
# 檢查橋接器狀態
ip addr show vmbr0
ip addr show vmbr1

# 驗證 MTU
ip link show vmbr0 | grep mtu
ip link show vmbr1 | grep mtu

# 驗證 sysctl
sysctl net.ipv4.ip_forward
sysctl net.ipv4.conf.all.rp_filter
```

**預期結果**：
- vmbr0: 192.168.0.2/24, MTU 1500
- vmbr1: 10.0.0.2/24, MTU 1500
- ip_forward = 1
- rp_filter = 2

---

### 2. DNS 伺服器配置

DetectViz 使用 Proxmox dnsmasq 提供內部 DNS 解析。

**參考文件**: `docs/infrastructure/00-planning/configuration-domain.md`

#### 2.1 安裝 dnsmasq

```bash
apt update
apt install dnsmasq -y
```

#### 2.2 配置 dnsmasq

創建 `/etc/dnsmasq.d/detectviz.conf`：

```bash
cat <<EOF | tee /etc/dnsmasq.d/detectviz.conf
# DetectViz DNS Configuration
domain=detectviz.internal
expand-hosts
local=/detectviz.internal/

# 外部網路記錄 (vmbr0)
address=/proxmox.detectviz.internal/192.168.0.2
address=/ipmi.detectviz.internal/192.168.0.4
address=/k8s-api.detectviz.internal/192.168.0.10
address=/master-1.detectviz.internal/192.168.0.11
address=/master-2.detectviz.internal/192.168.0.12
address=/master-3.detectviz.internal/192.168.0.13
address=/app-worker.detectviz.internal/192.168.0.14

# 內部集群網路域名
local=/cluster.internal/

# 內部網路記錄 (vmbr1)
address=/master-1.cluster.internal/10.0.0.11
address=/master-2.cluster.internal/10.0.0.12
address=/master-3.cluster.internal/10.0.0.13
address=/app-worker.cluster.internal/10.0.0.14

# 應用服務
address=/argocd.detectviz.internal/192.168.0.10
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
EOF
```

#### 2.3 啟動 dnsmasq

```bash
systemctl enable --now dnsmasq
systemctl restart dnsmasq
systemctl status dnsmasq
```

#### 2.4 驗證 DNS

```bash
# 測試外部域名解析
dig @192.168.0.2 master-1.detectviz.internal +short
# 預期: 192.168.0.11

# 測試集群內部域名解析
dig @192.168.0.2 master-1.cluster.internal +short
# 預期: 10.0.0.11

# 測試外部 DNS 轉發
dig @192.168.0.2 google.com +short
# 預期: Google IP 位址
```

---

### 3. VM 模板準備

**參考文件**: `docs/infrastructure/02-proxmox/vm-template-creation.md`

確保已建立 Ubuntu 22.04 Cloud-init 模板（VM ID: 9000）

驗證模板：

```bash
pvesh get /nodes/proxmox/qemu --output-format json | jq -r '.[] | select(.template==1) | .name'
# 預期輸出: ubuntu-2204-template
```

---

### 4. SSH 金鑰準備

```bash
# 檢查是否已有 SSH 金鑰
ls -la ~/.ssh/id_rsa.pub

# 如果沒有，生成新的金鑰對
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

---

## 部署流程

### Phase 1: Terraform 基礎設施佈建

**目標**: 建立 4 台 VM，配置雙網路架構（vmbr0 + vmbr1）

#### 1.1 檢查 Terraform 配置

確認 `terraform/terraform.tfvars` 配置正確：

```bash
cd terraform/

# 檢查網路配置
grep -E 'proxmox_bridge|k8s_overlay_bridge|master_internal_ips|worker_internal_ips|cluster_domain' terraform.tfvars

# 檢查磁碟配置
grep -E 'worker_system_disk_sizes|worker_data_disks' terraform.tfvars
```

**預期輸出 - 網路配置**：
```
proxmox_bridge     = "vmbr0"          # 外部網路 (管理 + 應用)
k8s_overlay_bridge = "vmbr1"          # 內部網路 (Kubernetes 節點間通訊)
master_internal_ips = ["10.0.0.11", "10.0.0.12", "10.0.0.13"]
worker_internal_ips = ["10.0.0.14"]
cluster_domain      = "cluster.internal"
```

**預期輸出 - 磁碟配置（雙磁碟架構）**：
```hcl
worker_system_disk_sizes = ["100G"]    # 系統磁碟 (OS + kubelet)
worker_data_disks = [
  {
    size    = "250G"                   # 資料磁碟 (TopoLVM topolvm-vg)
    storage = "nvme-vm"
  }
]
```

**說明**：
- **Master 節點**: 單磁碟 100GB (OS + etcd)
- **Worker 節點**: 雙磁碟架構
  - `/dev/sda` 100GB: 系統磁碟
  - `/dev/sdb` 250GB: 資料磁碟 (供 TopoLVM 管理，動態 PV)

#### 1.2 初始化並部署

```bash
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -auto-approve
```

#### 1.3 驗證 VM 創建

```bash
# 檢查 VM 狀態
pvesh get /nodes/proxmox/qemu --output-format json | jq -r '.[] | select(.vmid >= 111 and .vmid <= 114) | {vmid, name, status}'

# 測試 SSH 連接
ssh ubuntu@192.168.0.11 'hostname'
ssh ubuntu@192.168.0.14 'hostname'

# 檢查 app-worker 磁碟配置
ssh ubuntu@192.168.0.14 'lsblk'
```

**預期輸出 (app-worker 磁碟)**：
```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda      8:0    0  100G  0 disk
├─sda1   8:1    0    1M  0 part
├─sda2   8:2    0    2G  0 part /boot
└─sda3   8:3    0   98G  0 part
  └─ubuntu--vg-ubuntu--lv 253:0 0 98G  0 lvm  /
sdb      8:16   0  250G  0 disk     ← 資料磁碟 (未格式化)
```

#### 1.4 TopoLVM Volume Group 配置

**重要**: LVM Volume Group 的建立已經**自動化**在 Ansible 部署流程中 (Phase 4: Worker Role),**無需手動操作**。

Ansible 會在 Phase 4 自動執行:
1. 檢查 /dev/sdb 磁碟是否存在
2. 建立 Physical Volume (`pvcreate /dev/sdb`)
3. 建立 Volume Group (`vgcreate topolvm-vg /dev/sdb`)
4. 驗證 LVM 配置

配置檔案位置: `ansible/group_vars/all.yml:51-60`

```yaml
configure_lvm: true  # 啟用 LVM 自動配置

lvm_volume_groups:
  - name: topolvm-vg   # Volume Group 名稱
    devices:
      - /dev/sdb       # 使用的物理設備 (250GB 資料磁碟)
```

**部署後驗證** (在 Phase 4 完成後):
```bash
# SSH 到 app-worker 檢查 LVM 配置
ssh ubuntu@192.168.0.14 'sudo vgs && sudo pvs'
```

**預期輸出**：
```bash
# vgs
  VG          #PV #LV #SN Attr   VSize    VFree
  topolvm-vg    1   0   0 wz--n- <250.00g <250.00g  ← TopoLVM VG (自動建立)
  ubuntu-vg     1   1   0 wz--n-  <98.00g       0   ← 系統 VG
```

> **說明**:
> - Ansible Worker Role 會自動檢查並建立 LVM 配置
> - 如果 VG 已存在,會自動跳過 (ignore_errors: true)
> - 可透過設定 `configure_lvm: false` 停用自動 LVM 配置

#### 1.5 TopoLVM Storage Capacity 模式配置

**重要**: TopoLVM 使用 **Storage Capacity Tracking** 模式（Kubernetes 1.21+ 原生功能），而非舊的 Scheduler Extender 模式。

**配置檔案**: `argocd/apps/infrastructure/topolvm/overlays/values.yaml`

```yaml
scheduler:
  enabled: false  # 禁用 scheduler extender (不需要)

controller:
  storageCapacityTracking:
    enabled: true  # 啟用 CSI Storage Capacity Tracking

webhook:
  podMutatingWebhook:
    enabled: false  # Storage Capacity 模式不需要 pod webhook
```

**Storage Capacity Tracking 優勢**:
- ✅ Kubernetes 原生功能（1.21+ GA）
- ✅ 無需配置 kube-scheduler extender
- ✅ 更簡單、更可靠的調度機制
- ✅ 自動容量追蹤和報告

**部署後驗證** (在 Phase 4.7 完成後):
```bash
# 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A

# 檢查 TopoLVM controller 日誌
kubectl logs -n kube-system -l app.kubernetes.io/component=controller --tail=50
```

**預期輸出**：
```
NAMESPACE      NAME                    STORAGECLASS           CAPACITY
kube-system    topolvm-<node>-<hash>   topolvm-provisioner    257693843456
```

#### 1.6 檢查生成的文件

```bash
# 回到 terraform 目錄
cd /path/to/detectviz-gitops/terraform

# Ansible inventory
cat ../ansible/inventory.ini

# /etc/hosts 片段
cat ../hosts-fragment.txt
```

---

### Phase 2: 網路配置驗證

**目標**: 驗證雙網路架構配置正確

#### 2.1 執行網路驗證腳本

```bash
cd ../scripts/
./validate-dual-network.sh
```

#### 2.2 手動驗證（可選）

```bash
# 檢查 VM 網路介面
ssh ubuntu@192.168.0.11 'ip addr show eth0'
ssh ubuntu@192.168.0.11 'ip addr show eth1'

# 檢查 MTU 設定
ssh ubuntu@192.168.0.11 'ip link show eth0 | grep mtu'
ssh ubuntu@192.168.0.11 'ip link show eth1 | grep mtu'

# 測試內部網路連通性
ssh ubuntu@192.168.0.11 'ping -c 3 10.0.0.14'

# 測試 DNS 解析
ssh ubuntu@192.168.0.11 'getent hosts master-1.detectviz.internal'
ssh ubuntu@192.168.0.11 'getent hosts master-1.cluster.internal'
```

**預期結果**：
- ✅ 每個 VM 有兩個網路介面 (eth0, eth1)
- ✅ MTU 都設定為 1500 (或您自訂的值)
- ✅ 內部網路可互通
- ✅ DNS 正確解析兩個域名

---

### Phase 3: Ansible 自動化部署

**目標**: 部署 Kubernetes 集群與所有基礎設施組件

#### 3.1 檢查 Ansible Inventory

```bash
cd ../ansible/
cat inventory.ini

# 測試 Ansible 連接
ansible all -i inventory.ini -m ping
```

#### 3.2 執行完整部署

```bash
ansible-playbook -i inventory.ini deploy-cluster.yml
```

**部署階段**：
1. **[Phase 1] Common Role**: 系統初始化、套件安裝、Kubernetes 內核參數配置
   - 安裝基礎套件: `apt-transport-https`, `ca-certificates`, `curl`, `gnupg`, `python3-pip`
   - **安裝 Python Kubernetes 客戶端**: `kubernetes`, `pyyaml`, `jsonpatch` (供 ansible kubernetes.core 模組使用)
   - 安裝 containerd (2.1.5) 和 Kubernetes 組件 (1.32.0)
   - 安裝 yq (YAML 處理器) 供後續 manifest 修改使用
   - 配置 Kubernetes 必要內核參數：
     - `net.ipv4.ip_forward=1` - 啟用 IP 轉發（Pod 網路路由）
     - `net.bridge.bridge-nf-call-iptables=1` - 橋接流量經 iptables 處理
     - `net.bridge.bridge-nf-call-ip6tables=1` - IPv6 橋接流量處理
     - 載入 `br_netfilter` 內核模組並持久化

2. **[Phase 2] Network Role**:
   - 配置雙網路介面 (eth0: 192.168.0.0/24 + eth1: 10.0.0.0/24)
   - 設定 /etc/hosts (detectviz.internal + cluster.internal 雙域名)
   - 配置網路 sysctl 參數 (rp_filter=2 支援非對稱路由)

3. **[Phase 3] Master Role**: 初始化 Kubernetes 控制平面
   - 初始化第一個 master 節點 (kubeadm init)
   - 部署 Kube-VIP (控制平面 HA 的虛擬 IP)
   - 安裝 Calico CNI 網路插件
   - 其他 master 節點加入控制平面 (kubeadm join --control-plane)
   - **設定 kubeconfig**: 為 root 和 ansible_user (ubuntu) 建立 ~/.kube/config

4. **[Phase 3.5] 生成 Worker 加入命令**:
   - 在 master-1 上生成 kubeadm join token
   - 將 join 命令動態傳遞給所有 worker 節點

5. **[Phase 4] Worker Role**: 加入工作節點
   - 配置 LVM Volume Groups (topolvm-vg) 供 TopoLVM 使用
   - 使用 Phase 3.5 生成的 join 命令加入集群
   - 等待 kubelet 健康檢查通過

6. **[Phase 5] 節點標籤**: 為節點添加工作負載標籤
   - master-1: `workload-monitoring=true` (Grafana, Prometheus)
   - master-2: `workload-mimir=true` (Mimir 長期指標儲存)
   - master-3: `workload-loki=true` (Loki 日誌聚合)
   - app-worker: `workload-apps=true` (ArgoCD, 應用程式)
   - **注意**: 使用 `--kubeconfig=/etc/kubernetes/admin.conf` 明確指定配置檔案

7. **[Phase 6] ArgoCD 部署**: 安裝 GitOps 引擎
   - **設定環境變數**: `KUBECONFIG=/etc/kubernetes/admin.conf` (供 kubernetes.core.k8s 模組使用)
   - 建立 argocd namespace
   - 下載 ArgoCD 官方 manifest
   - 使用 yq 為 ArgoCD 組件添加 nodeSelector (確保部署到 app-worker)
   - 應用 ArgoCD manifest
   - 部署 Root Application (App of Apps 模式)

8. **[Phase 7] 最終驗證**: 集群健康檢查
   - 等待所有節點進入 Ready 狀態
   - 顯示集群節點資訊和部署摘要

#### 3.3 部署後驗證

```bash
# 設定 kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig/admin.conf

# 檢查節點狀態
kubectl get nodes -o wide

# 檢查節點標籤
kubectl get nodes --show-labels
```

**預期輸出**：
```
NAME         STATUS   ROLES           AGE   VERSION
master-1     Ready    control-plane   10m   v1.32.0
master-2     Ready    control-plane   9m    v1.32.0
master-3     Ready    control-plane   8m    v1.32.0
app-worker   Ready    <none>          7m    v1.32.0
```

---

### Phase 4: GitOps 基礎設施同步

**目標**: 透過 ArgoCD 自動部署基礎設施組件

#### 4.1 檢查 ArgoCD 狀態

```bash
# 等待 ArgoCD 就緒
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 檢查 ArgoCD Pods
kubectl get pods -n argocd
```

#### 4.2 獲取 ArgoCD 密碼

```bash
# 獲取初始密碼
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
```

#### 4.3 訪問 ArgoCD UI

```bash
# 選項 1: Port Forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 選項 2: 通過 Ingress (需要先配置 DNS)
# https://argocd.detectviz.internal
```

登入資訊：
- **URL**: `https://localhost:8080` 或 `https://argocd.detectviz.internal`
- **Username**: `admin`
- **Password**: (上一步驟獲取的密碼)

#### 4.4 配置 Git Repository SSH 認證

> **🤖 自動化**: 此步驟已在 **Ansible Phase 6** 中自動完成。
>
> **前置條件**: SSH 私鑰存在於 `~/.ssh/id_ed25519_detectviz`
>
> 如果您的 SSH 金鑰已準備好,Ansible 會自動:
> - ✅ 複製 SSH 金鑰到 master-1
> - ✅ 建立 ArgoCD repository secret
> - ✅ 配置 GitHub SSH known_hosts
> - ✅ 重啟 repo-server 並刷新 root application
>
> **以下手動步驟僅供參考和故障排除使用**。

---

**手動配置步驟** (如果自動化失敗或需要手動干預):

由於 Root Application 使用 SSH URL 訪問 GitHub 私有 repository,需要配置 SSH 金鑰:

```bash
# 1. 複製 SSH 私鑰到 master-1
scp ~/.ssh/id_ed25519_detectviz ubuntu@192.168.0.11:/tmp/argocd-ssh-key

# 2. 建立 ArgoCD repository secret
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create secret generic detectviz-gitops-repo --from-file=sshPrivateKey=/tmp/argocd-ssh-key -n argocd"

# 3. 添加標籤讓 ArgoCD 識別為 repository credential
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf label secret detectviz-gitops-repo argocd.argoproj.io/secret-type=repository -n argocd --overwrite"

# 4. 配置 repository URL
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf patch secret detectviz-gitops-repo -n argocd -p='{\"stringData\":{\"type\":\"git\",\"url\":\"git@github.com:detectviz/detectviz-gitops.git\"}}'"

# 5. 添加 GitHub SSH known_hosts
ssh-keyscan github.com > /tmp/github-hostkey
scp /tmp/github-hostkey ubuntu@192.168.0.11:/tmp/
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create secret generic argocd-ssh-known-hosts --from-file=ssh_known_hosts=/tmp/github-hostkey -n argocd"

# 6. 重啟 ArgoCD repo-server 載入新的認證
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment argocd-repo-server -n argocd"
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status deployment argocd-repo-server -n argocd --timeout=60s"

# 7. 強制刷新 root application
ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf patch application root -n argocd -p='{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}' --type=merge"

# 8. 清理臨時檔案
ssh ubuntu@192.168.0.11 "rm -f /tmp/argocd-ssh-key /tmp/github-hostkey"
```

**等待約 10-30 秒後,驗證 Root Application 狀態**:
```bash
# 檢查 root application
kubectl get application root -n argocd
# 預期輸出: SYNC STATUS = Synced

# 檢查 ApplicationSets
kubectl get applicationset -n argocd
# 預期看到: argocd-bootstrap, detectviz-gitops
```

#### 4.5 理解 Bootstrap 分階段部署

> **📚 詳細文檔**: `argocd/bootstrap/PHASE_DEPLOYMENT.md`

ArgoCD Bootstrap 資源採用**兩階段部署策略**來解決 CRD 依賴問題:

**Phase 1: 基礎資源** (Sync Wave: -10)
- ✅ 立即部署: Namespaces (cert-manager, ingress-nginx, vault, etc.)
- ✅ 不依賴任何 CRDs
- ✅ 總是成功

**Phase 2: 進階資源** (Sync Wave: 10)
- ⏳ 延後部署: Certificates, ClusterIssuers, Ingress, ArgoCDExtensions
- ⏳ 依賴基礎設施 CRDs (cert-manager, ingress-nginx, argo-rollouts)
- ⏳ 使用 `SkipDryRunOnMissingResource=true` 避免預檢查失敗

**預期行為**:
```
1. Root Application 同步 → Synced, Healthy ✅
2. cluster-bootstrap Phase 1 部署 → Namespaces 建立成功 ✅
3. 基礎設施 ApplicationSets 生成 Applications (cert-manager, ingress-nginx, etc.) ✅
4. cluster-bootstrap Phase 2 嘗試部署 → 失敗 (CRDs 尚未安裝) ⚠️  這是正常的!
5. 手動同步基礎設施 Applications → CRDs 安裝 ✅
6. cluster-bootstrap Phase 2 自動重試 → 成功 ✅
```

**為什麼 cluster-bootstrap 會顯示錯誤?**

在基礎設施同步之前,您會看到類似的錯誤訊息:
```
resource mapping not found for name: "argocd-server-tls"
no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

**這是正常且預期的行為**,因為:
- Phase 2 資源需要 cert-manager 的 `Certificate` CRD
- cert-manager 尚未部署,CRD 不存在
- 一旦基礎設施同步完成,cluster-bootstrap 會自動重試並成功

---

#### 4.6 驗證 ApplicationSet 同步

```bash
# 檢查 Root Application 狀態
kubectl get application root -n argocd
# 預期: Synced, Healthy

# 檢查 cluster-bootstrap 狀態
kubectl get application cluster-bootstrap -n argocd
# 預期: OutOfSync, Missing (等待基礎設施 CRDs) - 這是正常的!

# 檢查 ApplicationSet
kubectl get applicationset -n argocd

# 檢查所有應用狀態
argocd app list

# 檢查基礎設施組件 (部署後)
kubectl get pods -n metallb-system
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
kubectl get pods -n external-secrets-system
kubectl get pods -n vault
kubectl get pods -n topolvm-system
```

#### 4.7 手動同步基礎設施 Applications

> **📖 快速參考**: 詳細步驟請參考 `QUICK_START.md`

此時基礎設施 Applications 已自動生成,但處於 `Unknown` 狀態,需要手動觸發同步:

**選項 1: 在 ArgoCD UI 中手動同步** (推薦)

1. 訪問 ArgoCD UI (https://localhost:8080)
2. 點擊每個 `infra-*` Application
3. 點擊 "SYNC" 按鈕
4. 等待同步完成

**建議同步順序**:
1. `infra-argocd` (ArgoCD 自我配置 - 應用 URL 設定)
2. `infra-cert-manager` (優先 - 提供 Certificate CRDs)
3. `infra-ingress-nginx`
4. `infra-metallb`
5. `infra-external-secrets-operator`
6. `infra-vault`
7. `infra-topolvm`

**注意**: `infra-argocd` 是 ArgoCD 的配置管理應用,會自動出現在 ApplicationSet 中。它不會重新部署 ArgoCD 本身,只管理配置文件（如 server URL）。

**選項 2: 使用命令行同步**

```bash
# SSH 到 master-1
ssh ubuntu@192.168.0.11

# 同步所有基礎設施 Applications
for app in infra-argocd infra-cert-manager infra-ingress-nginx infra-metallb \
           infra-external-secrets-operator infra-vault infra-topolvm; do
  sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf patch application $app -n argocd \
    -p='{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":true}}}' \
    --type=merge
  echo "✅ Triggered sync for $app"
  sleep 5
done
```

**選項 3: 使用 ArgoCD CLI**

```bash
# 1. Port forward (在另一個終端)
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443 &

# 2. 登入 (使用 Phase 4.2 獲取的密碼)
argocd login localhost:8080 \
  --username admin \
  --password <your-argocd-password> \
  --insecure

# 3. 同步所有基礎設施 Applications
argocd app sync infra-cert-manager
argocd app sync infra-ingress-nginx
argocd app sync infra-metallb
argocd app sync infra-external-secrets-operator
argocd app sync infra-vault
argocd app sync infra-topolvm

# 4. 檢查狀態
argocd app list
```

**驗證同步完成**:
```bash
# 等待所有 Pods 運行
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
kubectl get pods -n metallb-system
kubectl get pods -n external-secrets-system
kubectl get pods -n vault
kubectl get pods -n topolvm-system

# 確認 CRDs 已安裝
kubectl get crd | grep cert-manager
# 預期輸出: certificates.cert-manager.io, clusterissuers.cert-manager.io, issuers.cert-manager.io

# 檢查 cluster-bootstrap 狀態 (應該自動重試並成功)
kubectl get application cluster-bootstrap -n argocd
# 預期: Synced, Healthy (Phase 2 資源已部署)

# 驗證 TopoLVM CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 預期: 應該看到 topolvm-provisioner 的容量資源
```

**預期結果**：
- ✅ 所有基礎設施 Applications: Synced, Healthy
- ✅ cluster-bootstrap: Synced, Healthy (Phase 2 自動重試成功)
- ✅ MetalLB 運行中 (LoadBalancer 支援)
- ✅ cert-manager 運行中 (TLS 證書管理 + CRDs)
- ✅ NGINX Ingress 運行中 (Ingress 控制器)
- ✅ External Secrets 運行中 (Secret 管理)
- ✅ Vault 運行中 (密鑰管理,待初始化)
- ✅ TopoLVM 運行中 (動態 PV 提供，使用 Storage Capacity Tracking)

**常見問題處理**:

如果基礎設施 Applications 顯示 `OutOfSync` 或 `Unknown` 但不自動同步：

```bash
# 1. 檢查 ArgoCD repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50

# 2. 如果看到路徑錯誤，確認 ApplicationSet 配置正確
kubectl get applicationset detectviz-gitops -n argocd -o yaml | grep path

# 3. 手動觸發 root application 刷新
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge

# 4. 等待 30 秒後檢查狀態
sleep 30 && kubectl get applications -n argocd
```

---

### Phase 5: Vault 初始化

**目標**: 手動初始化並解封 Hashicorp Vault

#### 5.1 等待 Vault Pod 就緒

```bash
kubectl get pods -n vault --watch
# 等待所有 vault-0/1/2 都處於 Running 狀態 (0/1 Ready 是正常的,因為尚未 unseal)
# Ctrl+C 退出 watch
```

**注意**:
- 所有 3 個 Vault pods 都會進入 Running 狀態，但顯示 0/1 Ready (因為未 unseal)
- 如果 vault-1/vault-2 持續 Pending，檢查是否遇到 Anti-Affinity 問題（參見[問題 #5](#問題-5-vault-pod-anti-affinity-與單-worker-node)）
- 配置已修正為 `preferredDuringScheduling`，允許單 worker node 環境運行

#### 5.2 初始化 Vault

```bash
# 在第一個 Vault Pod 上執行初始化
kubectl exec -n vault vault-0 -c vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-keys.json

# 顯示初始化金鑰
cat vault-keys.json | jq
```

**重要**: 安全保存 `vault-keys.json`，包含：
- `unseal_keys_b64`: 5 個 Unseal Keys
- `root_token`: Root Token

#### 5.3 解封所有 Vault 實例

```bash
# 提取 Unseal Keys
UNSEAL_KEY_1=$(cat vault-keys.json | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(cat vault-keys.json | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(cat vault-keys.json | jq -r '.unseal_keys_b64[2]')

# 解封 vault-0
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_3

# 驗證狀態
kubectl exec -n vault vault-0 -- vault status

# 預期輸出:
# Sealed: false  ✅
# Initialized: true ✅
```

# 解封 vault-1 (會自動加入 Raft cluster)
kubectl exec -n vault vault-1 -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-1 -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-1 -- vault operator unseal $UNSEAL_KEY_3

# 解封 vault-2 (會自動加入 Raft cluster)
kubectl exec -n vault vault-2 -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-2 -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-2 -- vault operator unseal $UNSEAL_KEY_3
```

**注意**:
- vault-1 和 vault-2 在 unseal 後會自動加入 vault-0 的 Raft cluster
- 第三次 unseal 命令後可能仍顯示 `Sealed: true`，但日誌會顯示 "vault is unsealed"
- 這是正常行為，Vault 正在加入 Raft cluster 並同步狀態
- 稍等片刻後檢查 pod 狀態，應該會變成 1/1 Ready

#### 5.4 驗證 Vault 狀態

```bash
# 檢查所有 Vault pods 狀態
kubectl get pods -n vault -l app.kubernetes.io/name=vault,component=server

# 檢查所有 Vault 實例
kubectl exec -n vault vault-0 -- vault status
kubectl exec -n vault vault-1 -- vault status
kubectl exec -n vault vault-2 -- vault status
```

**預期結果**:
- 所有 pods 顯示 `1/1 Running`
- vault-0: `Sealed: false`, `HA Mode: active`
- vault-1: `Sealed: false`, `HA Mode: standby`
- vault-2: `Sealed: false`, `HA Mode: standby`
- 所有實例都在同一個 Raft cluster 中 (相同 `Cluster ID`)

**如果 vault pods 在 unseal 後仍然 0/1**:
```bash
# 檢查日誌
kubectl logs vault-1 -n vault --tail=50
# 應該看到 "vault is unsealed" 和 "entering standby mode"

# 強制刪除並重建 pods (會保留 PVC 資料)
kubectl delete pod vault-0 vault-1 vault-2 -n vault

# 等待 pods 重新創建後再次 unseal
# (重啟後 Vault 會重新進入 sealed 狀態)
```

---

### Phase 6: 應用部署

**目標**: 同步觀測性堆疊、身份認證與應用服務

#### 6.0 前置檢查

確認應用層 ApplicationSet 已啟用：

```bash
# 檢查 apps-appset ApplicationSet 是否存在
kubectl get applicationset apps-appset -n argocd

# 檢查應用 Applications 是否已生成
kubectl get applications -n argocd | grep -E "postgresql|keycloak|prometheus|grafana"
```

**預期輸出**: 應該看到以下 Applications（狀態可能為 Unknown 或 OutOfSync）:
- `postgresql` - PostgreSQL HA 資料庫
- `keycloak` - 身份認證與 SSO
- `prometheus` - Prometheus + Alertmanager + Node Exporter
- `loki` - 日誌聚合
- `tempo` - 分散式追蹤
- `mimir` - 長期指標儲存
- `grafana` - 監控可視化
- `alertmanager` - 告警管理
- `node-exporter` - 節點指標收集
- `pgbouncer-hpa` - PostgreSQL 連接池

**如果沒有看到這些 Applications**:
```bash
# 刷新 root application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 等待 30 秒後再次檢查
sleep 30 && kubectl get applications -n argocd
```

---

#### 6.1 應用部署順序說明

**重要**: 應用之間有依賴關係，必須按以下順序部署：

```
階段 1: 基礎服務
  └─ postgresql (資料庫) ← 被 keycloak 和 grafana 依賴

階段 2: 身份認證
  └─ keycloak (SSO/OAuth2) ← 依賴 postgresql，為 grafana 提供 OAuth2

階段 3: 觀測性基礎設施
  ├─ prometheus (指標收集)
  ├─ loki (日誌聚合)
  ├─ tempo (分散式追蹤)
  └─ mimir (長期指標儲存)

階段 4: 可視化
  └─ grafana (監控儀表板) ← 依賴 postgresql (存儲), keycloak (OAuth2), prometheus/loki/tempo/mimir (資料源)

階段 5: 輔助服務
  ├─ alertmanager (告警管理)
  ├─ node-exporter (節點指標)
  └─ pgbouncer-hpa (PostgreSQL 連接池)
```

---

#### 6.2 階段 1: 部署 PostgreSQL (資料庫)

**優先級**: 🔴 最高（被 keycloak 和 grafana 依賴）

```bash
# 選項 1: 通過 ArgoCD UI
# 1. 訪問 https://argocd.detectviz.internal
# 2. 找到 "postgresql" Application
# 3. 點擊 "SYNC" 按鈕
# 4. 等待同步完成

# 選項 2: 通過 kubectl
kubectl patch application postgresql -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql-ha -n postgresql --timeout=300s

# 驗證 PostgreSQL 部署
kubectl get pods -n postgresql
kubectl get svc -n postgresql
kubectl get pvc -n postgresql
```

**預期結果**:
```
NAME                          READY   STATUS    RESTARTS   AGE
postgresql-ha-pgpool-0        1/1     Running   0          2m
postgresql-ha-postgresql-0    1/1     Running   0          2m
postgresql-ha-postgresql-1    1/1     Running   0          1m
```

**故障排除**:
- 如果 pods 一直 Pending: 檢查 PVC 是否綁定（`kubectl get pvc -n postgresql`）
- 如果 PVC 一直 Pending: 檢查 TopoLVM 是否正常運行（參見 Phase 4.7）

---

#### 6.3 階段 2: 部署 Keycloak (身份認證)

**優先級**: 🟠 高（依賴 postgresql，為 grafana 提供 OAuth2）

```bash
# 同步 keycloak
kubectl patch application keycloak -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# 驗證 Keycloak 部署
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
```

**預期結果**:
```
NAME          READY   STATUS    RESTARTS   AGE
keycloak-0    1/1     Running   0          2m
```

**訪問 Keycloak**:
```bash
# 獲取 admin 密碼（如果配置了 secret）
kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d

# 訪問 UI
# URL: https://keycloak.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)
```

**後續配置** (可選，視需求而定):
- 創建 Realm: `detectviz`
- 配置 OAuth2 Client: `grafana`
- 設置用戶和角色

---

#### 6.4 階段 3: 部署觀測性基礎設施

**優先級**: 🟡 中

```bash
# 並行同步觀測性組件（無相互依賴）
kubectl patch application prometheus -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application loki -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application tempo -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application mimir -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

wait  # 等待所有背景任務完成

# 驗證部署
kubectl get pods -n prometheus
kubectl get pods -n loki
kubectl get pods -n tempo
kubectl get pods -n mimir
```

**預期結果** (各命名空間):
```
# Prometheus namespace
prometheus-kube-prometheus-operator-*        1/1     Running
prometheus-kube-state-metrics-*              1/1     Running
prometheus-prometheus-node-exporter-*        1/1     Running (每個節點一個)
alertmanager-*                               1/1     Running
prometheus-*                                 1/1     Running

# Loki namespace
loki-*                                       1/1     Running

# Tempo namespace
tempo-*                                      1/1     Running

# Mimir namespace
mimir-*                                      多個 pods (分散式架構)
```

---

#### 6.5 階段 4: 部署 Grafana (可視化)

**優先級**: 🟢 低（依賴所有前面的服務）

**先決條件確認**:
```bash
# 確認 PostgreSQL 正在運行
kubectl get pods -n postgresql -l app.kubernetes.io/name=postgresql-ha

# 確認 Keycloak 正在運行
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak

# 確認資料源正在運行
kubectl get pods -n prometheus -l app.kubernetes.io/name=prometheus
kubectl get pods -n loki -l app.kubernetes.io/name=loki
kubectl get pods -n tempo -l app.kubernetes.io/name=tempo
kubectl get pods -n mimir -l app.kubernetes.io/name=mimir
```

**部署 Grafana**:
```bash
# 同步 grafana
kubectl patch application grafana -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n grafana --timeout=300s

# 驗證 Grafana 部署
kubectl get pods -n grafana
kubectl get svc -n grafana
kubectl get ingress -n grafana
```

**訪問 Grafana**:
```bash
# 獲取 admin 密碼
kubectl get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d

# 訪問 UI
# URL: https://grafana.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)
```

**Grafana 集成配置** (values.yaml 應已配置):
- ✅ **資料庫**: PostgreSQL (用於存儲 dashboards, users, sessions)
- ✅ **OAuth2**: Keycloak (SSO 登入)
- ✅ **資料源**:
  - Prometheus (指標查詢)
  - Loki (日誌查詢)
  - Tempo (追蹤查詢)
  - Mimir (長期指標查詢)

---

#### 6.6 階段 5: 部署輔助服務 (可選)

```bash
# Alertmanager (如果不是 prometheus 的一部分)
kubectl patch application alertmanager -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# Node Exporter (如果不是 prometheus 的一部分)
kubectl patch application node-exporter -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# PgBouncer (PostgreSQL 連接池)
kubectl patch application pgbouncer-hpa -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge
```

---

#### 6.7 最終驗證

```bash
# 檢查所有應用狀態
kubectl get applications -n argocd

# 檢查所有 pods
kubectl get pods -A | grep -E "postgresql|keycloak|prometheus|loki|tempo|mimir|grafana"

# 檢查所有服務
kubectl get svc -A | grep -E "postgresql|keycloak|prometheus|loki|tempo|mimir|grafana"

# 檢查所有 Ingress
kubectl get ingress -A
```

**預期結果**: 所有 Applications 應該為 `Synced, Healthy`

**服務訪問 URLs**:
- ArgoCD: https://argocd.detectviz.internal
- Keycloak: https://keycloak.detectviz.internal
- Grafana: https://grafana.detectviz.internal
- Prometheus: https://prometheus.detectviz.internal
- Alertmanager: https://alertmanager.detectviz.internal

---

#### 6.8 常見問題處理

**問題 1: Applications 顯示 Unknown 或 OutOfSync**

```bash
# 刷新特定 application
kubectl patch application <app-name> -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 強制同步
kubectl patch application <app-name> -n argocd \
  -p='{"operation":{"sync":{"prune":true,"force":true}}}' --type=merge
```

**問題 2: Helm chart 下載失敗**

確認 ArgoCD 已啟用 Helm 支持：
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep "kustomize.buildOptions"
# 應該看到: kustomize.buildOptions: "--enable-helm"
```

**問題 3: PVC 無法綁定**

檢查 TopoLVM 和 StorageClass：
```bash
kubectl get csistoragecapacity -A
kubectl get storageclass topolvm-provisioner
kubectl get pods -n topolvm-system
```

**問題 4: Grafana 無法連接 PostgreSQL**

檢查資料庫服務和密碼：
```bash
kubectl get svc -n postgresql
kubectl get secret -n grafana | grep postgres
kubectl logs -n grafana -l app.kubernetes.io/name=grafana --tail=50
```

---

### Phase 7: 最終驗證

#### 7.1 集群健康檢查

```bash
# 檢查所有節點
kubectl get nodes -o wide

# 檢查所有 Pods
kubectl get pods -A -o wide

# 檢查失敗的 Pods
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# 檢查事件
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

#### 7.2 網路驗證

```bash
# 驗證雙網路配置
./scripts/validate-dual-network.sh

# 檢查 MetalLB IP 池
kubectl get ipaddresspool -n metallb-system

# 檢查 Ingress
kubectl get ingress -A
```

#### 7.3 DNS 驗證

```bash
# 從 VM 測試 DNS
ssh ubuntu@192.168.0.11 'nslookup argocd.detectviz.internal 192.168.0.2'
ssh ubuntu@192.168.0.11 'nslookup master-1.cluster.internal 192.168.0.2'

# 從本機測試 (如果已配置 /etc/hosts)
curl -k https://argocd.detectviz.internal
curl -k https://grafana.detectviz.internal
```

#### 7.4 存取服務 UI

| 服務 | URL | 用途 |
|------|-----|------|
| ArgoCD | https://argocd.detectviz.internal | GitOps 管理 |
| Grafana | https://grafana.detectviz.internal | 監控儀表板 |
| Prometheus | https://prometheus.detectviz.internal | 指標查詢 |
| Loki | https://loki.detectviz.internal | 日誌查詢 |
| Tempo | https://tempo.detectviz.internal | 追蹤查詢 |
| PgAdmin | https://pgadmin.detectviz.internal | 資料庫管理 |

#### 7.5 效能驗證

```bash
# 檢查資源使用情況
kubectl top nodes
kubectl top pods -A

# 檢查儲存
kubectl get pvc -A
kubectl get pv

# 檢查網路策略
kubectl get networkpolicies -A
```

---

## 故障排除

### 常見問題

#### 1. Terraform 部署失敗

**問題**: VM 創建失敗或網路配置錯誤

**解決方案**:

```bash
# 檢查 Proxmox 橋接器
ssh root@192.168.0.2 'ip link show vmbr0'
ssh root@192.168.0.2 'ip link show vmbr1'

# 清理失敗的 VM
cd terraform/
./cleanup-failed-vms.sh

# 重新部署
terraform apply -auto-approve
```

#### 2. 網路連通性問題

**問題**: VM 之間無法通訊或 DNS 無法解析

**解決方案**:

```bash
# 檢查 VM 網路介面
ssh ubuntu@192.168.0.11 'ip addr show'

# 檢查路由
ssh ubuntu@192.168.0.11 'ip route'

# 檢查 DNS
ssh ubuntu@192.168.0.11 'cat /etc/resolv.conf'
ssh ubuntu@192.168.0.11 'nslookup master-1.detectviz.internal'

# 重新執行網路配置
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags network
```

#### 3. sysctl 參數未生效

**問題**: rp_filter 或 ip_forward 未正確設定

**解決方案**:

```bash
# 在 Proxmox 檢查
ssh root@192.168.0.2 'sysctl net.ipv4.conf.all.rp_filter'
ssh root@192.168.0.2 'sysctl net.ipv4.ip_forward'

# 在 VM 檢查
ssh ubuntu@192.168.0.11 'sudo sysctl net.ipv4.conf.all.rp_filter'
ssh ubuntu@192.168.0.11 'sudo sysctl net.ipv4.ip_forward'

# 如果不正確，重新應用
ssh ubuntu@192.168.0.11 'sudo sysctl --system'
```

#### 4. Kubernetes 節點未就緒

**問題**: 節點顯示 NotReady 狀態

**解決方案**:

```bash
# 檢查節點狀態
kubectl get nodes -o wide
kubectl describe node <node-name>

# 檢查 kubelet 日誌
ssh ubuntu@<node-ip> 'sudo journalctl -u kubelet -n 100 --no-pager'

# 檢查 CNI 狀態
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl get pods -n kube-system -l k8s-app=calico-node
```

#### 5. ArgoCD 應用同步失敗

**問題**: 應用顯示 OutOfSync 或 Degraded

**解決方案**:

```bash
# 檢查應用狀態
argocd app get <app-name>

# 查看詳細錯誤
kubectl describe application <app-name> -n argocd

# 手動同步
argocd app sync <app-name> --force

# 重置應用
argocd app delete <app-name>
argocd app create <app-name> ...
```

#### 6. ApplicationSet 路徑錯誤（雞生蛋問題 #1）

**症狀**:
```
ComparisonError: Failed to load target state: failed to generate manifest
apps/infrastructure/cert-manager/overlays: app path does not exist
```

**根本原因**: ApplicationSet 生成的應用路徑缺少 `argocd/` 前綴

**診斷**:
```bash
# 檢查 Application 的實際路徑
kubectl get application infra-cert-manager -n argocd -o jsonpath='{.spec.source.path}'
# 錯誤輸出: apps/infrastructure/cert-manager/overlays
# 正確輸出: argocd/apps/infrastructure/cert-manager/overlays

# 檢查 ApplicationSet 配置
kubectl get applicationset detectviz-gitops -n argocd -o yaml | grep -A 2 "path:"
```

**解決方案**:

1. 修正 `argocd/appsets/appset.yaml`:
```yaml
elements:
  - appName: cert-manager
    path: argocd/apps/infrastructure/cert-manager/overlays  # 添加 argocd/ 前綴
```

2. 提交並推送修改
3. 刷新 root application:
```bash
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

**預防措施**: 所有 ApplicationSet 中的路徑都應包含 `argocd/` 前綴

---

#### 7. AppProject 權限不足（雞生蛋問題 #2）

**症狀**:
```
resource :Namespace is not permitted in project platform-bootstrap
resource :IngressClass is not permitted in project platform-bootstrap
```

**根本原因**: AppProject `platform-bootstrap` 的 `clusterResourceWhitelist` 缺少必要資源

**診斷**:
```bash
# 檢查 Application 錯誤
kubectl get application infra-cert-manager -n argocd -o yaml | grep -A 10 "conditions:"

# 檢查 AppProject 白名單
kubectl get appproject platform-bootstrap -n argocd -o yaml | grep -A 20 "clusterResourceWhitelist"
```

**解決方案**:

修正 `argocd/bootstrap/argocd-projects.yaml`:
```yaml
clusterResourceWhitelist:
  - group: ""
    kind: Namespace       # 添加 Namespace
  - group: networking.k8s.io
    kind: IngressClass    # 添加 IngressClass
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
  # ... 其他資源
```

**預防措施**: 在添加新基礎設施組件前，確認 AppProject 已包含所需的資源類型

---

#### 8. cluster-bootstrap CRD 依賴問題（雞生蛋問題 #3）

**症狀**:
```
cluster-bootstrap: OutOfSync, Progressing
no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

**根本原因**: cluster-bootstrap Phase 2 資源（Certificates, Ingress）依賴尚未部署的 CRDs

**這是正常且預期的行為！**

**解決方案**（已內建於部署流程）:

1. **Phase 1** (Sync Wave: -10): Namespaces → 立即成功 ✅
2. **Phase 2** (Sync Wave: 10): Certificates, Ingress → 失敗（CRDs 不存在）⚠️
3. **手動同步基礎設施**: cert-manager, ingress-nginx → CRDs 安裝 ✅
4. **Phase 2 自動重試**: Certificates, Ingress → 成功 ✅

**驗證**:
```bash
# 基礎設施同步前
kubectl get application cluster-bootstrap -n argocd
# 預期: OutOfSync, Progressing ⚠️ 這是正常的!

# 基礎設施同步後
kubectl get application cluster-bootstrap -n argocd
# 預期: Synced, Healthy ✅
```

**關鍵設定**（已配置）:
```yaml
# argocd/bootstrap/manifests/*.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
    argocd.argoproj.io/sync-wave: "10"  # 延後部署
```

---

#### 9. TopoLVM Pod 無法調度（雞生蛋問題 #4）

**症狀**:
```
Vault pods: Pending
Events: 0/1 nodes are available: 1 Insufficient topolvm.io/capacity
實際節點容量: 240GB
需求: 45GB
```

**根本原因**: 使用 Scheduler Extender 模式但 kube-scheduler 未配置 extender endpoint

**診斷**:
```bash
# 檢查 Pod 資源請求
kubectl get pod vault-0 -n vault -o yaml | grep "topolvm.io/capacity"
# 錯誤: topolvm.io/capacity: "1"  (僅 1 byte!)

# 檢查節點 annotation
kubectl get node app-worker -o jsonpath='{.metadata.annotations}' | grep topolvm
# 正確: capacity.topolvm.io/00default: "257693843456"  (240GB)

# 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 舊模式: No resources found  ❌
# 新模式: 應該顯示 topolvm 容量 ✅
```

**解決方案**（已實施）:

改用 **Storage Capacity Tracking** 模式（`argocd/apps/infrastructure/topolvm/overlays/values.yaml`）:

```yaml
scheduler:
  enabled: false  # 禁用 scheduler extender

controller:
  storageCapacityTracking:
    enabled: true  # 啟用 Storage Capacity Tracking

webhook:
  podMutatingWebhook:
    enabled: false  # 不需要 pod webhook
```

**重新部署後驗證**:
```bash
# 1. 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 預期: 應該看到 topolvm-provisioner 的容量資源

# 2. 檢查 topolvm-scheduler DaemonSet 不應存在
kubectl get daemonset -n kube-system topolvm-scheduler
# 預期: Error from server (NotFound)  ✅

# 3. 刪除舊 Vault pods 讓它們重建（清除舊 webhook mutations）
kubectl delete pod -n vault --all

# 4. 檢查新 pods 是否成功調度
kubectl get pods -n vault -o wide
# 預期: Running 狀態，調度到 app-worker
```

**為什麼這個方案更好**:
- ✅ Kubernetes 原生功能（1.21+ GA）
- ✅ 無需修改 kube-scheduler 配置
- ✅ 自動容量追蹤和更新
- ✅ 更簡單、更可靠的調度機制

---

#### 11. Ingress-Nginx LoadBalancer 無法分配 IP

**症狀**:
- ingress-nginx-controller 服務 EXTERNAL-IP 顯示 `<pending>`
- 無法訪問 https://argocd.detectviz.internal
- curl 連接被拒絕 (Connection refused)
- 所有通過 Ingress 暴露的服務都無法訪問

**根本原因**:

1. **MetalLB IP 池配置不完整**: IP 池缺少 `192.168.0.10`
   ```yaml
   # 錯誤配置
   spec:
     addresses:
       - 192.168.0.200-192.168.0.220  # 缺少 .10
   ```

2. **使用 deprecated `spec.loadBalancerIP` 欄位**: 與 MetalLB 註解 `metallb.universe.tf/loadBalancerIPs` 衝突
   ```
   MetalLB 錯誤: service can not have both metallb.universe.tf/loadBalancerIPs and svc.Spec.LoadBalancerIP
   ```

3. **`externalTrafficPolicy: Local` 導致健康檢查失敗**: MetalLB speaker 宣告 IP 後立即撤回
   ```
   MetalLB 日誌:
   "service has IP, announcing" ips=["192.168.0.10"]
   "withdrawing service announcement" reason="noIPAllocated"
   ```

**診斷步驟**:

```bash
# 1. 檢查服務狀態
kubectl get svc ingress-nginx-controller -n ingress-nginx
# 症狀: EXTERNAL-IP = <pending>

# 2. 檢查 MetalLB IP 池
kubectl get ipaddresspool -n metallb-system default-pool -o yaml
# 檢查是否包含 192.168.0.10

# 3. 檢查 MetalLB speaker 日誌
kubectl logs -n metallb-system -l component=speaker --tail=50
# 尋找 "withdrawing service announcement" 或其他錯誤

# 4. 檢查服務配置衝突
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml | grep -E "loadBalancerIP|loadBalancerIPs"
# 檢查是否同時使用了 spec.loadBalancerIP 和註解
```

**解決方案**:

1. **添加 `192.168.0.10/32` 到 MetalLB IPAddressPool**:

   編輯 `argocd/apps/infrastructure/metallb/overlays/ipaddresspool.yaml`:
   ```yaml
   apiVersion: metallb.io/v1beta1
   kind: IPAddressPool
   metadata:
     name: default-pool
     namespace: metallb-system
   spec:
     addresses:
       - 192.168.0.10/32  # ✅ 添加 Ingress Controller VIP
       - 192.168.0.200-192.168.0.220  # 動態 IP 池
   ```

2. **移除 deprecated `spec.loadBalancerIP` 欄位**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/ingress-nginx-service.yaml`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: ingress-nginx-controller
     namespace: ingress-nginx
   spec:
     type: LoadBalancer
     # ❌ 移除這一行:
     # loadBalancerIP: 192.168.0.10
   ```

3. **使用 `externalTrafficPolicy: Cluster` 模式**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/ingress-nginx-service.yaml`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: ingress-nginx-controller
     namespace: ingress-nginx
   spec:
     type: LoadBalancer
     externalTrafficPolicy: Cluster  # ✅ 改為 Cluster 模式
     ports:
       - name: http
         port: 80
         protocol: TCP
         targetPort: http
       - name: https
         port: 443
         protocol: TCP
         targetPort: https
     selector:
       app.kubernetes.io/name: ingress-nginx
       app.kubernetes.io/instance: ingress-nginx
       app.kubernetes.io/component: controller
   ```

4. **確保 Helm values.yaml 配置一致**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/values.yaml`:
   ```yaml
   ingress-nginx:
     controller:
       service:
         enabled: true
         type: LoadBalancer
         externalTrafficPolicy: Cluster  # 與 patch 一致
   ```

5. **通過 Strategic Merge Patch 正確配置服務**:

   確保 `argocd/apps/infrastructure/ingress-nginx/overlays/kustomization.yaml` 包含:
   ```yaml
   patchesStrategicMerge:
     - ingress-nginx-service.yaml  # 明確的服務配置
   ```

**驗證修復**:

```bash
# 1. 同步 MetalLB 配置
kubectl apply -k argocd/apps/infrastructure/metallb/overlays/

# 2. 同步 Ingress-Nginx 配置
kubectl apply -k argocd/apps/infrastructure/ingress-nginx/overlays/

# 3. 等待服務重新創建
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx

# 4. 檢查 EXTERNAL-IP
kubectl get svc ingress-nginx-controller -n ingress-nginx
# 預期: EXTERNAL-IP = 192.168.0.10

# 5. 檢查 Ingress 資源
kubectl get ingress -n argocd argocd-server
# 預期: ADDRESS = 192.168.0.10

# 6. 測試 HTTPS 連接
curl -k -I https://argocd.detectviz.internal
# 預期: HTTP/2 307 (ArgoCD 重定向)

# 7. 檢查 MetalLB speaker 日誌
kubectl logs -n metallb-system -l component=speaker --tail=20
# 預期: "service has IP, announcing" 且沒有 "withdrawing" 訊息
```

**externalTrafficPolicy 模式對比**:

| 特性 | Local | Cluster |
|-----|-------|---------|
| 保留源 IP | ✅ 是 | ❌ 否 (SNAT) |
| 負載均衡 | 僅本地 Pod | 全集群 Pod |
| 健康檢查 | 需要 healthCheckNodePort | 不需要 |
| MetalLB 相容性 | ⚠️ 需要健康檢查通過 | ✅ 無額外要求 |
| 適用場景 | 生產環境 (需要源 IP) | 測試/開發環境 |

**為何選擇 Cluster 模式**:
- ✅ 避免 MetalLB L2 模式下的健康檢查問題
- ✅ 更簡單的配置,無需額外的健康檢查設置
- ⚠️ 缺點: 無法保留客戶端源 IP (對於 Ingress 通常不重要)

**相關文件**:
- `ingress-nginx-loadbalancer-fix.md` - 完整修復過程和技術洞察
- Commits:
  - `bbab4f2` - "fix: Add 192.168.0.10 to MetalLB IP pool"
  - `16bb52d` - "fix: Remove deprecated loadBalancerIP field"
  - `8bafac7` - "fix: Configure externalTrafficPolicy=Cluster"
  - `959332d` - "fix: Re-add ingress-nginx-service.yaml with correct config"

**預期結果**:
- ✅ EXTERNAL-IP: 192.168.0.10 成功分配
- ✅ HTTPS 正常訪問: https://argocd.detectviz.internal
- ✅ MetalLB 穩定運行,無 IP 撤回問題
- ✅ 所有 Ingress 資源正常工作

---

#### 10. MTU 問題

**問題**: 設定 MTU 9000 後無法連線或封包丟失

**原因**: 網卡、交換機或線材不支援巨型幀（Jumbo Frames）

**診斷步驟**:

```bash
# 1. 測試標準 MTU (1472 bytes payload + 28 bytes header = 1500 bytes)
ping -c 3 -M do -s 1472 192.168.0.11
# 預期: 成功

# 2. 測試巨型幀 MTU (8972 bytes payload + 28 bytes header = 9000 bytes)
ping -c 3 -M do -s 8972 192.168.0.11
# 如果失敗，表示路徑中有設備不支援 MTU 9000

# 3. 檢查 Proxmox 網卡最大支援
ip link show enp4s0
# 查看 "mtu" 欄位的最大值

# 4. 檢查所有 VM 的 MTU
ansible all -i ansible/inventory.ini -m shell -a "ip link show | grep mtu"
```

**解決方案**:

```bash
# 方案 A: 改回 MTU 1500（建議）
# 1. 修改 terraform/terraform.tfvars
#    proxmox_mtu = 1500
# 2. 修改 Proxmox /etc/network/interfaces
#    mtu 1500
# 3. 重啟網路
systemctl restart networking

# 方案 B: 逐步提升 MTU 找出最大支援值
# 測試不同的 MTU 值
ping -c 3 -M do -s 1972 192.168.0.11  # 2000 MTU
ping -c 3 -M do -s 3972 192.168.0.11  # 4000 MTU
ping -c 3 -M do -s 7972 192.168.0.11  # 8000 MTU
# 找出可用的最大值後設定

# 重新配置 VM 網路
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags network
```

**注意事項**:
- MTU 9000 需要**整條路徑**（Proxmox 網卡→交換機→VM 網卡）都支援
- 一般家用網卡和交換機只支援 MTU 1500
- 企業級 NIC 和交換機通常支援 MTU 9000
- 對於小型 Kubernetes 集群，MTU 1500 已足夠，不會有明顯效能差異

---

### 清理與重新部署

#### 清理失敗的 VM 部署

如果 Terraform 部署中途失敗：

```bash
cd terraform/
./cleanup-failed-vms.sh
```

此腳本將：
- 檢查並清理 Terraform 狀態
- 提供手動清理 Proxmox VM 的詳細指令

#### 完全重新部署

如果需要從頭開始整個集群部署：

```bash
cd terraform/
./cleanup-and-redeploy.sh
```

此腳本將：
- 自動銷毀所有現有資源
- 重新初始化並部署新基礎設施
- 適用於開發測試或重大配置變更

#### 手動清理步驟

如果自動化腳本無法使用：

1. **銷毀 Terraform 資源**:
   ```bash
   cd terraform/
   terraform destroy -auto-approve
   ```

2. **手動刪除 Proxmox VM**:
   ```bash
   # 在 Proxmox 上執行
   qm stop 111 && qm destroy 111
   qm stop 112 && qm destroy 112
   qm stop 113 && qm destroy 113
   qm stop 114 && qm destroy 114
   ```

3. **清理 Terraform 狀態**:
   ```bash
   rm -rf .terraform/
   rm terraform.tfstate*
   ```

4. **清理 Ansible 生成的文件**:
   ```bash
   rm -rf ansible/kubeconfig/
   rm ansible/inventory.ini
   ```

5. **重置 Proxmox 網路**（如需要）:
   ```bash
   # 在 Proxmox 上執行
   systemctl restart networking
   ```

---

### 診斷工具

#### 網路診斷

```bash
# 執行完整網路驗證
./scripts/validate-dual-network.sh

# 分段驗證
./scripts/validate-dual-network.sh --proxmox
./scripts/validate-dual-network.sh --vms
./scripts/validate-dual-network.sh --dns
./scripts/validate-dual-network.sh --connectivity
```

#### 集群診斷

```bash
# 檢查集群健康狀態
./scripts/health-check.sh

# 檢查 DNS
./scripts/test-cluster-dns.sh

# 診斷特定節點網路問題
./scripts/diagnose-vm1-network.sh
```

---

### 參考文檔

- **網路規劃**: `docs/infrastructure/00-planning/configuration-network.md`
- **域名配置**: `docs/infrastructure/00-planning/configuration-domain.md`
- **儲存規劃**: `docs/infrastructure/00-planning/configuration-storage.md`
- **Proxmox 配置**: `docs/infrastructure/02-proxmox/`
- **Terraform 文檔**: `terraform/README.md`
- **Ansible 文檔**: `ansible/README.md`

---

> [!IMPORTANT]
> **生產環境注意事項**:
> - 定期備份 Vault 金鑰 (`vault-keys.json`)
> - 定期備份 kubeconfig (`ansible/kubeconfig/admin.conf`)
> - 定期備份 Terraform 狀態 (`terraform/terraform.tfstate`)
> - 監控磁碟空間和網路流量
> - 定期更新 Kubernetes 版本和應用組件

> [!TIP]
> **效能優化建議**:
> - **MTU 設定**: 預設使用 1500，僅在確認硬體支援時才啟用 MTU 9000（巨型幀）
> - **rp_filter**: 使用 `rp_filter = 2` (寬鬆模式) 以支援非對稱路由
> - **sysctl 參數**: 定期檢查參數是否正確應用
> - **雙網路架構**: 使用內部集群網路 (vmbr1) 進行 Kubernetes 節點間通訊以提升效能
> - **MTU 測試**: 使用 `ping -M do -s <size>` 測試路徑最大 MTU
