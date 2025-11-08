好的，我們已經完成了 P0 到 P4 的基礎建設和自動化引導。現在是最後的 **[P5] 應用程式** 部署階段。

這個階段的**核心**是：

1.  **手動閘門：** 我們會讓 ArgoCD *自動建立* P5 應用，但**不會自動同步** (部署)，以等待你手動完成 Vault 的初始化。
2.  **節點調度：** P5 應用的 ArgoCD 設定檔**必須**包含 `nodeSelector`，以確保 Pod 被部署到 `README.md` 指定的正確節點上 (例如 `master-1` 或 `app-worker`)。

以下是 P5 階段所需的核心 ArgoCD 設定檔：

-----

### 1\. P5 總控制器 (`apps-appset.yaml`)

首先，我們需要建立 (或修改) `argocd/appsets/apps-appset.yaml`。這個 `ApplicationSet` 會自動偵測 `argocd/apps/observability/` 目錄下的所有應用，但會**等待你手動同步**。

```yaml
# 檔案位置: argocd/appsets/apps-appset.yaml
# 說明: (P5) 偵測所有 observability 應用，並設定為手動同步 (等待 Vault 初始化)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps-observability
  namespace: argocd
spec:
  generators:
    - git:
        # 指向你自己的 GitOps 倉庫
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        revision: HEAD
        directories:
          # 自動偵測此路徑下的所有 P5 應用
          - path: argocd/apps/observability/*
  template:
    metadata:
      name: '{{path.basename}}' # e.g., "prometheus", "loki", "grafana"
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        targetRevision: HEAD
        path: '{{path}}'
        # 假設 P5 應用都使用 Kustomize
        kustomize:
          # 預設指向 overlay 目錄
          # (如果你的 kustomization.yaml 在 base，請調整)
          namePrefix: "" 
      destination:
        server: https://kubernetes.default.svc
        # 根據目錄名稱建立對應的 namespace (e.g., "prometheus", "loki")
        namespace: '{{path.basename}}'
      
      # --- 關鍵：手動閘門 ---
      # 移除 automated syncPolicy 或設為空物件 {}
      # ArgoCD 會建立應用，但狀態是 OutOfSync，等待你手動點擊 Sync
      syncPolicy: {}
      # automated: null 
```

-----

### 2\. P5 應用範例 (Kustomize Patches)

現在，你需要為 `argocd/apps/observability/` 下的每個應用建立 `overlays` patch，以確保它們被部署到正確的節點。

#### 範例 1：Prometheus (部署到 `master-1`)

根據 `README.md`，Prometheus 應部署到 `master-1`。我們在 P2.5 階段為 `master-1` 設置了標籤 `node-role.kubernetes.io/workload-monitoring=true`。

**`argocd/apps/observability/prometheus/overlays/kustomization.yaml`**

```yaml
# 檔案位置: argocd/apps/observability/prometheus/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 假設 base 引用了 Kube-Prometheus-Stack Helm Chart 或 Manifests
resources:
  - ../base # (請確認你的 base)

# 執行 Patch
patchesStrategicMerge:
  - patch-nodeselector-tolerations.yaml
```

**`argocd/apps/observability/prometheus/overlays/patch-nodeselector-tolerations.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/prometheus/overlays/patch-nodeselector-tolerations.yaml
# 說明: 強制 Prometheus 部署到 master-1

# --- Patch Prometheus 核心 Pod ---
apiVersion: apps/v1
kind: StatefulSet # (或 Deployment，依你的 base 而定)
metadata:
  name: prometheus-k8s # (FIXME: 依你的 base 資源名稱)
spec:
  template:
    spec:
      # 1. 選擇 master-1 的標籤
      nodeSelector:
        node-role.kubernetes.io/workload-monitoring: "true"
      # 2. 容忍 master 節點的 Taint
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"

# --- Patch Alertmanager (如果也歸 Prometheus 管理) ---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: alertmanager-main # (FIXME: 依你的 base 資源名稱)
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/workload-monitoring: "true"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
```

