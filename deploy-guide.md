# DetectViz GitOps 部署指令

**基於架構**: `README.md` (4 VM 混合負載模型)

---

### 前置作業

1. **設定 Proxmox Host 網路**: 參考 `docs/infrastructure/networking/network-info.md` 的「Proxmox 手動網路配置」章節
2. **準備 Ubuntu 22.04 範本**: 參考 `docs/infrastructure/proxmox/installation.md`
3. **準備 SSH 金鑰**: `~/.ssh/id_rsa.pub` 用於 Terraform/Ansible

---

### [P1] Phase 1: Terraform 基礎設施佈建

**目標**：建立 `README.md` 中定義的 4 台 VM。

**執行:**

```bash
cd terraform/
terraform init
terraform apply -auto-approve
```

---

### [P2 & P3] Phase 2: Ansible 完全自動化部署

**執行:**
```bash
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml
```

---

### [P4] Phase 3: GitOps 自動同步基礎設施

**驗證:**
```bash
export KUBECONFIG=$(pwd)/kubeconfig/admin.conf
argocd app list
kubectl get pods -n metallb-system
kubectl get pods -n topolvm-system
kubectl get pods -n ingress-nginx
```

---

### [P5] Phase 4: 手動介入 - Vault 初始化

**執行:**
```bash
kubectl get pods -n vault --watch
kubectl exec -n vault statefulset/vault -c vault -- vault operator init > vault.init
# 取得 Unseal Key 和 Root Token，然後解封 Vault
kubectl exec -n vault statefulset/vault -c vault -- vault operator unseal "$VAULT_UNSEAL_KEY"
```

---

### [P5] Phase 5: 手動同步 P5 應用

**執行:**
1. 登入 ArgoCD UI
2. 找到 `apps-appset` 應用
3. 點擊 **Sync** 按鈕

### [最終驗證] Phase 6: 驗證部署

**執行:**
```bash
kubectl get pods -A -o wide
```
