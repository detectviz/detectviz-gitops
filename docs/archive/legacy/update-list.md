# 重構修改要點清單

本文件記錄了根據 `update-*.md` 文件，為符合新 `README.md` 架構而需要進行的所有修改。

## 第一階段：Ansible (P2 & P3 Bootstrap)

### 檔案修改

1.  **`ansible/group_vars/all.yml`**:
    *   更新 `cluster_vip`, `pod_cidr`, `service_cidr`。
    *   將 `cni_provider` 從 `flannel` 改為 `calico`，並更新 Calico manifest URL。
    *   新增 `kube_vip_version` 變數。

2.  **`ansible/roles/master/tasks/main.yml`**:
    *   移除舊的 Flannel CNI 安裝任務。
    *   新增 Kube-VIP 安裝與設定任務。
    *   新增 Calico CNI 安裝與設定任務，並確保能動態更新 Pod CIDR。

3.  **`ansible/roles/common/tasks/main.yml`** (或 `all.yml` playbook):
    *   新增任務以確保 `qemu-guest-agent` 已安裝並執行。

4.  **`ansible/deploy-cluster.yml`**:
    *   **新增 Play：節點標籤**：在 Ansible Playbook 的最後，新增一個 Play，用 `kubectl label` 為 `master-1`, `master-2`, `master-3`, `app-worker` 加上 workload 標籤。
    *   **新增 Play：ArgoCD SSH Secret**：新增一個 Play，用 `kubernetes.core.k8s` 模組建立 `argocd-ssh-creds` Secret。
    *   **新增 Play：ArgoCD Bootstrap**：新增一個 Play，取代 `install-argocd.sh`，下載 ArgoCD manifest，用 `yedit` 加入 `nodeSelector`，然後用 `kubernetes.core.k8s` 模組套用。
    *   **新增任務：部署 Root App**：在 ArgoCD Bootstrap Play 的最後，部署 `root-argocd-app.yaml`。

### 檔案刪除

1.  **`scripts/render-node-labels.sh`**: 功能已被 Ansible 自動化，應刪除。
2.  **`scripts/setup-argocd-ssh.sh`**: 功能已被 Ansible 自動化，應刪除。
3.  **`scripts/install-argocd.sh`**: 功能已被 Ansible 自動化，應刪除。
4.  **`ansible/install-ingress.yml`**: Ingress 現在由 ArgoCD (P4) 管理，此 Playbook 應刪除。

## 第二階段：ArgoCD (P3, P4, P5)

### GitOps 結構調整

1.  **`argocd/root-argocd-app.yaml`**:
    *   確保 `source.path` 指向 `argocd/appsets`。
    *   更新 `repoURL` 為正確的 Git 倉庫地址。

2.  **`argocd/appsets/`**:
    *   **建立 `argocd-bootstrap-app.yaml`**: 管理 ArgoCD 自身和集群資源。
    *   **建立 `infra-appset.yaml`**:
        *   使用 Git Generator 自動偵測 `argocd/apps/infrastructure/*`。
        *   設定**自動同步** (`automated: { prune: true, selfHeal: true }`)。
    *   **建立 `apps-appset.yaml`**:
        *   使用 Git Generator 自動偵測 `argocd/apps/observability/*` 和 `argocd/apps/identity/*`。
        *   設定**手動同步** (`syncPolicy: {}`)，作為 Vault 初始化的手動閘門。

### P3/P4/P5 應用程式設定

1.  **ArgoCD (`argocd/apps/infrastructure/argocd/`)**:
    *   在 `overlays/kustomization.yaml` 中，新增一個 patch (`patch-nodeselector-app-worker.yaml`)，為所有 ArgoCD 元件 (Deployment, StatefulSet) 加入 `nodeSelector`，確保它們部署到 `app-worker` 節點，以防止設定漂移。

2.  **ingress-nginx (`argocd/apps/infrastructure/ingress-nginx/`)**:
    *   在 `values.yaml` 中加入 `nodeSelector`，指向 `app-worker`。

3.  **metallb (`argocd/apps/infrastructure/metallb/`)**:
    *   在 `overlays/ipaddresspool.yaml` 中，將 IP 池範圍修改為 `192.168.0.200-192.168.0.220`，以避免與現有設備衝突。

4.  **topolvm (`argocd/apps/infrastructure/topolvm/`)**:
    *   在 `values.yaml` 中，為 `controller` 和 `node` 都加入 `nodeSelector`，指向 `app-worker`。

5.  **P5 應用程式 (`argocd/apps/observability/*` and `argocd/apps/identity/*`)**:
    *   **Prometheus**: 在 `overlays` 中加入 patch，設定 `nodeSelector` 指向 `master-1` (`workload-monitoring: true`)，並加入 `tolerations`。
    *   **Mimir**: 在 `overlays` 中加入 patch，設定 `nodeSelector` 指向 `master-2` (`workload-mimir: true`)，並加入 `tolerations`。
    *   **Loki**: 在 `overlays` 中加入 patch，設定 `nodeSelector` 指向 `master-3` (`workload-loki: true`)，並加入 `tolerations`。
    *   **Grafana, Keycloak, PostgreSQL, Tempo, Alertmanager**: 在 `overlays` 中加入 patch，設定 `nodeSelector` 指向 `app-worker` (`workload-apps: true`)。
    *   **grafana-alloy, node-exporter (DaemonSets)**: 在 `overlays` 中加入 patch，為 DaemonSet 加入 `tolerations`，使其能部署到 Master 節點。
    *   **ESO (`ExternalSecret`)**: 為需要資料庫密碼的應用 (如 Grafana, Keycloak) 建立 `ExternalSecret` 資源，從 Vault 獲取機密。
    *   **儲存 (`volumeClaimTemplates`)**: 為有狀態應用 (如 PostgreSQL, Loki, Tempo, Alertmanager) 在 patch 中指定 `storageClassName: topolvm-provisioner`。

## 第三階段：文檔更新

1.  **`deploy-guide.md`**:
    *   根據以上所有自動化流程和 ArgoCD 手動閘門的步驟，**完全重寫**部署指南。
    *   移除所有對已刪除腳本 (`.sh`) 的引用。
    *   強調 Vault 初始化的手動步驟是 P4 和 P5 之間的分界點。
    *   更新驗證步驟，包括檢查 Pod 是否在正確的節點上 (`kubectl get pods -o wide`)。

2.  **`README.md`**:
    *   審查並確保與新的 `deploy-guide.md` 內容一致，沒有衝突。

## 第四階段：最終審查

1.  **`AGENT.md`**:
    *   根據重構後的 `deploy-guide.md` 和相關設定檔，再次依據 `AGENT.md` 思考是否符合最佳實踐，有沒有需要再改善的地方。
