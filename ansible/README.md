# ansible

使用 Ansible 自動化部署高可用 Kubernetes 集群（3 Master + 2 Worker 節點）。

---

## 架構概覽

本倉庫使用 Ansible 自動化部署高可用 Kubernetes 集群，包含完整的集群初始化、節點配置、網路設定和驗證流程。

### 核心功能
- 集群初始化與 kubeadm 配置
- Master/Worker 節點批量部署
- Calico CNI 網路插件安裝
- 高可用控制平面設置
- 安全配置與 TLS 證書管理
- 集群健康檢查與驗證

### 部署範圍
- 3 個控制平面節點（etcd + API Server）
- 2 個工作節點（kubelet + kube-proxy）
- 高可用 VIP 配置
- Calico CNI 網路插件
- NGINX Ingress Controller
- containerd 容器運行時

### 技術棧
- Ansible >= 2.9.0 - 配置管理工具
- Kubernetes v1.32.9 - 容器編排平台
- Calico v3.27.3 - CNI 網路插件
- containerd - 容器運行時
- etcd - 分佈式鍵值存儲

---

## 快速開始

### 前置需求
- 控制節點: Ubuntu/macOS，安裝 Ansible >= 2.9.0
- 目標節點: Ubuntu 22.04 LTS，已配置 SSH 訪問
- 網路: 所有節點間網路互通
- 資源: 每節點至少 2 CPU、2GB RAM、20GB 儲存
- 上游依賴: terraform 已執行完成，VM 已就緒

### 基本部署

```bash
# 1. 進入 ansible 目錄
cd ansible

# 2. 編輯主機清單（或從 Terraform 輸出自動生成）
vim inventory.ini

# 3. 執行完整部署
ansible-playbook -i inventory.ini deploy-cluster.yml

# 4. 驗證集群狀態
./validate-cluster.sh
```

### 重置並重新部署

如果需要完全重置現有集群並重新部署：

```bash
ansible-playbook -i inventory.ini deploy-cluster.yml \
  -e reset_cluster=true \
  -e force_rejoin=true
```

---

## 檔案結構

```bash
ansible/
├── deploy-cluster.yml              # 主要部署腳本
├── inventory.ini                   # 節點清單配置
├── ansible.cfg                     # Ansible 運行配置
├── docs/                           # 相關文檔
│   └── best-practices.md           # Ansible 最佳實踐與規格
├── group_vars/
│   └── all.yml                     # 全域變數定義
├── roles/                          # 角色定義
│   ├── common/                     # 系統準備角色
│   │   ├── tasks/
│   │   │   └── main.yml            # 系統配置任務
│   │   └── handlers/
│   │       └── main.yml            # 服務重啟處理
│   ├── master/                     # 控制平面角色
│   │   ├── tasks/
│   │   │   └── main.yml            # Master 初始化任務
│   │   └── templates/
│   │       └── kubeadm-config.yaml.j2 # kubeadm 配置模板
│   └── worker/                     # Worker 節點角色
│       └── tasks/
│           └── main.yml            # Worker 加入任務
├── validate-cluster.sh             # 集群驗證腳本
├── kubeconfig/                     # Kubeconfig 儲存目錄
│   └── admin.conf                  # 自動產生的管理配置
└── README.md                       # 本文檔
```

---

## 配置說明

### 主機清單（inventory.ini）

定義集群節點資訊：

```ini
[masters]
master-1 ansible_host=192.168.0.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
master-2 ansible_host=192.168.0.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
master-3 ansible_host=192.168.0.13 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[workers]
app ansible_host=192.168.0.14 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
ai ansible_host=192.168.0.15 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### 全域變數（group_vars/all.yml）

控制部署行為的關鍵參數：

```yaml
# 集群基本資訊
cluster_name: detectviz
kubernetes_version: "1.32.0"
kubernetes_package_version: ""  # 留空使用最新 1.32.x 版本

# 網路配置
pod_network_cidr: "10.244.0.0/16"      # Pod IP 範圍
service_cidr: "10.96.0.0/12"           # Service IP 範圍
control_plane_endpoint: "k8s-api.detectviz.internal:6443"  # 高可用端點

# 容器運行時
containerd_sandbox_image: "registry.k8s.io/pause:3.9"

# CNI 網路插件
calico_manifest_url: "https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml"

