你好！身為你的程式夥伴，我詳細閱讀了你的 `README.md` 和現有的專案檔案。

你的 `README.md` 規劃了非常清晰的新架構，特別是 P1 到 P5 的部署流程 和 Master/Worker 節點的特定工作負載（例如 Prometheus on master-1, Argo CD on app-worker）。

你現有的 `deploy-guide.md` 已經過時，並且與 `README.md` 的新架構有幾個**關鍵衝突**：

1.  **CNI 不符：** `README.md` 指定 P2 使用 **Calico**，但舊指南 提到 Flannel。
2.  **GitOps 結構不符：** `README.md` 描述了 `infra-appset.yaml` 和 `apps-appset.yaml`，而你目前的 `argocd/appsets` 目錄 還是舊結構。
3.  **部署順序錯誤：** `README.md` 要求 P5 的應用 (如 Prometheus) 部署到特定節點。但舊指南 在 GitOps 部署*之後*才執行節點標籤 (Labeling)，這會導致所有 P5 的 Pod 因找不到符合標籤的節點而**調度失敗 (Pending)**。

我將為你重新撰寫一份符合 `README.md` 新架構的 `deploy-guide.md`，並提供在部署流程中**必須更新的設定檔**，以確保架構能成功部署。

-----

### DetectViz GitOps 部署手冊 (新架構版)

**版本**: 2.0
**基於架構**: `README.md` (4 VM 混合負載模型)

本手冊遵循 `README.md` 定義的 P1 至 P5 部署流程，並進行了必要的順序調整（例如提前進行節點標籤），以確保工作負載能正確調度。

-----

### Phase 0: Proxmox Host 與範本前置作業

在 P1 (Terraform) 開始之前，必須先準備好 Proxmox 宿主機環境。

#### 1\. (關鍵) 修正 Proxmox Host 網路

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
ansible-playbook -i ansible/inventory.ini setup-proxmox.yml # (你需要一個指向 proxmox-host role 的 playbook)
```

#### 2\. 準備 Ubuntu 22.04 範本

根據 `README.md` 的「前置作業」，確保你的 Proxmox VM 範本 (`ubuntu-2204-template`) 已經：

  * 安裝 `qemu-guest-agent` (並在 Proxmox VM 選項中啟用)。
  * 啟用 Cloud-Init。

#### 3\. 準備 SSH 金鑰

  * `~/.ssh/id_rsa.pub`：用於 Terraform 注入 VM 以便 Ansible 連線。
  * `~/.ssh/id_gitops` (新金鑰)：產生一組**專門給 ArgoCD** 讀取 Git 倉庫用的 SSH Key (請將公鑰 `id_gitops.pub` 加入你的 Git 倉庫 Deploy Key)。

-----

### [P1] Phase 1: Terraform 基礎設施佈建

**目標**：建立 `README.md` 中定義的 4 台 VM。

**設定檔:** `terraform/main.tf` (確保資源配置符合 `README.md`)

```terraform
# (部分範例)
# ... Proxmox Provider ...

# VM-1: master-1
resource "proxmox_vm_qemu" "k8s_master_1" {
  count       = 1
  name        = "master-1"
  target_node = var.proxmox_node
  # ... (其他設定) ...
  cores       = 4  # 根據 README
  memory      = 8192 # 根據 README
  # ... (磁碟/網路設定) ...
  ipconfig0   = "ip=192.168.0.11/24,gw=192.168.0.1"
}

# VM-2: master-2
resource "proxmox_vm_qemu" "k8s_master_2" {
  # ... (略) ...
  cores       = 3
  memory      = 8192
  ipconfig0   = "ip=192.168.0.12/24,gw=192.168.0.1"
}

# VM-3: master-3
resource "proxmox_vm_qemu" "k8s_master_3" {
  # ... (略) ...
  cores       = 3
  memory      = 8192
  ipconfig0   = "ip=192.168.0.13/24,gw=192.168.0.1"
}

# VM-4: app-worker
resource "proxmox_vm_qemu" "k8s_worker_1" {
  name        = "app-worker"
  # ... (略) ...
  cores       = 12 # 根據 README
  memory      = 24576 # 根據 README (24GB)
  # ...
  scsi0       = "nvme-vm:320,..." # 根據 README (320GB)
  ipconfig0   = "ip=192.168.0.14/24,gw=192.168.0.1"
}
```

**執行:**

```bash
cd terraform/

