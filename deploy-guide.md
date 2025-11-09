# DetectViz GitOps 部署手冊 (新架構版)

**版本**: 2.0
**基於架構**: `README.md` (4 VM 混合負載模型)

本手冊遵循 `README.md` 定義的 P1 至 P5 部署流程，並進行了必要的順序調整（例如提前進行節點標籤），以確保工作負載能正確調度。

---

### Phase 0: Proxmox Host 與範本前置作業

在 P1 (Terraform) 開始之前，必須先準備好 Proxmox 宿主機環境。

#### 1. (關鍵) 修正 Proxmox Host 網路

我們之前診斷過，Proxmox Host 預設的 `rp_filter` = 2 會導致 VM ICMP reply 封包遺失。你必須先修正 PVE Host。

**設定檔 (PVE Host):** `ansible/roles/proxmox-host/tasks/main.yml`

```yaml
---
- name: (PVE Host) 修正 KVM 橋接網路的 rp_filter
  ansible.builtin.copy:
    dest: /etc/sysctl.d/98-pve-networking.conf
    content: |
      # 修正 Proxmox KVM/Bridge/Tap 網路封包遺失 (ICMP Reply)
      # 設為 1 (Loose Mode) 以允許橋接的非對稱路由
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.conf.default.rp_filter = 1
  notify: reload pve sysctl
```

**設定檔 (PVE Host):** `ansible/roles/proxmox-host/handlers/main.yml`

```yaml
---
- name: reload pve sysctl
  ansible.builtin.command: sysctl --system
```

**設定檔 (PVE Host):** `ansible/inventory.ini` (加入 PVE Host)

```ini
[pve_hosts]
# 填入你的 PVE Host IP 或 FQDN
proxmox.your-domain.com  ansible_user=root

[k8s_cluster:children]
masters
workers
# ... (k8s 節點)
```

**執行 (PVE Host):**

```bash
# 針對 PVE Host 執行此 Playbook
ansible-playbook -i ansible/inventory.ini setup-proxmox.yml
```

#### 2. 準備 Ubuntu 22.04 範本

根據 `README.md` 的「前置作業」，確保你的 Proxmox VM 範本 (`ubuntu-2204-template`) 已經：

*   安裝 `qemu-guest-agent` (並在 Proxmox VM 選項中啟用)。
*   啟用 Cloud-Init。

#### 3. 準備 SSH 金鑰

*   `~/.ssh/id_rsa.pub`：用於 Terraform 注入 VM 以便 Ansible 連線。
*   `~/.ssh/id_gitops` (新金鑰)：產生一組**專門給 ArgoCD** 讀取 Git 倉庫用的 SSH Key (請將公鑰 `id_gitops.pub` 加入你的 Git 倉庫 Deploy Key)。

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

**目標**：執行一個 Ansible Playbook，自動完成 K8s 初始化、節點標籤、ArgoCD 憑證注入和 ArgoCD 自身部署的所有步驟。

**執行:**

```bash
cd ansible/

# 執行 K8s 叢集部署
ansible-playbook -i inventory.ini deploy-cluster.yml
```

**完成後，你將擁有一個：**

*   完全運作的 Kubernetes 叢集。
*   已安裝 Calico CNI 和 Kube-VIP。
*   節點已根據 `README.md` 架構貼上標籤。
*   ArgoCD 已安裝，並已部署 `root-argocd-app.yaml`，開始自動同步 P3/P4 應用。

---

### [P4] Phase 3: GitOps 自動同步基礎設施

**目標**：ArgoCD 會自動偵測 `infra-appset.yaml`，並部署所有 P4 服務。

**驗證:**

```bash
# 取得 Kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig/admin.conf

# 檢查 ArgoCD 狀態
argocd app list
# (等待所有 Apps 變為 Synced 和 Healthy)

# 驗證 P4 服務
kubectl get pods -n metallb-system
kubectl get pods -n topolvm-system
kubectl get pods -n ingress-nginx
```

---

### [P5] Phase 4: 手動介入 - Vault 初始化

**目標**：在部署 P5 應用之前，手動初始化和解封 Vault。

**執行 (手動):**

```bash
# 1. 等待 Vault Pod (應在 app-worker 節點) 進入 Running
kubectl get pods -n vault --watch

# 2. 初始化 Vault
kubectl exec -n vault statefulset/vault -c vault -- vault operator init > vault.init

# 3. 取得金鑰和 Token
VAULT_UNSEAL_KEY=$(grep 'Unseal Key 1:' vault.init | awk '{print $NF}')
VAULT_ROOT_TOKEN=$(grep 'Initial Root Token:' vault.init | awk '{print $NF}')

# 4. 解封 Vault
kubectl exec -n vault statefulset/vault -c vault -- vault operator unseal "$VAULT_UNSEAL_KEY"

# 5. 登入 Vault
kubectl exec -n vault statefulset/vault -c vault -- vault login "$VAULT_ROOT_TOKEN"

# 6. 設定 Kubernetes Auth (供 ESO 使用)
# ... (vault auth enable kubernetes, etc.)
```

---

### [P5] Phase 5: 手動同步 P5 應用

**目標**：在 Vault 初始化完成後，手動觸發 P5 應用的同步。

**執行:**

1.  登入 ArgoCD UI。
2.  找到 `apps-appset` (或其下的所有 P5 應用)。
3.  點擊 **Sync** 按鈕。

---

### [最終驗證] Phase 6: 驗證工作負載調度

**目標**：驗證所有 P5 應用都已成功部署，並在 `README.md` 指定的節點上。

**執行 (驗證):**

```bash
kubectl get pods -A -o wide

# 預期輸出 (範例):
# NAMESPACE          NAME                              NODE
# ...
# vault              vault-0                           app-worker
# argocd             argocd-server-xxxx                app-worker
# ...
# prometheus         prometheus-0                      master-1
# loki               loki-0                            master-3
# mimir              mimir-0                           master-2
# grafana            grafana-xxxx                      app-worker
# keycloak           keycloak-xxxx                     app-worker
# ...
```