# 部署控制開關
reset_cluster: false   # 是否重置現有集群
force_rejoin: false    # 是否強制 worker 重新加入
```

---

## 部署流程

### 階段 1: DNS 和網路配置（約 30 秒）
- 配置 /etc/hosts 主機解析
- 設定 DNS resolver
- 確保節點間網路連通

### 階段 2: 系統準備（約 5-10 分鐘）
- 停止舊服務（如果重置）
- 清理舊配置和資料（如果重置）
- 安裝基礎依賴套件
- 禁用 Swap
- 設定核心模組（overlay, br_netfilter）
- 配置系統參數（sysctl）
- 安裝 containerd 容器運行時
- 安裝 kubelet, kubeadm, kubectl

### 階段 3: Master 節點初始化（約 3-5 分鐘）
- Master-1（第一個控制平面節點）:
  - 執行 kubeadm init
  - 設定 kubeconfig
  - 安裝 Calico CNI 網路插件
  - 產生 join token（控制平面和 worker）
  - 重啟 containerd 和 kubelet（確保 CNI）
- Master-2/3: 加入控制平面

### 階段 4: Worker 節點加入（約 2-3 分鐘）
- 檢查節點當前狀態
- 重置節點（如果需要）
- 確保 containerd 運行
- 執行 kubeadm join
- 等待 kubelet 健康檢查通過

### 階段 5: NGINX Ingress Controller 安裝（約 2-3 分鐘）
- 安裝 NGINX Ingress Controller
- 等待控制器部署就緒
- 驗證 Service 和 Pod 狀態
- 創建測試 Ingress 資源

### 階段 6: 驗證部署（約 2-5 分鐘）
- 等待 Calico pods 就緒
- 等待所有節點進入 Ready 狀態
- 顯示集群狀態摘要

---

## 進階操作

### 單獨安裝 NGINX Ingress Controller

如果 Kubernetes 集群已經存在，可以單獨安裝 NGINX Ingress Controller：

```bash
# 進入 ansible 目錄
cd ansible

# 安裝 NGINX Ingress Controller
ansible-playbook -i inventory.ini install-ingress.yml
```

此 playbook 會：
- 檢查集群連線狀態
- 安裝 NGINX Ingress Controller
- 配置 LoadBalancer service (固定 IP: 192.168.0.10)
- 驗證安裝結果

### 部分節點操作

#### 只處理 Master 節點
```bash
ansible-playbook -i inventory.ini deploy-cluster.yml --limit masters
```

#### 只處理 Worker 節點
```bash
ansible-playbook -i inventory.ini deploy-cluster.yml --limit workers
```

#### 只處理特定節點
```bash
ansible-playbook -i inventory.ini deploy-cluster.yml --limit master-1
```

### 使用標籤控制

#### 只執行 DNS 配置
```bash
ansible-playbook -i inventory.ini deploy-cluster.yml --tags dns
```

#### 只執行重置操作
```bash
ansible-playbook -i inventory.ini deploy-cluster.yml --tags reset
```

### 乾跑模式（檢查不執行）

```bash
# 檢查會執行哪些任務
ansible-playbook -i inventory.ini deploy-cluster.yml --list-tasks

# 語法檢查
ansible-playbook -i inventory.ini deploy-cluster.yml --syntax-check

# 檢查模式（不實際執行）
ansible-playbook -i inventory.ini deploy-cluster.yml --check
```

### 詳細輸出

```bash
# 顯示詳細輸出
ansible-playbook -i inventory.ini deploy-cluster.yml -v

# 更詳細的輸出
ansible-playbook -i inventory.ini deploy-cluster.yml -vv

# 最詳細的除錯輸出
ansible-playbook -i inventory.ini deploy-cluster.yml -vvv
```

### 使用 kubeconfig

部署完成後，kubeconfig 會自動下載到 `kubeconfig/admin.conf`：

```bash
# 在控制節點上使用
export KUBECONFIG=./kubeconfig/admin.conf

# 查看集群
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

---

## 故障排除

### 常見問題

#### 1. SSH 連接失敗

症狀:
```bash
UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh", ...}
```

解決方案:
```bash
# 檢查 SSH 連接
ssh -i ~/.ssh/id_rsa ubuntu@192.168.0.11

# 確認 SSH 金鑰權限
chmod 600 ~/.ssh/id_rsa

# 測試 Ansible 連接
ansible -i inventory.ini all -m ping
```

