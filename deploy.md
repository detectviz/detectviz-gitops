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
    mtu 9000

# 內部集群網路橋接器 (vmbr1 - enp5s0)
auto vmbr1
iface vmbr1 inet static
    address 10.0.0.2/24
    bridge-ports enp5s0
    bridge-stp off
    bridge-fd 0
    mtu 9000
```

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
- vmbr0: 192.168.0.2/24, MTU 9000
- vmbr1: 10.0.0.2/24, MTU 9000
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

# 檢查關鍵配置
grep -E "proxmox_bridge|k8s_overlay_bridge|master_internal_ips|worker_internal_ips|cluster_domain" terraform.tfvars
```

**預期輸出**：
```
proxmox_bridge     = "vmbr0"
k8s_overlay_bridge = "vmbr1"
master_internal_ips = ["10.0.0.11", "10.0.0.12", "10.0.0.13"]
worker_internal_ips = ["10.0.0.14"]
cluster_domain      = "cluster.internal"
```

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
```

#### 1.4 檢查生成的文件

```bash
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
ssh ubuntu@192.168.0.11 'ip addr show ens18'
ssh ubuntu@192.168.0.11 'ip addr show ens19'

# 檢查 MTU 設定
ssh ubuntu@192.168.0.11 'ip link show ens18 | grep mtu'
ssh ubuntu@192.168.0.11 'ip link show ens19 | grep mtu'

# 測試內部網路連通性
ssh ubuntu@192.168.0.11 'ping -c 3 10.0.0.14'

# 測試 DNS 解析
ssh ubuntu@192.168.0.11 'getent hosts master-1.detectviz.internal'
ssh ubuntu@192.168.0.11 'getent hosts master-1.cluster.internal'
```

**預期結果**：
- ✅ 每個 VM 有兩個網路介面 (ens18, ens19)
- ✅ MTU 都設定為 9000
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

**部署內容**：
1. **Common Role**: 系統初始化、套件安裝
2. **Network Role**:
   - 配置雙網路介面 (ens18 + ens19)
   - 設定 /etc/hosts (detectviz.internal + cluster.internal)
   - 配置 sysctl 參數 (rp_filter=2, ip_forward=1)
3. **Master Role**: 初始化 Kubernetes 控制平面
4. **Worker Role**: 加入工作節點
5. **ArgoCD**: 安裝 GitOps 引擎

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

#### 4.4 驗證 ApplicationSet 同步

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

**問題**: 封包丟失或連線不穩定

**解決方案**:

```bash
# 測試 MTU
ping -c 3 -M do -s 8972 192.168.0.11

# 檢查所有介面 MTU
ansible all -i ansible/inventory.ini -m shell -a "ip link show | grep mtu"

# 重新配置
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags network
```

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
> - 確保所有節點和交換機支援 MTU 9000
> - 使用 `rp_filter = 2` (寬鬆模式) 以支援非對稱路由
> - 定期檢查 sysctl 參數是否正確應用
> - 使用內部集群網路 (vmbr1) 進行 Kubernetes 節點間通訊以提升效能
