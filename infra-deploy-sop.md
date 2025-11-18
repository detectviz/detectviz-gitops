# DetectViz GitOps Infrastructure Deployment Guide

**基於架構**: `README.md` (4 VM 混合負載模型 + 雙網路架構)

本文件提供完整的部署流程，從 Proxmox 網路配置到 Kubernetes 集群啟動的所有步驟。故障排除紀錄在 `infra-deploy-troubleshooting.md` 中。

---

## 目錄

- [Phase 0: 前置作業](#phase-0-前置作業)
  - [1. Proxmox 雙網路配置](#1-proxmox-雙網路配置)
  - [2. DNS 伺服器配置](#2-dns-伺服器配置)
  - [3. VM 模板準備](#3-vm-模板準備)
  - [4. SSH 金鑰準備](#4-ssh-金鑰準備)
- [Phase 1: Terraform 基礎設施佈建](#phase-1-terraform-基礎設施佈建)
- [Phase 2: 網路配置驗證](#phase-2-網路配置驗證)
- [Phase 3: Ansible 自動化部署](#phase-3-ansible-自動化部署)
- [Phase 4: GitOps 基礎設施同步](#phase-4-gitops-基礎設施同步)
- [Phase 5: Vault 初始化](#phase-5-vault-初始化)

---

## Phase 0: 前置作業

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

## Phase 1: Terraform 基礎設施佈建

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

## Phase 2: 網路配置驗證

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

## Phase 3: Ansible 自動化部署

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

## Phase 4: GitOps 基礎設施同步

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
##### 以下手動步驟僅供參考和故障排除使用

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
> [!NOTE]
> 在執行刷新前，請先確認 `argocd/root-argocd-app.yaml` 中 `spec.project` 為 `platform-bootstrap`，確保根 Application 受正確 AppProject 權限控管。
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

> [!IMPORTANT]
> `infra-appset` 使用 Git Generator 追蹤 `argocd/apps/infrastructure/*`，因此每個元件根目錄都需要有 `kustomization.yaml` 將資源指向 `overlays/`。若缺少此入口，Argo CD 會只看到空目錄而無法生成 Application。提交任何新的基礎設施服務前，請執行 `kustomize build --enable-helm argocd/apps/infrastructure/<component>`，確認根層入口確實載入 overlay（若環境無法下載 Helm chart，請在變更紀錄中附上等效驗證）。

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

> [!TIP]
> 如果 ApplicationSet 沒有自動生成上述 Application，請先在 Repo 中檢查對應的 `argocd/apps/infrastructure/<component>/kustomization.yaml` 是否仍引用 `resources: - overlays`。修正後重新執行 `kubectl patch application root ...` 觸發 `root-argocd-app` Refresh，即可重新載入最新的 infra-appset 配置。

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

## Phase 5: Vault 初始化

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

## Phase 5.5: Vault Kubernetes Auth 配置

**目標**: 配置 Vault Kubernetes Auth 和 KV Secrets Engine，為應用部署做準備

**前置條件**: Phase 5 完成，Vault 已初始化並解封

#### 5.5.1 啟用 KV v2 Secrets Engine

```bash
# 設置 Vault Token
export VAULT_TOKEN=$(cat vault-keys.json | jq -r '.root_token')

# 啟用 KV v2 secrets engine
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
  vault secrets enable -version=2 -path=secret kv

# 預期輸出:
# Success! Enabled the kv secrets engine at: secret/
```

---

#### 5.5.2 啟用並配置 Kubernetes Auth Method

```bash
# 啟用 Kubernetes auth method
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
  vault auth enable kubernetes

# 配置 Kubernetes auth
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN sh -c \
  'vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token'

# 預期輸出:
# Success! Enabled kubernetes auth method at: kubernetes/
# Success! Data written to: auth/kubernetes/config
```

---

#### 5.5.3 創建 Vault Policy 給 External Secrets Operator

```bash
# 創建 policy 允許 ESO 讀取所有 secrets
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN sh -c \
  'cat <<EOF | vault policy write external-secrets -
path "secret/data/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF'

# 預期輸出:
# Success! Uploaded policy: external-secrets
```

---

#### 5.5.4 創建 Kubernetes Auth Role

```bash
# 創建 role 綁定 ServiceAccount 和 policy
kubectl exec -n vault vault-0 -- env VAULT_TOKEN=$VAULT_TOKEN \
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets-system \
    policies=external-secrets \
    ttl=24h

# 預期輸出:
# Success! Data written to: auth/kubernetes/role/external-secrets
```

---

#### 5.5.5 部署 ClusterSecretStore

```bash
# 手動創建 ClusterSecretStore (如果 ArgoCD 同步失敗)
kubectl apply -f argocd/apps/infrastructure/external-secrets-operator/overlays/cluster-secret-store.yaml

# 驗證 ClusterSecretStore 狀態
kubectl get clustersecretstore vault-backend -o yaml | grep -A5 "status:"

# 預期輸出:
# status:
#   capabilities: ReadWrite
#   conditions:
#   - message: store validated
#     reason: Valid
#     status: "True"
#     type: Ready
```

---

**完成 Phase 5.5 後**:
- ✅ Vault Kubernetes Auth 已啟用並配置
- ✅ KV v2 Secrets Engine 已啟用在 `secret/` 路徑
- ✅ External Secrets Operator 可以透過 Kubernetes Auth 訪問 Vault
- ✅ ClusterSecretStore `vault-backend` 已就緒

**下一步**: 進入 `app-deploy-sop.md` Phase 6.0 初始化應用 secrets