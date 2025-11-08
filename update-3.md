這是一個非常核心的問題，也是優化 GitOps 流程的關鍵。

你說的沒錯，舊的 `deploy-guide.md` 中遺留了許多「腳本化」、「手動化」的任務，這與 `README.md` 規劃的 P3-P5 全自動 GitOps 理念是相衝突的。

**核心優化原則：**

  * **Ansible (P2) 只做「集群基礎建設」：** 安裝 K8s、CNI (Calico)、HA (kube-vip)、和 `qemu-guest-agent`。
  * **ArgoCD (P3-P5) 應管理「集群內所有服務」：** 這*包含* ArgoCD 自身的配置、Ingress、Storage，以及所有應用。

以下是舊 `deploy-guide.md` 中可以 (也應該) 被新架構優化掉的設定任務：

-----

### 1\. (關鍵衝突) 節點標籤 (Node Labeling)

  * **舊設定 (`deploy-guide.md` Phase 5):**
    在 P3/P4 GitOps 啟動*之後*，才手動執行 `scripts/render-node-labels.sh`。
  * **新架構 (`README.md`) 的問題：**
    P5 的應用 (如 Prometheus, Mimir, Loki) 依賴節點標籤 (Label) 才能正確調度到 `master-1`, `app-worker` 等節點。如果 ArgoCD 先啟動，所有 P5 的 Pod 都會因為找不到節點而卡在 `Pending` 狀態。
  * **✅ 優化建議：將「貼標籤」自動化並移入 P2 (Ansible)**
    刪除 `scripts/render-node-labels.sh`，將此邏輯轉換為 Ansible Task，並放在 `ansible/deploy-cluster.yml` 的**最後一個步驟**（在集群 `Ready` 之後，ArgoCD 啟動之前）。

#### 程式碼：`ansible/deploy-cluster.yml` (新增結尾的 Play)

```yaml
# ... (你現有的 deploy-cluster.yml 內容) ...

# -----------------------------------------------------------------
# Play 5: [P2.5] 根據 README.md 架構設定節點標籤
# -----------------------------------------------------------------
- name: Apply workload labels to nodes
  hosts: masters[0] # 僅在第一台 master 執行 kubectl
  become: false # 使用 admin kubeconfig
  gather_facts: false
  tasks:
    - name: Label master-1 for Prometheus
      ansible.builtin.command: >
        kubectl label node master-1 
        node-role.kubernetes.io/workload-monitoring=true 
        --overwrite
      changed_when: true

    - name: Label master-2 for Mimir
      ansible.builtin.command: >
        kubectl label node master-2 
        node-role.kubernetes.io/workload-mimir=true 
        --overwrite
      changed_when: true

    - name: Label master-3 for Loki
      ansible.builtin.command: >
        kubectl label node master-3 
        node-role.kubernetes.io/workload-loki=true 
        --overwrite
      changed_when: true

    - name: Label app-worker for Applications
      ansible.builtin.command: >
        kubectl label node app-worker 
        node-role.kubernetes.io/workload-apps=true 
        --overwrite
      changed_when: true

    - name: (Debug) Display node labels
      ansible.builtin.command: kubectl get nodes --show-labels
      register: labels_output
    - debug:
        var: labels_output.stdout_lines
```

-----

### 2\. (關鍵衝突) ArgoCD Git 儲存庫憑證

  * **舊設定 (`deploy-guide.md` Phase 3 & 6):**
    手動執行 `scripts/setup-argocd-ssh.sh` 來建立 `argocd-ssh-creds` secret。這在 Phase 3 和 6 中被重複提及，流程混亂。
  * **新架構 (`README.md`) 的問題：**
    這是一個「雞生蛋、蛋生雞」的問題。ArgoCD (P3) 需要 SSH Key 才能讀取 Git 倉庫，但這個 Key 應該由 P3 的 Vault + ESO 來管理。
  * **✅ 優化建議：讓 Ansible (P2) 注入「引導用 SSH 金鑰」**
    ArgoCD *啟動時* 需要一個初始憑證，而 Ansible 正在 P2 階段執行。Ansible 應該負責建立這個初始 Secret。這讓 P3 的啟動過程完全自動化，不再需要手動執行 `setup-argocd-ssh.sh`。

