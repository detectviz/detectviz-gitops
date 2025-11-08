# 技術堆疊與建置系統

## 核心技術棧

### 基礎設施層
- **Terraform** >= 1.5.0 - 基礎設施即程式碼，管理 Proxmox VM
- **Ansible** >= 2.15 - 配置管理與 Kubernetes 集群部署
- **Proxmox VE** 8.x - 虛擬化平台
- **Ubuntu** 22.04 LTS - 作業系統

### 容器與編排
- **Kubernetes** v1.32.0 - 容器編排平台
- **containerd** - 容器運行時
- **Calico** v3.27.3 - CNI 網路插件
- **kubeadm** - Kubernetes 集群初始化工具

### GitOps 與應用管理
- **Argo CD** >= 2.9 - GitOps 控制面
- **Kustomize** - Kubernetes 配置管理
- **Helm** - 套件管理器
- **ApplicationSet** - 多環境應用管理

### 安全與秘密管理
- **HashiCorp Vault** 0.28.0 - 秘密管理
- **External Secrets Operator** 0.10.5 - 秘密同步
- **cert-manager** - TLS 證書自動化

### 網路與儲存
- **MetalLB** - 負載均衡器
- **kube-vip** - 控制平面 VIP
- **TopoLVM** - 本地儲存管理
- **LVM** - 邏輯卷管理

## 常用指令

### Terraform 操作
```bash
# 初始化與部署
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -auto-approve

# 清理資源
terraform destroy -auto-approve

# 查看輸出
terraform output -json
```

### Ansible 操作
```bash
# 測試連線
ansible all -i inventory.ini -m ping

# 部署集群
ansible-playbook -i inventory.ini deploy-cluster.yml

# 重置並重新部署
ansible-playbook -i inventory.ini deploy-cluster.yml \
  -e reset_cluster=true -e force_rejoin=true

# 僅安裝 Ingress
ansible-playbook -i inventory.ini install-ingress.yml
```

### Kubernetes 管理
```bash
# 設定 kubeconfig
export KUBECONFIG=./ansible/kubeconfig/admin.conf

# 基本檢查
kubectl get nodes
kubectl get pods -A
kubectl cluster-info

# ArgoCD 管理
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
```

### 驗證腳本
```bash
# 集群驗證
./scripts/validation-check.sh --final
./scripts/health-check.sh

# DNS 測試
./scripts/test-cluster-dns.sh

# Pod 恢復測試
./scripts/test-pod-recovery.sh
```

### Vault 操作
```bash
# 初始化 Vault
kubectl exec -n vault statefulset/vault -c vault -- \
  vault operator init -key-shares=5 -key-threshold=3

# 解封 Vault
kubectl exec -n vault statefulset/vault -c vault -- \
  vault operator unseal <unseal-key>

# 登入 Vault
kubectl exec -n vault statefulset/vault -c vault -- \
  vault login <root-token>
```

## 建置與測試流程

### 完整部署流程
1. **Phase 1**: Terraform 建立 VM (15-20 分鐘)
2. **Phase 2**: Ansible 部署 Kubernetes (10-15 分鐘)
3. **Phase 3**: 安裝 ArgoCD (5 分鐘)
4. **Phase 4**: GitOps 應用同步 (10-15 分鐘)
5. **Phase 5**: Vault 初始化與配置 (5-10 分鐘)

### 驗證檢查點
- Terraform: `terraform output` 顯示所有節點資訊
- Ansible: 所有節點狀態為 `Ready`
- ArgoCD: 所有 Application 狀態為 `Synced`/`Healthy`
- Vault: 成功初始化並配置 Kubernetes Auth

## 配置檔案結構

### 關鍵配置檔案
- `terraform/terraform.tfvars` - Terraform 變數配置
- `ansible/inventory.ini` - Ansible 主機清單
- `ansible/group_vars/all.yml` - 全域變數
- `apps/*/overlays/kustomization.yaml` - Kustomize 配置
- `appsets/*.yaml` - ApplicationSet 定義