# 填寫 Proxmox API 資訊
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# 佈建 VM
terraform init
terraform apply -auto-approve

# 驗證 VM IP (並更新 ansible/inventory.ini)
terraform output
```

-----

### [P2] Phase 2: Ansible K8s 初始化 (Calico & Kube-VIP)

**目標**：安裝 K8s、**Calico** (CNI) 和 `kube-vip` (HA VIP)。

**設定檔:** `ansible/group_vars/all.yml` (更新變數)

```yaml
# ... (現有變數) ...

# --- K8s Cluster ---
# 根據 README.md 的 Network Configuration
cluster_vip: "192.168.0.10"
pod_cidr: "10.244.0.0/16"
service_cidr: "10.96.0.0/12"

# --- K8s CNI (P2) ---
# 指定 Calico (取代 Flannel)
cni_provider: "calico"
calico_manifest_url: "https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml"
calico_manifest_local_path: "/tmp/calico-patched.yaml"

# --- K8s HA (P2) ---
kube_vip_version: "v0.7.1" # (或更新)
```

**設定檔:** `ansible/roles/master/tasks/main.yml` (替換 CNI 和 Kube-VIP 任務)

```yaml
# ... (kubeadm init 任務之前) ...

- name: "[P2] 安裝 Kube-VIP 所需套件"
  ansible.builtin.apt:
    name: ['arping', 'jq']
    state: present
  become: true

- name: "[P2] 下載 Kube-VIP Manifest"
  ansible.builtin.get_url:
    url: "https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml"
    dest: "/etc/kubernetes/manifests/kube-vip-cloud-controller.yaml"
    mode: '0644'
  become: true
  when: inventory_hostname == groups['masters'][0]

- name: "[P2] 產生 Kube-VIP DaemonSet (用於 Control Plane HA)"
  ansible.builtin.command: >
    docker run --rm ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }} manifest daemonset
    --interface {{ ansible_default_ipv4.interface }}
    --address {{ cluster_vip }}
    --controlplane
    --leaderElection
    --taint
    --inCluster
    --arp
    --enableLoadBalancer=true
  register: kube_vip_ds_manifest
  become: true
  changed_when: true
  when: inventory_hostname == groups['masters'][0]

- name: "[P2] 寫入 Kube-VIP DaemonSet Manifest"
  ansible.builtin.copy:
    content: "{{ kube_vip_ds_manifest.stdout }}"
    dest: "/etc/kubernetes/manifests/kube-vip-ds.yaml"
  become: true
  when: inventory_hostname == groups['masters'][0]

# ... (kubeadm init 任務) ...
# 確保 kubeadm-config.yaml.j2 使用 {{ cluster_vip }} 和 {{ pod_cidr }}

# ... (複製 kubeconfig 任務之後) ...

- name: "[P2] 下載 Calico Manifest"
  ansible.builtin.get_url:
    url: "{{ calico_manifest_url }}"
    dest: "{{ calico_manifest_local_path }}"
    mode: '0644'
  become: false # 以 admin.conf 執行
  when: inventory_hostname == groups['masters'][0]

- name: "[P2] 根據 Pod CIDR 修改 Calico Manifest"
  ansible.builtin.lineinfile:
    path: "{{ calico_manifest_local_path }}"
    regexp: '^(.*"name": "CALICO_IPV4POOL_CIDR", "value": ").*(")$'
    line: '\1{{ pod_cidr }}\2'
    backrefs: true
  become: false
  when: inventory_hostname == groups['masters'][0]

- name: "[P2] 套用 Calico CNI"
  ansible.builtin.command: "kubectl apply -f {{ calico_manifest_local_path }}"
  become: false
  when: inventory_hostname == groups['masters'][0]
  changed_when: true
```

**執行:**

```bash
cd ansible/

# 更新 inventory.ini (若未被 Terraform 自動更新)
# 確保 SSH 連線正常
ansible all -i inventory.ini -m ping

# 執行 K8s 叢集部署
ansible-playbook -i inventory.ini deploy-cluster.yml

# 取得 Kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig/admin.conf
kubectl get nodes
# (節點此時應為 Ready)
```

-----

### [P2.5] Phase 3: Kubernetes 節點標籤 (關鍵順序調整)

**目標**：在 P3/P4/P5 應用部署*之前*，為節點貼上標籤，以符合 `README.md` 的工作負載規劃。

**設定檔:** `scripts/render-node-labels.sh` (更新為新架構)

```bash
#!/bin/bash
set -e