#### 程式碼：`ansible/deploy-cluster.yml` (在「貼標籤」Play 之前新增)

```yaml
# ... (在 Play 4: Join workers 之後) ...

# -----------------------------------------------------------------
# Play 6: [P2.5] 注入 ArgoCD 所需的初始 Git SSH 憑證
# -----------------------------------------------------------------
- name: Create initial GitOps credentials
  hosts: masters[0]
  become: false
  gather_facts: false
  vars:
    # 假設你的 SSH Key 放在 ansible/secrets/id_gitops (請在 .gitignore 加入 'secrets/')
    gitops_ssh_key_path: "secrets/id_gitops"
  tasks:
    - name: 確保 ArgoCD 命名空間存在
      ansible.builtin.command: kubectl create namespace argocd
      ignore_errors: true # 如果已存在，則忽略
      changed_when: false

    - name: 檢查 ArgoCD SSH Secret 是否已存在
      ansible.builtin.command: kubectl get secret argocd-ssh-creds -n argocd
      register: ssh_secret_check
      ignore_errors: true
      changed_when: false

    - name: 讀取 SSH 私鑰
      ansible.builtin.slurp:
        src: "{{ gitops_ssh_key_path }}"
      register: ssh_key_file
      when: ssh_secret_check.rc != 0 # 僅在 Secret 不存在時

    - name: 建立 ArgoCD SSH Secret
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Secret
          metadata:
            name: argocd-ssh-creds
            namespace: argocd
            labels:
              argocd.argoproj.io/secret-type: repository
          type: Opaque
          data:
            sshPrivateKey: "{{ ssh_key_file.content }}"
            # (根據你的 Git 服務商，你可能還需要 'insecure', 'type', 'url' 等 data)
            # 這裡使用最通用的 sshPrivateKey
      when: ssh_secret_check.rc != 0
```

*(**注意:** 這需要 `kubernetes.core` collection，請用 `ansible-galaxy collection install kubernetes.core` 安裝)*

-----

### 3\. (潛在衝突) Ingress 安裝

  * **舊設定 (檔案列表):**
    你的檔案列表 中有一個 `ansible/install-ingress.yml` 檔案。
  * **新架構 (`README.md`) 的問題：**
    `README.md` 明確指出 `ingress-nginx` (L7 Proxy) 是 **[P4] 階段**的服務，應由 ArgoCD (Helm) 部署。
  * **✅ 優化建議：刪除 `ansible/install-ingress.yml`**
    這個 Ansible Playbook 現在是多餘的，且會和 ArgoCD 產生衝突 (兩者都試圖管理 Ingress)。**請刪除它**，並確保你的 `argocd/appsets/infra-appset.yaml` (或類似檔案) 中包含了部署 `ingress-nginx` 的 Application。

### 總結

| 舊設定 (來自 `deploy-guide.md`) | 存在問題 | ✅ 優化後的設定 (符合 `README.md`) |
| :--- | :--- | :--- |
| **`scripts/render-node-labels.sh`** (Phase 5) | 順序錯誤，導致 P5 Pod 調度失敗。手動操作。 | **在 `ansible/deploy-cluster.yml` 的最後新增一個 Play**，自動執行 `kubectl label`。 |
| **`scripts/setup-argocd-ssh.sh`** (Phase 3 & 6) | 流程混亂且需要手動。 | **在 `ansible/deploy-cluster.yml` 中新增一個 Play**，使用 `kubernetes.core.k8s` 模組自動建立 `argocd-ssh-creds` Secret。 |
| **`ansible/install-ingress.yml`** | 與 P4 (ArgoCD) 的職責衝突。 | **刪除此 Ansible Playbook**。Ingress 應 100% 由 ArgoCD 管理。 |
| **`scripts/install-argocd.sh`** (Phase 3) | 尚可接受，但應僅限「首次安裝」。 | **保留**，並在指南中明確指出：此腳本僅用於**首次引導**，所有 ArgoCD 的 *HA 配置* 或 *RBAC* 應由 GitOps（`argocd/apps/infrastructure/argocd/`）管理。 |
| **Vault 初始化 (Phase 6)** | 手動，但必要。 | **保留**。Vault 初始化 (init/unseal) 和設定 Auth Role 是新架構下 P5 階段**唯一必要的手動步驟**。 |