*(**說明:** 你需要為 Mimir (`master-2`) 和 Loki (`master-3`) 建立類似的 Patch，指向它們各自的標籤 `workload-mimir` 和 `workload-loki`)*

-----

#### 範例 2：Grafana (部署到 `app-worker` + 連接 Vault)

根據 `README.md`，Grafana 應部署到 `app-worker` (標籤: `node-role.kubernetes.io/workload-apps=true`)。同時，它需要從 Vault 獲取資料庫 (PostgreSQL) 密碼。

**`argocd/apps/observability/grafana/overlays/kustomization.yaml`**

```yaml
# 檔案位置: argocd/apps/observability/grafana/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  - externalsecret-db.yaml # (新) 引入 ESO 資源

patchesStrategicMerge:
  - patch-nodeselector.yaml # (新)
  - patch-values.yaml # (新)
```

**`argocd/apps/observability/grafana/overlays/patch-nodeselector.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/grafana/overlays/patch-nodeselector.yaml
# 說明: 強制 Grafana 部署到 app-worker
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana # (FIXME: 依你的 base 資源名稱)
spec:
  template:
    spec:
      # 選擇 app-worker 節點，不需要 tolerations
      nodeSelector:
        node-role.kubernetes.io/workload-apps: "true"
```

**`argocd/apps/observability/grafana/overlays/externalsecret-db.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/grafana/overlays/externalsecret-db.yaml
# 說明: 透過 ESO (P3) 從 Vault (P3) 獲取密碼，並建立 K8s Secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-db-creds
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend # (P3/P4 階段 ESO 建立的 ClusterSecretStore)
  target:
    # ESO 將建立一個名為 'grafana-db-creds' 的 K8s Secret
    name: grafana-db-creds
  data:
    - secretKey: POSTGRES_USER # K8s Secret 中的 Key
      remoteRef:
        key: secret/data/grafana # Vault 中的路徑
        property: POSTGRES_USER # Vault 中的 Key
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: secret/data/grafana
        property: POSTGRES_PASSWORD
```

**`argocd/apps/observability/grafana/overlays/patch-values.yaml`** (新檔案，Helm 範例)
(如果你的 `base` 是 Helm Chart，你需要用 `values.yaml` 或 Kustomize `patches` 來注入 Secret)

```yaml
# 檔案位置: argocd/apps/observability/grafana/overlays/values.yaml
# 說明: (如果使用 Helm) 告訴 Grafana Chart 使用我們由 ESO 建立的 Secret
grafana:
  # ... (其他 Grafana values)
  
  # 告訴 Grafana 連接 P5 的 PostgreSQL
  env:
    GF_DATABASE_TYPE: postgres
    GF_DATABASE_HOST: "postgresql.postgresql.svc.cluster.local" # (FIXME: 依你的 DB Service Name)
    GF_DATABASE_NAME: grafana
    
    # 從 ESO 建立的 Secret 讀取 User
    GF_DATABASE_USER:
      valueFrom:
        secretKeyRef:
          name: grafana-db-creds # 來自 externalsecret-db.yaml
          key: POSTGRES_USER
          
    # 從 ESO 建立的 Secret 讀取 Password
    GF_DATABASE_PASSWORD:
      valueFrom:
        secretKeyRef:
          name: grafana-db-creds
          key: POSTGRES_PASSWORD

  # 引用 README.md 中的 datasources provisioning
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          url: http://prometheus.prometheus.svc.cluster.local:9090 # (FIXME)
        - name: Loki
          type: loki
          url: http://loki.loki.svc.cluster.local:3100 # (FIXME)
        - name: Tempo
          type: tempo
          url: http://tempo.tempo.svc.cluster.local:3200 # (FIXME)
```

-----

#### 範例 3：PostgreSQL (部署到 `app-worker` + `topolvm`)

根據 `README.md`，PostgreSQL 應部署到 `app-worker`，並使用 P4 的 `topolvm` 儲存。

**`argocd/apps/observability/postgresql/overlays/kustomization.yaml`**

