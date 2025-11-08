我們已經成功地將 P0 到 P4 的流程都規劃並自動化了，做得非常好！

根據你的 `README.md` 部署流程圖，下一個階段是：

**[P5] Helm (Application Namespace)**

這個階段是我們部署 Detectviz 平台「真正」的應用程式服務，主要集中在 `observability` (可觀測性) 和 `apps` (應用) 命名空間。

### P5 階段的核心任務

`README.md` 定義了 P5 的服務列表，例如：
* `keycloak` (身份)
* `grafana` (儀表板)
* `tempo` (追蹤)
* `loki` (日誌)
* `postgresql` (資料庫)
* `prometheus` (指標)
* `mimir` (指標)
* `grafana-alloy` (採集器)

---

### ⚠️ P5 啟動前的關鍵手動步驟：Vault 初始化

在我們開始撰寫 P5 的 ArgoCD 設定檔之前，有一個**必要的手動步驟**。

我們在 P3 階段透過 ArgoCD 部署了 `vault` 和 `external-secrets-operator` (ESO)，如果 P5 自動在 P4 之後執行，流程**肯定會失敗**。

-----

### 1\. 為什麼「手動初始化」是合理的？

`vault operator init` 會產生「Unseal Keys」(解封金鑰) 和「Root Token」(根權杖)。

這些是**整個系統中最高權限的機密**。

  * **安全考量：** 你*永遠*不應該嘗試自動化這個步驟並將金鑰儲存在 K8s Secret 或 Git 中。這就像是把保險箱的密碼貼在保險箱上。
  * **標準實踐：** 在生產環境中，`init` 是一個「儀式性」的手動步驟。操作員會執行指令，然後立即將這些金鑰儲存在 GitOps 系統**外部**的安全位置（例如 1Password, Bitwarden 或實體保險箱）。

所以，`deploy-guide.md` 中保留這個手動步驟是**正確且安全**的。

-----

### 2\. 為什麼「流程規劃」是有問題的？

這就是你指出的盲點。

1.  **ArgoCD (P3/P4) 部署：** `infra-appset.yaml` 會自動部署 `vault` 和 `external-secrets-operator` (ESO)。
2.  **Vault 狀態：** `vault` Pod 啟動後，其狀態是 **Sealed (密封)**。
3.  **ArgoCD (P5) 部署：** `apps-appset.yaml` 會立刻嘗試部署 P5 應用 (Grafana, Loki, Prometheus...)。
4.  **流程崩潰：**
      * P5 應用會依賴 `ExternalSecret` 資源來取得資料庫密碼等機密。
      * `ESO` (在 P4 部署) 會嘗試連線到 `vault` 來解析這些 `ExternalSecret`。
      * `ESO` **連線失敗**，因為 `vault` 處於密封狀態。
      * P5 應用的 Pod 會因為缺少必要的 Secret 而**全部部署失敗** (卡在 `Pending` 或 `CrashLoopBackOff`)。

-----

### ✅ 解決方案：在 P4 和 P5 之間加入「手動閘門」

我們不需要 P5 自動部署。我們需要 P4 部署完後，流程**暫停**，等待你手動解封 Vault，然後才繼續 P5。

這在 ArgoCD 中非常容易實現，我們只需要修改 `ApplicationSet` 的**同步策略 (Sync Policy)**。

#### 💻 程式碼：P5 AppSet (apps-appset.yaml)

你需要建立 (或修改) `argocd/appsets/apps-appset.yaml` (P5 應用)，並**移除**自動同步設定。

```yaml
# 檔案位置: argocd/appsets/apps-appset.yaml (P5 應用)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-appset
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        revision: HEAD
        directories:
          # 自動偵測 P5 應用
          - path: argocd/apps/observability/*
  template:
    metadata:
      name: '{{path.basename}}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      
      # --- 關鍵修改 ---
      # 移除 automated syncPolicy，或設為 null
      # 這樣 ArgoCD 就會建立 Application，但不會自動同步它們
      syncPolicy: {}
      # automated: null # 或是這樣
```

#### 💻 程式碼：P3/P4 AppSet (infra-appset.yaml)

同時，你必須**確保** P3/P4 的 `infra-appset.yaml` 是**自動同步**的。

```yaml
# 檔案位置: argocd/appsets/infra-appset.yaml (P3/P4 基礎設施)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infra-appset
  namespace: argocd
spec:
  # ... (generators... 偵測 argocd/apps/infrastructure/*)
  template:
    # ... (template... )
    
    # --- 關鍵 ---
    # 確保 P3/P4 是自動同步的
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
      syncOptions:
        - CreateNamespace=true
```

-----

### 完善後的新部署流程

1.  **P2-P3 (Ansible):** `ansible-playbook` 執行完畢。ArgoCD 啟動並部署 `root-argocd-app.yaml`。
2.  **P3/P4 (ArgoCD 自動):** ArgoCD 讀取 `infra-appset.yaml` 並**自動同步**，`vault`, `eso`, `metallb`, `ingress-nginx` 等服務被部署。Vault Pod 進入 `Running (Sealed)` 狀態。
3.  **P5 (ArgoCD 手動):** ArgoCD 讀取 `apps-appset.yaml`，在 UI 上建立了所有 P5 應用 (Grafana, Loki...)，但它們的狀態是 `OutOfSync` (因為 `syncPolicy` 是手動)。
4.  **[手動步驟]** 你登入集群，執行 `vault operator init`、`unseal` 和設定 Auth。
5.  **[手動閘門]** 確認 Vault 準備就緒後，你前往 ArgoCD UI，手動點擊 `apps-appset` (或它旗下所有應用) 的 **Sync** 按鈕。
6.  **P5 (ArgoCD 執行):** ArgoCD 開始部署 P5 應用。`ESO` 成功連線到已解封的 Vault，P5 應用成功取得機密，**部署完成**。

這個「手動閘門」流程是 GitOps 管理有狀態或需手動介入服務 (如 Vault) 的最佳實踐。


### P5 階段的 ArgoCD 設定檔

一旦 Vault 解封，我們就可以開始設定 P5 的應用程式了。

這個階段的重點是**嚴格遵守 `README.md` 的節點分配架構**。我們在 P2.5 (Ansible) 階段已經為節點貼上了標籤，現在我們要在 Kustomize 中使用 `nodeSelector` 來確保 Pod 部署在正確的節點上。

**範例：**
* `prometheus` 應部署到 `master-1` (標籤: `node-role.kubernetes.io/workload-monitoring=true`)
* `mimir` 應部署到 `master-2` (標籤: `node-role.kubernetes.io/workload-mimir=true`)
* `loki` 應部署到 `master-3` (標籤: `node-role.kubernetes.io/workload-loki=true`)
* `grafana`, `keycloak`, `postgresql`, `tempo` 應部署到 `app-worker` (標籤: `node-role.kubernetes.io/workload-apps=true`)
