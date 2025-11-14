# DetectViz GitOps 部署指南

**基於架構**: `README.md` (4 VM 混合負載模型 + 雙網路架構)

本文件提供完整的部署流程，從 Proxmox 網路配置到 Kubernetes 集群啟動的所有步驟。

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
    size    = "250G"                   # 資料磁碟 (TopoLVM data-vg)
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

#### 1.5 檢查生成的文件

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
   - 配置 LVM Volume Groups (data-vg) 供 TopoLVM 使用
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

#### 4.5 驗證 ApplicationSet 同步

```bash
# 檢查 ApplicationSet
kubectl get applicationset -n argocd

# 檢查所有應用狀態
argocd app list

# 檢查基礎設施組件
kubectl get pods -n metallb-system
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
kubectl get pods -n external-secrets
```

**預期結果**：
- ✅ MetalLB 運行中 (LoadBalancer 支援)
- ✅ cert-manager 運行中 (TLS 證書管理)
- ✅ NGINX Ingress 運行中 (Ingress 控制器)
- ✅ External Secrets 運行中 (Secret 管理)

---

### Phase 5: Vault 初始化

**目標**: 手動初始化並解封 Hashicorp Vault

#### 5.1 等待 Vault Pod 就緒

```bash
kubectl get pods -n vault --watch
# 等待 vault-0, vault-1, vault-2 都處於 Running 狀態
# Ctrl+C 退出 watch
```

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

# 解封 vault-1
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_3

# 解封 vault-2
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_3
```

#### 5.4 驗證 Vault 狀態

```bash
# 檢查所有 Vault 實例
kubectl exec -n vault vault-0 -c vault -- vault status
kubectl exec -n vault vault-1 -c vault -- vault status
kubectl exec -n vault vault-2 -c vault -- vault status
```

**預期結果**: 所有實例顯示 `Sealed: false`

---

### Phase 6: 應用部署

**目標**: 同步觀測性堆疊與應用服務

#### 6.1 在 ArgoCD UI 手動同步應用

登入 ArgoCD UI，按以下順序同步應用：

1. **infrastructure/postgresql** - 資料庫
2. **observability/prometheus** - 指標收集
3. **observability/loki** - 日誌聚合
4. **observability/tempo** - 分散式追蹤
5. **observability/mimir** - 長期指標儲存
6. **observability/grafana** - 可視化

#### 6.2 或使用 CLI 同步

```bash
# 同步所有應用
argocd app sync --async infrastructure-postgresql
argocd app sync --async observability-prometheus
argocd app sync --async observability-loki
argocd app sync --async observability-tempo
argocd app sync --async observability-mimir
argocd app sync --async observability-grafana

# 監控同步狀態
argocd app list
watch argocd app list
```

#### 6.3 驗證應用部署

```bash
# 檢查 PostgreSQL
kubectl get pods -n infrastructure

# 檢查觀測性堆疊
kubectl get pods -n observability

# 檢查所有服務
kubectl get svc -A | grep LoadBalancer
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

#### 6. MTU 問題

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