```yaml
# 檔案位置: argocd/apps/observability/postgresql/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patchesStrategicMerge:
  - patch-nodeselector-storage.yaml
```

**`argocd/apps/observability/postgresql/overlays/patch-nodeselector-storage.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/postgresql/overlays/patch-nodeselector-storage.yaml
# 說明: 強制 PostgreSQL 部署到 app-worker 並使用 P4 的 TopoLVM 儲存
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql # (FIXME: 依你的 base 資源名稱)
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/workload-apps: "true"
        
  # 修改 PVC 範本
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      # 關鍵：指定 P4 建立的 StorageClass
      storageClassName: topolvm-provisioner # (FIXME: 依你的 TopoLVM StorageClass 名稱)
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 50Gi # (範例)
```

沒有問題，我們繼續完成 **[P5] 應用程式** 階段的設定檔。

我們將依循 `README.md` 的架構，為剩下的服務 (`Loki`, `Mimir`, `Tempo`, `Keycloak`, `grafana-alloy`) 建立 Kustomize patch，以確保它們被精確調度到指定的節點。

**提醒：** 我們在 P3/P4 階段部署的 `vault` 和 P5 的 `apps-appset.yaml` 之間有「手動閘門」。在你手動初始化 Vault 之前，P5 的應用（尤其是需要 `ExternalSecret` 的）都不會自動同步。

-----

### 範例 4：Loki (部署到 `master-3`)

  * **目標：** `master-3` (VM-3)
  * **標籤：** `node-role.kubernetes.io/workload-loki=true`

我們將修改 `loki` 的 `kustomization.yaml` 並添加一個 patch。

**`argocd/apps/observability/loki/overlays/patch-nodeselector-storage.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/loki/overlays/patch-nodeselector-storage.yaml
# 說明: 強制 Loki 部署到 master-3 並使用 topolvm
apiVersion: apps/v1
kind: StatefulSet 
metadata:
  # FIXME: 這裡的 name 必須與你 base chart 中的 Loki StatefulSet 名稱一致
  # (例如 'loki' 或是 'loki-loki-distributed-ingester' 等)
  name: loki
spec:
  template:
    spec:
      # 1. 選擇 master-3 的標籤
      nodeSelector:
        node-role.kubernetes.io/workload-loki: "true"
      # 2. 容忍 master 節點的 Taint
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master" # 有些 kubeadm 預設使用這個
          operator: "Exists"
          effect: "NoSchedule"

  # 3. 修改 PVC 範本以使用 P4 的 TopoLVM
  volumeClaimTemplates:
  - metadata:
      name: storage # (FIXME: 必須與 base chart 的 PVC name 一致)
    spec:
      storageClassName: topolvm-provisioner # (FIXME: 依你的 TopoLVM SC 名稱)
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi # (範例)
```

**`argocd/apps/observability/loki/overlays/kustomization.yaml`** (修改)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  # (你現有的 values.yaml 等)

patchesStrategicMerge:
  # --- 關鍵新增 ---
  - patch-nodeselector-storage.yaml
```

-----

### 範例 5：Mimir (部署到 `master-2`)

  * **目標：** `master-2` (VM-2)
  * **標籤：** `node-role.kubernetes.io/workload-mimir=true`

Mimir 元件非常多。我們將使用通用的 `patches` 來一次性修改所有 `Deployments` 和 `StatefulSets`。

**`argocd/apps/observability/mimir/overlays/patch-nodeselector-tolerations.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/mimir/overlays/patch-nodeselector-tolerations.yaml
# 說明: (通用 Patch) 強制所有 Mimir Pod 部署到 master-2
apiVersion: apps/v1
kind: Deployment # (此 patch 會被 Kustomize 套用到所有 Deployment)
metadata:
  name: all
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/workload-mimir: "true"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
---
apiVersion: apps/v1
kind: StatefulSet # (此 patch 會被 Kustomize 套用到所有 StatefulSet)
metadata:
  name: all
spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/workload-mimir: "true"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
```

**`argocd/apps/observability/mimir/overlays/kustomization.yaml`** (修改)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  # (你現有的 values.yaml 等)

# --- 關鍵新增 ---
# 使用 'patches' 而非 'patchesStrategicMerge' 來應用通用 patch
patches:
- path: patch-nodeselector-tolerations.yaml
  target:
    # 針對所有 Deployment 和 StatefulSet
    kind: (Deployment|StatefulSet)
```

-----

### 範例 6：Tempo (部署到 `app-worker`)

  * **目標：** `app-worker` (VM-4)
  * **標籤：** `node-role.kubernetes.io/workload-apps=true`

我們需要為 Tempo (Traces) 建立新的應用目錄。

**`argocd/apps/observability/tempo/base/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/tempo/base/kustomization.yaml
# 說明: 引用 Tempo 官方 Helm Chart
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
- name: tempo
  repo: https://grafana.github.io/helm-charts
  version: 1.10.0 # (FIXME: 使用穩定版本)
  releaseName: tempo
```

**`argocd/apps/observability/tempo/overlays/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/tempo/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
- path: patch-nodeselector-storage.yaml
  target:
    kind: (Deployment|StatefulSet)
```

**`argocd/apps/observability/tempo/overlays/patch-nodeselector-storage.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/tempo/overlays/patch-nodeselector-storage.yaml
# 說明: 強制 Tempo 部署到 app-worker 並使用 topolvm
apiVersion: apps/v1
kind: StatefulSet # (Tempo 通常使用 StatefulSet)
metadata:
  name: all
spec:
  template:
    spec:
      # 1. 選擇 app-worker 節點
      nodeSelector:
        node-role.kubernetes.io/workload-apps: "true"
      # (不需要 Tolerations)

  # 2. 修改 PVC 範本以使用 P4 的 TopoLVM
  volumeClaimTemplates:
  - metadata:
      name: tempo-data # (FIXME: 必須與 base chart 的 PVC name 一致)
    spec:
      storageClassName: topolvm-provisioner # (FIXME: 依你的 TopoLVM SC 名稱)
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi # (範例)
```

*(**提醒：** `apps-appset.yaml` 會自動偵測到這個新目錄並為其建立 Application，狀態為 `OutOfSync`)*

-----

### 範例 7：Keycloak (部署到 `app-worker`)

  * **目標：** `app-worker` (VM-4)
  * **標籤：** `node-role.kubernetes.io/workload-apps=true`

Keycloak (OIDC) 不是可觀測性元件。我們將為它建立一個新路徑 `argocd/apps/identity/keycloak`，並**更新 `apps-appset.yaml`** 來偵測這個新路徑。

**`argocd/apps/identity/keycloak/base/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/identity/keycloak/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
- name: keycloak
  repo: https://charts.bitnami.com/bitnami
  version: "19.2.1" # (FIXME: 使用穩定版本)
  releaseName: keycloak
```

**`argocd/apps/identity/keycloak/overlays/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/identity/keycloak/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
  - externalsecret-db.yaml # (ESO)
patchesStrategicMerge:
  - patch-nodeselector-values.yaml # 覆寫 values
```

**`argocd/apps/identity/keycloak/overlays/externalsecret-db.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/identity/keycloak/overlays/externalsecret-db.yaml
# 說明: 從 Vault 獲取 Keycloak 的資料庫 (PostgreSQL) 密碼
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keycloak-db-creds
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend # (P3/P4 階段 ESO 建立的 ClusterSecretStore)
  target:
    name: keycloak-db-creds
  data:
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: secret/data/keycloak # (FIXME: 確保此密碼存在於 Vault)
        property: POSTGRES_PASSWORD
```