# 根據 README.md 的架構為節點貼標籤
echo "Applying workload labels based on README.md..."

# Master 節點 (Control Plane + Observability Backend)
kubectl label node master-1 node-role.kubernetes.io/workload-monitoring=true --overwrite
kubectl label node master-2 node-role.kubernetes.io/workload-mimir=true --overwrite
kubectl label node master-3 node-role.kubernetes.io/workload-loki=true --overwrite

# Worker 節點 (Application Node)
kubectl label node app-worker node-role.kubernetes.io/workload-apps=true --overwrite

# (可選) 為所有 master 節點添加通用標籤
for i in 1 2 3; do
  kubectl label node "master-$i" node-role.kubernetes.io/observability-backend=true --overwrite
done

echo "Node labels applied successfully."
kubectl get nodes --show-labels
```

**執行:**

```bash
cd scripts/
chmod +x render-node-labels.sh

# 執行標籤腳本
./render-node-labels.sh
```

-----

### [P3] Phase 4: GitOps Bootstrap (Argo CD)

**目標**：安裝 Argo CD，並部署 `root-argocd-app.yaml` 來啟動 P3/P4/P5 的 GitOps 流程。

**設定檔 (GitOps 結構):**
根據 `README.md` 的目錄結構，我們需要 4 個檔案來啟動 GitOps。

1.  `argocd/root-argocd-app.yaml` (App-of-Apps 入口)

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME: 換成你的 Git Repo
        path: argocd/appsets # 指向 AppSet 目錄
        targetRevision: HEAD
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
    ```

2.  `argocd/appsets/argocd-bootstrap-app.yaml` (管理 ArgoCD 自身與集群資源)

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: ApplicationSet
    metadata:
      name: argocd-bootstrap
    spec:
      generators:
        - list:
            elements:
              - name: cluster-bootstrap
                path: argocd/bootstrap
      template:
        metadata:
          name: '{{name}}'
        spec:
          project: default
          source:
            repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
            targetRevision: HEAD
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc
            namespace: default # Bootstrap 資源 (如 NS, ClusterIssuer)
          syncPolicy:
            automated: { prune: true, selfHeal: true }
    ```

3.  `argocd/appsets/infra-appset.yaml` (新檔案，管理 P3/P4)

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: ApplicationSet
    metadata:
      name: infra-appset
    spec:
      generators:
        - git:
            repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
            revision: HEAD
            directories:
              - path: argocd/apps/infrastructure/* # P3/P4 服務
      template:
        metadata:
          name: '{{path.basename}}'
        spec:
          project: default
          source:
            repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
            targetRevision: HEAD
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc
            namespace: '{{path.basename}}' # 預設 namespace 與 app 同名
          syncPolicy:
            automated: { prune: true, selfHeal: true }
            syncOptions:
              - CreateNamespace=true
    ```

