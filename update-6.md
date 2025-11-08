你好！很高興我們已經完成了 P0 到 P3 的自動化流程。

現在，我們來處理 **[P4] 基礎設施 (Infrastructure Namespace)**。

根據你的 `README.md`，P4 階段的服務包含：

  * `metallb` (L2 LoadBalancer)
  * `topolvm` (本地儲存)
  * `ingress-nginx` (L7 Ingress)

我們將採用與 P3 (ArgoCD, Vault) 相同的 **GitOps 模式**：

1.  使用 `argocd/appsets/infra-appset.yaml` 這個 `ApplicationSet` 來**自動偵測** `argocd/apps/infrastructure/` 目錄下的所有子目錄。
2.  每個子目錄都將被視為一個**獨立的 Helm Chart 應用**。
3.  我們將在 `values.yaml` 中，嚴格遵守 `README.md` 的架構，將這些服務的 Controller Pod **全部署到 `app-worker` 節點**。

這是在 `argocd/apps/infrastructure/` 目錄下部署 P4 服務所需的完整 ArgoCD 設定檔：

-----

### 1\. `argocd/appsets/infra-appset.yaml` (P4 總管理)

首先，我們需要建立 (或確認) `infra-appset.yaml`，它會自動尋找並部署 P4 的所有應用。

```yaml
# 檔案位置: argocd/appsets/infra-appset.yaml
# (此檔案會被 P3 的 root-argocd-app.yaml 部署)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infra-appset
  namespace: argocd
spec:
  generators:
    - git:
        # 指向你自己的 GitOps 倉庫
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        revision: HEAD
        directories:
          # 自動偵測此路徑下的所有基礎設施應用
          - path: argocd/apps/infrastructure/*
  template:
    metadata:
      name: '{{path.basename}}' # e.g., "ingress-nginx", "metallb"
      namespace: argocd
    spec:
      project: default
      source:
        # 來源就是 Git Generator 找到的路徑
        repoURL: 'git@github.com:YOUR-ORG/detectviz-gitops.git' # FIXME
        targetRevision: HEAD
        path: '{{path}}'
        # 宣告這是一個 Helm 應用
        plugin:
          name: helm
      destination:
        server: https://kubernetes.default.svc
        # 根據目錄名稱建立對應的 namespace (e.g., "ingress-nginx")
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true # 自動建立 Namespace
```

-----

### 2\. `ingress-nginx` (P4 服務 1/3)

建立 `argocd/apps/infrastructure/ingress-nginx/` 目錄並加入以下檔案：

**`Chart.yaml`**

```yaml
# 檔案位置: argocd/apps/infrastructure/ingress-nginx/Chart.yaml
# 說明: 將官方 Helm Chart 宣告為依賴
apiVersion: v2
name: ingress-nginx-app
version: 1.0.0
description: "[P4] Deploys ingress-nginx for detectviz."
dependencies:
  - name: ingress-nginx
    version: "4.10.1" # (使用一個穩定的版本)
    repository: "https://kubernetes.github.io/ingress-nginx"
```

**`values.yaml`**

```yaml
# 檔案位置: argocd/apps/infrastructure/ingress-nginx/values.yaml
# 說明: 覆寫 Helm Chart 參數，強制部署到 app-worker 節點
ingress-nginx:
  controller:
    kind: Deployment
    # 根據 README.md 架構，部署到 app-worker 節點
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
    
    # 使用 hostPort 直接在 app-worker 節點上暴露 80/443 埠
    # 這樣 MetalLB 就不需要介入
    service:
      enabled: false # 我們不使用 LoadBalancer Service
    
    hostPort:
      enabled: true
      ports:
        http: 80
        https: 443
```

-----

### 3\. `metallb` (P4 服務 2/3)

建立 `argocd/apps/infrastructure/metallb/` 目錄並加入以下檔案：


MetalLB 在 L2 模式下運作時，會透過 ARP 宣告一個 IP。如果你將 `192.168.0.100-192.168.0.150` 這個範圍交給 MetalLB，它隨時可能會宣告 `192.168.0.101` (你的本機) 或 `192.168.0.104` (IPMI) 這兩個 IP，這會導致你的本機或 IPMI 立即斷線。

請修改以下檔案，我們將 IP 池移到一個更安全的範圍，例如 `192.168.0.200-192.168.0.220`。

**檔案位置:** `argocd/apps/infrastructure/metallb/overlays/ipaddresspool.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  # 命名空間應與 kustomization.yaml 中定義的 upstream 基礎一致 (通常是 metallb-system)
  namespace: metallb-system
spec:
  addresses:
    # 修正後的範圍：避開 .10 (VIP), .11-.14 (VMs), .101 (本機), .104 (IPMI)
    - 192.168.0.200-192.168.0.220
```

**檔案位置:** `argocd/apps/infrastructure/metallb/overlays/l2advertisement.yaml`
(這個檔案通常不需要修改，只需確認它引用了正確的 IP 池名稱 `default-pool`)

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool # 確保這個名稱與 ipaddresspool.yaml 中的 name 一致
```

-----

### 4\. `topolvm` (P4 服務 3/3)

建立 `argocd/apps/infrastructure/topolvm/` 目錄並加入以下檔案：

**`Chart.yaml`**

```yaml
# 檔案位置: argocd/apps/infrastructure/topolvm/Chart.yaml
apiVersion: v2
name: topolvm-app
version: 1.0.0
description: "[P4] Deploys topolvm for detectviz local storage."
dependencies:
  - name: topolvm
    version: "0.14.0" # (使用一個穩定的版本)
    repository: "https://topolvm.github.io/charts"
```

**`values.yaml`**

```yaml
# 檔案位置: argocd/apps/infrastructure/topolvm/values.yaml
topolvm:
  # 根據 README.md 架構，部署到 app-worker 節點
  controller:
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
  
  node:
    # 我們的儲存 (VM-4 上的 320GB) 只在 app-worker 節點，
    # 所以 node (DaemonSet) 也只需要在 app-worker 上運行。
    nodeSelector:
      node-role.kubernetes.io/workload-apps: "true"
  
  storageClass:
    # 自動建立一個名為 'topolvm-provisioner' 的 StorageClass
    create: true
    storageClasses:
      - name: topolvm-provisioner
        default: true
        volumeBindingMode: WaitForFirstConsumer
        allowVolumeExpansion: true
```

> **重要提示:** `topolvm` 需要你在 `app-worker` 節點上**手動**準備好 LVM Volume Group (VG)，它才能正常運作。Helm Chart 不會幫你做這件事。

-----

### 總結

完成 P0-P3 的 Ansible 自動化後，你只需將上述 8 個 YAML 檔案 `git commit` 並 `git push` 到你的倉庫。

ArgoCD 會自動偵測到 `root-argocd-app.yaml`，然後部署 `infra-appset.yaml`，接著 `infra-appset.yaml` 會找到這 3 個新應用 (`ingress-nginx`, `metallb`, `topolvm`) 並自動將它們部署到集群中，P4 階段即告完成。