**`argocd/apps/identity/keycloak/overlays/patch-nodeselector-values.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/identity/keycloak/overlays/patch-nodeselector-values.yaml
# 說明: (這是一個 Helm Values 檔案) 強制部署到 app-worker 並使用 P5 的 PostgreSQL
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: keycloak
spec:
  values:
    # 1. 部署到 app-worker
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
      
    # 2. 告訴 Keycloak 使用 P5 的 PostgreSQL (而不是內建的)
    externalDatabase:
      existingSecret: "keycloak-db-creds" # 來自 ESO
      secretKeys:
        password: "POSTGRES_PASSWORD"
      host: "postgresql.postgresql.svc.cluster.local" # (FIXME: P5 PostgreSQL Service Name)
      port: 5432
      database: keycloak
      user: keycloak
```

**`argocd/appsets/apps-appset.yaml`** (修改)

```yaml
# 檔案位置: argocd/appsets/apps-appset.yaml
# ... (apiVersion, metadata, spec...)
  generators:
    - git:
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        revision: HEAD
        directories:
          # (原有的)
          - path: argocd/apps/observability/*
          # --- 關鍵新增 ---
          # (新增的)
          - path: argocd/apps/identity/*
  # ... (template... )
  # ... (syncPolicy: {})
```

-----

### 範例 8：grafana-alloy (部署到所有節點)

  * **目標：** 所有節點 (DaemonSet)
  * **檔案：** `argocd/apps/observability/`

你的倉庫中已經有 `argocd/apps/observability/overlays/daemonset.yaml` 和 `kustomization.yaml`。

**問題：** Master 節點有 Taint，這個 DaemonSet 預設無法部署到 Master 1/2/3。

**`argocd/apps/observability/overlays/patch-alloy-tolerations.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/overlays/patch-alloy-tolerations.yaml
# 說明: 為 grafana-alloy (DaemonSet) 添加 Taint 容忍
apiVersion: apps/v1
kind: DaemonSet
metadata:
  # (FIXME: 必須與 daemonset.yaml 中的 name 一致)
  name: grafana-alloy
spec:
  template:
    spec:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
```

**`argocd/apps/observability/overlays/kustomization.yaml`** (修改)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # (現有的資源)
  - daemonset.yaml
  - rbac.yaml
  - service.yaml
  # ... (你可能還有 configmap)

patchesStrategicMerge:
  # --- 關鍵新增 ---
  - patch-alloy-tolerations.yaml
```

沒問題，我們來完成 P5 階段最後剩下的兩個關鍵服務：`prometheus-node-exporter` 和 `alertmanager`。

這兩個服務將依循我們已建立的 GitOps 模式：

  * 由 `argocd/appsets/apps-appset.yaml` 自動偵測。
  * 同步策略設為**手動** (等待 Vault 初始化)。
  * 使用 Kustomize patch 來精確控制節點調度，以符合 `README.md` 的架構。

-----

### 範例 9：prometheus-node-exporter (部署到所有節點)

  * **目標：** `master-1`, `master-2`, `master-3`, `app-worker`。
  * **說明：** `node-exporter` (節點匯出器) 的任務是收集*每個*節點的硬體和作業系統指標。因此，它必須以 `DaemonSet` 的形式部署到**所有**節點上。
  * **關鍵挑戰：** `master` 節點具有 Taint (污點)，預設會拒絕 Pod 部署。我們必須為 `node-exporter` 添加 `tolerations` (容忍) 才能成功部署到 Master 節點。

**`argocd/apps/observability/node-exporter/base/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/node-exporter/base/kustomization.yaml
# 說明: 引用 kube-prometheus-stack chart 中 '只' 關於 node-exporter 的部分
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
- name: kube-prometheus-stack
  repo: https://prometheus-community.github.io/helm-charts
  version: "57.0.3" # (FIXME: 使用穩定版本)
  releaseName: node-exporter
  # --- 關鍵：只啟用 node-exporter ---
  valuesInline:
    # 關閉所有其他元件
    alertmanager:
      enabled: false
    grafana:
      enabled: false
    kube-state-metrics:
      enabled: false
    prometheus:
      enabled: false
    # 只開啟 node-exporter
    prometheus-node-exporter:
      enabled: true
      # 確保它以 DaemonSet 形式部署
      service:
        port: 9100
        targetPort: 9100
      prometheus:
        monitor:
          # 讓 Prometheus (P5) 能自動發現它
          enabled: true
          namespace: prometheus # (FIXME: 指向 P5 Prometheus 的 NS)