#### 2. 節點狀態 NotReady

症狀:
```bash
NAME       STATUS     ROLES           AGE   VERSION
master-1   NotReady   control-plane   5m    v1.32.9
```

解決方案:
```bash
# 在受影響的節點上檢查
kubectl get pods -n kube-system  # 檢查 CNI pods
systemctl status kubelet         # 檢查 kubelet 服務
systemctl status containerd      # 檢查 containerd

# 查看日誌
journalctl -u kubelet -f
journalctl -u containerd -f

# 重啟服務
systemctl restart containerd
systemctl restart kubelet
```

#### 3. Token 過期

症狀:
```
error execution phase preflight: invalid token
```

解決方案:
```bash
# 在 master-1 上產生新 token
kubeadm token create --print-join-command

# 或重新執行部署（會自動產生新 token）
ansible-playbook -i inventory.ini deploy-cluster.yml -e force_rejoin=true
```

---

## 效能與時間預估

### 部署時間（依網路和硬體而異）

| 階段 | 預估時間 | 說明 |
|------|----------|------|
| DNS 配置 | 30 秒 | 所有節點同時執行 |
| 系統準備 | 5-10 分鐘 | 下載套件和容器映像 |
| Master 初始化 | 3-5 分鐘 | 第一個 Master 較慢 |
| Worker 加入 | 2-3 分鐘 | 每個節點約 1 分鐘 |
| NGINX Ingress | 2-3 分鐘 | 安裝和配置控制器 |
| 驗證就緒 | 2-5 分鐘 | 等待所有 pods 啟動 |
| 總計 | 約 14-26 分鐘 | 視網路速度而定 |

### 資源使用

#### Master 節點（每個）
- CPU: 2 核心（建議 4 核心）
- RAM: 2GB（建議 4GB）
- 磁碟: 20GB（建議 50GB）

#### Worker 節點（每個）
- CPU: 2 核心（建議 4 核心）
- RAM: 2GB（建議 8GB+，依工作負載）
- 磁碟: 20GB（建議 100GB+）

---

## 參考資源

### Kubernetes 文檔
- [Kubernetes 官方文檔](https://kubernetes.io/docs/)
- [kubeadm 文檔](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [kubectl 文檔](https://kubernetes.io/docs/reference/kubectl/)

### 網路插件
- [Calico 文檔](https://docs.projectcalico.org/)
- [Calico Kubernetes 文檔](https://docs.projectcalico.org/getting-started/kubernetes/)

### Ansible 文檔
- [Ansible 文檔](https://docs.ansible.com/)
- [Ansible for Kubernetes](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)

### 容器運行時
- [containerd 文檔](https://containerd.io/docs/)
- [CRI 文檔](https://github.com/kubernetes/cri-api)

---

## 相關倉庫

| 倉庫 | 描述 | 依賴關係 |
|------|------|----------|
| [infra-deployment](https://github.com/detectviz/infra-deployment) | 中央編排與部署流程 | 調度 ansible |
| [terraform](https://github.com/detectviz/terraform) | 基礎設施即程式碼 | ansible 使用其輸出作為 inventory |
| [kubernetes](https://github.com/detectviz/kubernetes) | 集群級別配置 | 部署在 ansible 之上 |
| [gitops-argocd](https://github.com/detectviz/gitops-argocd) | GitOps 應用交付 | 最終應用部署與管理 |
| [observability-stack](https://github.com/detectviz/observability-stack) | 可觀測性外部組件 | 基礎設施監控 |

> 📌 **完整架構說明**: 請參閱 [https://github.com/detectviz/infra-deployment/blob/main/docs/ARCHITECTURE.md](https://github.com/detectviz/infra-deployment/blob/main/docs/ARCHITECTURE.md) - 五倉庫職責劃分與資料流總覽

---

## 維護資訊

### 聯絡方式
- 維護者: Detectviz Team
- 問題回報: [GitHub Issues](https://github.com/detectviz/ansible/issues)

### 版本資訊
- 本倉庫版本: v2.0.0
- Ansible 版本: >= 2.9.0
- Kubernetes 版本: v1.32.9
- Calico 版本: v3.27.3
- 相依倉庫:
  - infra-deployment >= v2.0.0
  - terraform >= v2.0.0
- 最後更新: 2025-10-25