4.  `argocd/appsets/apps-appset.yaml` (新檔案，管理 P5)

    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: ApplicationSet
    metadata:
      name: apps-appset
    spec:
      generators:
        - git:
            repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
            revision: HEAD
            directories:
              - path: argocd/apps/observability/* # P5 服務
      template:
        metadata:
          name: '{{path.basename}}'
        spec:
          project: default
          source:
            repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
            targetRevision: HEAD
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc
            namespace: '{{path.basename}}' # 預設 namespace 與 app 同名
          syncPolicy:
            automated: { prune: true, selfHeal: true }
            syncOptions:
              - CreateNamespace=true
    ```

**執行:**

```bash
cd scripts/

# 1. 安裝 Argo CD 基礎元件
# (install-argocd.sh 應包含 'kubectl create namespace argocd' 和 'kubectl apply -n argocd -f .../install.yaml')
./install-argocd.sh

# 2.【關鍵】設定 ArgoCD Git 權限
# (使用 Phase 0 建立的 id_gitops 私鑰)
./setup-argocd-ssh.sh --ssh-key-path ~/.ssh/id_gitops

# 3. 部署 App-of-Apps
kubectl apply -f ../argocd/root-argocd-app.yaml

# 4. 驗證 GitOps 啟動
kubectl get applicationsets -n argocd
# 預期應看到: argocd-bootstrap, infra-appset, apps-appset
```

-----

### [P3] Phase 5: 核心服務手動介入 (Vault)

**目標**：`README.md` P3 服務中的 `vault` 會由 ArgoCD 部署，但它需要手動初始化和解封 (Unseal)，`external-secrets-operator` 才能正常運作。

**執行 (手動):**

```bash
# 1. 等待 Vault Pod (應在 app-worker 節點) 進入 Running
kubectl get pods -n vault --watch

# 2. 初始化 Vault (使用單金鑰，僅供展示)
kubectl exec -n vault statefulset/vault -c vault -- \
  vault operator init -key-shares=1 -key-threshold=1 > vault.init
chmod 600 vault.init

# 3. 取得金鑰和 Token
VAULT_UNSEAL_KEY=$(grep 'Unseal Key 1:' vault.init | awk '{print $NF}')
VAULT_ROOT_TOKEN=$(grep 'Initial Root Token:' vault.init | awk '{print $NF}')

# 4. 解封 Vault
kubectl exec -n vault statefulset/vault -c vault -- \
  vault operator unseal "$VAULT_UNSEAL_KEY"

# 5. 登入 Vault
kubectl exec -n vault statefulset/vault -c vault -- vault login "$VAULT_ROOT_TOKEN"

# 6. 設定 Kubernetes Auth (供 ESO 使用)
# (此部分請參考舊 deploy-guide.md Phase 6 的 "啟用 Kubernetes Auth 並建立角色" 步驟)
# ... (vault auth enable kubernetes, vault write auth/kubernetes/config, vault policy write, vault write auth/kubernetes/role) ...

# 7. (安全) 妥善保存 vault.init 檔案並從本地刪除
```

-----

### [P4/P5] Phase 6: 最終驗證與工作負載調度

**目標**：驗證 P4 (Infra) 和 P5 (Apps) 服務已由 ArgoCD 成功部署，並**驗證它們是否在 `README.md` 指定的節點上**。

**設定檔 (P5 調度範例):**
為了讓 P5 Pod 正確調度，你需要使用 `nodeSelector` 來匹配 Phase 3 設定的標籤。

1.  **Prometheus (P5) -\> master-1 (VM-1)**
    `argocd/apps/observability/prometheus/overlays/values.yaml` (範例)

    ```yaml
    # Helm Values for Prometheus
    prometheus:
      prometheusSpec:
        nodeSelector:
          node-role.kubernetes.io/workload-monitoring: "true"
        tolerations: # (如果 master 有 Taint)
          - key: "node-role.kubernetes.io/control-plane"
            operator: "Exists"
            effect: "NoSchedule"
    # ... (其他 Alertmanager, Grafana 等元件應設為 false 或配置 nodeSelector)
    ```

2.  **Loki (P5) -\> master-3 (VM-3)**
    `argocd/apps/observability/loki/overlays/values.yaml` (範例)

    ```yaml
    # Helm Values for Loki
    loki:
      nodeSelector:
        node-role.kubernetes.io/workload-loki: "true"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    ```

3.  **Grafana (P5) -\> app-worker (VM-4)**
    `argocd/apps/observability/grafana/overlays/values.yaml` (範例)

    ```yaml
    # Helm Values for Grafana
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
    # ... (Grafana 不需要 tolerations，因為 app-worker 是 worker 節點)
    ```

*(**說明:** 你需要為 `README.md` 中所有 P5 應用 (Mimir, Keycloak, Tempo, Postgres) 和 P3/P4 應用 (ArgoCD, Vault) 設定類似的 `nodeSelector`，確保它們被部署到 `app-worker` 或指定的 Master 節點。)*

**執行 (驗證):**

```bash
# 1. 檢查 ArgoCD 狀態
argocd app list
# (等待所有 Apps 變為 Synced 和 Healthy)

# 2. 驗證 P4 服務
kubectl get pods -n metallb-system
kubectl get pods -n topolvm-system
kubectl get pods -n ingress-nginx

# 3.【最終驗證】檢查 P5 工作負載調度
kubectl get pods -A -o wide

# 預期輸出 (範例):
# NAMESPACE          NAME                              NODE
# ...
# vault              vault-0                           app-worker  # (P3)
# argocd             argocd-server-xxxx                app-worker  # (P3)
# ...
# prometheus         prometheus-0                      master-1    # (P5)
# loki               loki-0                            master-3    # (P5)
# mimir              mimir-0                           master-2    # (P5)
# grafana            grafana-xxxx                      app-worker  # (P5)
# keycloak           keycloak-xxxx                     app-worker  # (P5)
# ...
```