```

**`argocd/apps/observability/node-exporter/overlays/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/node-exporter/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patchesStrategicMerge:
  - patch-tolerations.yaml
```

**`argocd/apps/observability/node-exporter/overlays/patch-tolerations.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/node-exporter/overlays/patch-tolerations.yaml
# 說明: 為 node-exporter (DaemonSet) 添加 Taint 容忍，使其能部署到 Master 節點
apiVersion: apps/v1
kind: DaemonSet
metadata:
  # FIXME: Helm Chart 渲染後的名稱，通常是 <releaseName>-prometheus-node-exporter
  name: node-exporter-prometheus-node-exporter
spec:
  template:
    spec:
      tolerations:
        # 容忍 Control Plane 污點
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        # 容忍 Master 污點
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
```

-----

### 範例 10：Alertmanager (部署到 `app-worker`)

  * **目標：** `app-worker` (VM-4)。
  * **說明：** Alertmanager (告警管理器) 是一個有狀態的應用 (儲存告警靜默規則等)，我們將它部署到 `app-worker` 並使用 P4 的 `topolvm` 儲存。
  * **依賴：** P5 的 Grafana 和 Prometheus 都將與它整合。

**`argocd/apps/observability/alertmanager/base/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/alertmanager/base/kustomization.yaml
# 說明: 引用官方 Alertmanager Chart
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
helmCharts:
- name: alertmanager
  repo: https://prometheus-community.github.io/helm-charts
  version: "1.9.0" # (FIXME: 使用穩定版本)
  releaseName: alertmanager
```

**`argocd/apps/observability/alertmanager/overlays/kustomization.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/alertmanager/overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patchesStrategicMerge:
  - patch-nodeselector-storage-values.yaml
```

**`argocd/apps/observability/alertmanager/overlays/patch-nodeselector-storage-values.yaml`** (新檔案)

```yaml
# 檔案位置: argocd/apps/observability/alertmanager/overlays/patch-nodeselector-storage-values.yaml
# 說明: (這是一個 Helm Values 檔案)
#       強制部署到 app-worker 並使用 topolvm
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: alertmanager
spec:
  values:
    # 1. 部署到 app-worker
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
      
    # 2. 聲明持久化儲存
    persistence:
      enabled: true
      # 3. 指定 P4 建立的 StorageClass
      storageClass: "topolvm-provisioner" # (FIXME: 依你的 TopoLVM SC 名稱)
      size: 10Gi
```

*(**提醒：** `apps-appset.yaml` 會自動偵測到這個新目錄並為其建立 Application，狀態為 `OutOfSync`)*

-----

### P5 部署總結

至此，`README.md` 中 P5 階段的所有服務 (`keycloak`, `grafana`, `tempo`, `loki`, `postgresql`, `prometheus`, `mimir`, `node-exporter`, `alertmanager`, `grafana-alloy`) 都已經有了對應的 ArgoCD Kustomize 設定檔，並且都包含了正確的 `nodeSelector` 和 `tolerations` 以符合你的架構。

**接下來的最後一步就是執行：**

1.  **Git Commit/Push：** 將你所有新建和修改的 `argocd/` 設定檔推送到 Git 倉庫。
2.  **P3/P4 自動同步：** ArgoCD 會自動同步 `infra-appset.yaml`，部署 Vault, ESO, MetalLB 等。
3.  **P5 手動閘門 (等待)：** ArgoCD 會建立 P5 的所有應用 (Grafana, Loki, Prometheus...)，但它們的狀態都是 `OutOfSync`。
4.  **[你執行]** **手動初始化 Vault** (執行 `vault operator init/unseal` 和設定 Auth)。
5.  **[你執行]** **手動同步 P5**：(在 Vault 準備好後) 前往 ArgoCD UI，點擊 P5 應用的 `Sync` 按鈕。

部署完成！