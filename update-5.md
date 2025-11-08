經過我們一路的推導和整合，你做得非常好。

我們已經成功地將 `deploy-guide.md` 中所有**手動的 `.sh` 腳本** (`render-node-labels.sh`, `setup-argocd-ssh.sh`, `install-argocd.sh`) 全部整併到 Ansible `deploy-cluster.yml` 中。

目前的自動化流程直到 P3 結束，邏輯上是**健全且環環相扣**的：

1.  **P2 (Ansible):** 安裝 K8s、Calico (已修正 CIDR)、Kube-VIP，並確保 `qemu-guest-agent` 正在運行。
2.  **P2.5 (Ansible):** 自動為節點貼上 `README.md` 所需的 workload 標籤 (Label)。
3.  **P2.5 (Ansible):** 自動注入 ArgoCD 啟動所需的 `argocd-ssh-creds` Secret。
4.  **P3 (Ansible):** 自動安裝 ArgoCD 核心元件，並\*\*(關鍵)\*\*透過 `yedit` 強制將 Pod 調度到 `app-worker` 節點。
5.  **P3 (Ansible):** 自動部署 `root-argocd-app.yaml`，啟動 GitOps。

這已經非常完善了。

-----

### 💡 最後一個「完美」的調整建議

在我們目前的流程中，存在一個非常隱蔽的「設定漂移」(Configuration Drift) 風險，這也是 Ansible 和 ArgoCD 協作時最經典的問題：

1.  **Ansible (P3) 說：** 「我用 `yedit` 把 `nodeSelector: { workload-apps: true }` 加到 ArgoCD 的 Deployment 中，強制它在 `app-worker` 節點啟動。」
2.  **ArgoCD (P3 啟動後) 說：** 「太好了！我啟動了！我的任務是同步 `root-argocd-app.yaml` -\> `appset.yaml` -\> `argocd/apps/infrastructure/argocd/`。」
3.  **ArgoCD (同步自己時) 說：** 「我發現 Git 倉庫裡的 `argocd/apps/infrastructure/argocd/` 並**沒有** `nodeSelector` 的設定。Ansible 剛剛加的 `nodeSelector` 是『非 GitOps』的變更，我必須把它**移除**才能與 Git 保持一致！」

**結果：**
ArgoCD 會「修復」自己，移除 `nodeSelector`，導致 ArgoCD 的 Pod 被重新調度到*任何*節點 (包含 master)，這就**違背了 `README.md` 的架構規劃**。

-----

### ✅ 最終的完善方案：讓 GitOps 自己管理 `nodeSelector`

為了達到「完善」，我們必須讓 Ansible (P3) 的啟動設定 與 GitOps (P4/P5) 的最終狀態**完全一致**。

我們保留 Ansible (P3) 中用 `yedit` 添加 `nodeSelector` 的任務，這能確保 ArgoCD *第一次啟動* 就在正確的節點。

但我們**必須**同時將這個 `nodeSelector` 設定也加入到 Git 倉庫中，讓 ArgoCD 同步自己時，會「確認」這個設定是正確的，而不是「移除」它。

#### 程式碼：`argocd/apps/infrastructure/argocd/overlays/kustomization.yaml`

你需要修改這個 Kustomization 檔案，加入一個 `patches` 來為所有 ArgoCD 元件添加 `nodeSelector`。

1.  **建立一個新的 patch 檔案：**
    `argocd/apps/infrastructure/argocd/overlays/patch-nodeselector-app-worker.yaml` (新檔案)

    ```yaml
    # 這個 patch 為所有 ArgoCD 元件強制指定 nodeSelector
    # 以符合 README.md 的架構
    apiVersion: apps/v1
    kind: Deployment # 將被 Kustomize 套用到所有 Deployment
    metadata:
      name: all
    spec:
      template:
        spec:
          nodeSelector:
            node-role.kubernetes.io/workload-apps: "true"
    ---
    apiVersion: apps/v1
    kind: StatefulSet # 將被 Kustomize 套用到所有 StatefulSet
    metadata:
      name: all
    spec:
      template:
        spec:
          nodeSelector:
            node-role.kubernetes.io/workload-apps: "true"
    ```

2.  **修改 `kustomization.yaml` 來使用這個 patch：**
    `argocd/apps/infrastructure/argocd/overlays/kustomization.yaml` (修改)

    ```yaml
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    # 引用 base HA 設定
    resources:
      - ../base

    # ... (你現有的 patchesStrategicMerge，例如 argocd-cm.yaml, argocd-rbac-cm.yaml) ...

    patches:
      # 【關鍵新增】
      # 確保所有 ArgoCD 元件都部署在 app-worker 節點
      - path: patch-nodeselector-app-worker.yaml
        target:
          kind: (Deployment|StatefulSet) # 套用到所有 Pod 控制器

    # ... (你現有的 tolerations patches) ...
    # 範例：argocd/apps/infrastructure/argocd/overlays/argocd-repo-server-tolerations.yaml
    ```

    *(**注意:** `patches` 語法比 `patchesStrategicMerge` 更通用，你可以用 `target` 來選擇要 patch 的資源種類。)*

### 結論

在 P3 階段，我們的 Ansible 做了**兩件事**：

1.  **啟動 (Bootstrap):** 使用 `yedit` 確保 ArgoCD *首次啟動* 就在 `app-worker` 節點。
2.  **交接 (Handover):** 部署 `root-argocd-app.yaml`。

只要你**同時**在 Git 倉庫中（如上所示）也加入 `nodeSelector` 的定義，ArgoCD 在啟動後同步自己時，就會發現 Ansible 的設定與 Git 倉庫一致，從而實現**完美且無漂移的 GitOps 啟動**。

至此，從 P0 (Proxmox `rp_filter`) 到 P3 (ArgoCD 啟動) 的所有調整均已完善。