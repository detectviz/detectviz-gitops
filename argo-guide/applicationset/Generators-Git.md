# Git 產生器

Git 產生器包含兩種子類型：Git 目錄產生器和 Git 檔案產生器。

> [!WARNING]
> Git 產生器通常用於讓（非管理員）開發人員更容易地建立應用程式。
> 如果您的 ApplicationSet 中的 `project` 欄位是範本化的，開發人員可能會在具有過多權限的專案下建立應用程式。
> 對於具有範本化 `project` 欄位的 ApplicationSets，[事實來源**必須**由管理員控制](./Security.md#templated-project-field)
> - 在 git 產生器的情況下，PR 必須需要管理員批准。
> - 對於具有範本化 `project` 欄位的 ApplicationSets，Git 產生器不支援簽章驗證。
> - 對於具有範本化 `project` 欄位的 ApplicationSets，您只能使用「非範圍」儲存庫（請參閱下方的「ApplicationSets 的儲存庫憑證」）。

## Git 產生器：目錄

Git 目錄產生器是 Git 產生器的兩種子類型之一，它使用指定 Git 儲存庫的目錄結構來產生參數。

假設您有一個具有以下目錄結構的 Git 儲存庫：
```
├── argo-workflows
│   ├── kustomization.yaml
│   └── namespace-install.yaml
└── prometheus-operator
    ├── Chart.yaml
    ├── README.md
    ├── requirements.yaml
    └── values.yaml
```

此儲存庫包含兩個目錄，每個目錄對應要部署的工作負載之一：

- 一個 Argo Workflow 控制器的 kustomization YAML 檔案
- 一個 Prometheus Operator Helm 圖表

我們可以使用此範例來部署這兩個工作負載：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      directories:
      - path: applicationset/examples/git-generator-directory/cluster-addons/*
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
      syncPolicy:
        syncOptions:
        - CreateNamespace=true
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-directory)找到。*）

產生器參數為：

- `{{.path.path}}`：Git 儲存庫中與 `path` 萬用字元匹配的目錄路徑。
- `{{index .path.segments n}}`：Git 儲存庫中與 `path` 萬用字元匹配的目錄路徑，分割為陣列元素（`n` - 陣列索引）
- `{{.path.basename}}`：對於 Git 儲存庫中與 `path` 萬用字元匹配的任何目錄路徑，將擷取最右側的路徑名稱（例如 `/directory/directory2` 將產生 `directory2`）。
- `{{.path.basenameNormalized}}`：此欄位與 `path.basename` 相同，但不支援的字元會被取代為 `-`（例如，`/directory/directory_2` 的 `path` 和 `directory_2` 的 `path.basename` 在此處將產生 `directory-2`）。

**注意**：最右側的路徑名稱始終成為 `{{.path.basename}}`。例如，對於 `- path: /one/two/three/four`，`{{.path.basename}}` 是 `four`。

**注意**：如果指定了 `pathParamPrefix` 選項，則上述所有與 `path` 相關的參數名稱都將以指定的值和一個點分隔符號為前綴。例如，如果 `pathParamPrefix` 是 `myRepo`，則產生的參數名稱將是 `.myRepo.path` 而不是 `.path`。在 Matrix 產生器中，如果兩個子產生器都是 Git 產生器，則必須使用此選項（以避免在合併子產生器的項目時發生衝突）。

每當將新的 Helm 圖表/Kustomize YAML/應用程式/普通子目錄新增到 Git 儲存庫時，ApplicationSet 控制器都會偵測到此變更，並自動在新 `Application` 資源中部署產生的資訊清單。

與其他產生器一樣，叢集**必須**已在 Argo CD 中定義，才能為它們產生應用程式。

### 排除目錄

Git 目錄產生器會自動排除以 `.` 開頭的目錄（例如 `.git`）。

Git 目錄產生器還支援 `exclude` 選項，以從 ApplicationSet 控制器的掃描中排除儲存庫中的目錄：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      directories:
      - path: applicationset/examples/git-generator-directory/excludes/cluster-addons/*
      - path: applicationset/examples/git-generator-directory/excludes/cluster-addons/exclude-helm-guestbook
        exclude: true
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-directory/excludes)找到。*）

此範例會將 `exclude-helm-guestbook` 目錄從為此 `ApplicationSet` 資源掃描的目錄清單中排除。

> [!NOTE]
> **排除規則的優先順序高於包含規則**
>
> 如果一個目錄至少符合一個 `exclude` 模式，它將被排除。或者，換句話說，*排除規則優先於包含規則。*
>
> 作為推論，哪些目錄被包含/排除不受 `directories` 欄位清單中 `path` 的順序影響（因為，如上所述，排除規則始終優先於包含規則）。

例如，對於這些目錄：

```
.
└── d
    ├── e
    ├── f
    └── g
```
假設您要包含 `/d/e`，但排除 `/d/f` 和 `/d/g`。這樣做**行不通**：

```yaml
- path: /d/e
  exclude: false
- path: /d/*
  exclude: true
```
為什麼？因為排除 `/d/*` 的排除規則將優先於 `/d/e` 的包含規則。當 ApplicationSet 控制器處理 Git 儲存庫中的 `/d/e` 路徑時，控制器會偵測到至少符合一個排除規則，因此不應掃描該目錄。

您應該這樣做：

```yaml
- path: /d/*
- path: /d/f
  exclude: true
- path: /d/g
  exclude: true
```

或者，一個更簡短的方式（使用 [path.Match](https://golang.org/pkg/path/#Match) 語法）將是：

```yaml
- path: /d/*
- path: /d/[fg]
  exclude: true
```

### Git 儲存庫的根目錄

Git 目錄產生器可以設定為從 git 儲存庫的根目錄部署，方法是提供 `*` 作為 `path`。

若要排除目錄，您只需要放入不想部署的目錄名稱/[path.Match](https://golang.org/pkg/path/#Match) 即可。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/example/example-repo.git
      revision: HEAD
      directories:
      - path: '*'
      - path: donotdeploy
        exclude: true
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/example/example-repo.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
```

### 透過 `values` 欄位傳遞額外的鍵值對

您可以透過 git 目錄產生器的 `values` 欄位傳遞額外的、任意的字串鍵值對。透過 `values` 欄位新增的值會新增為 `values.(field)`。

在此範例中，傳遞了一個 `cluster` 參數值。它從 `path` 變數中插值，然後用於確定目標命名空間。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/example/example-repo.git
      revision: HEAD
      directories:
      - path: '*'
      values:
        cluster: '{{.path.basename}}'
  template:
    metadata:
      name: '{{.path.basename}}'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/example/example-repo.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.values.cluster}}'
```

> [!NOTE]
> `values.` 前綴總是會附加到透過 `generators.git.values` 欄位提供的值。在使用時，請確保在 `template` 中的參數名稱中包含此前綴。

在 `values` 中，我們也可以插入上面提到的由 git 目錄產生器設定的所有欄位。

## Git 產生器：檔案

Git 檔案產生器是 Git 產生器的第二個子類型。Git 檔案產生器使用在指定儲存庫中找到的 JSON/YAML 檔案的內容來產生參數。

假設您有一個具有以下目錄結構的 Git 儲存庫：
```
├── apps
│   └── guestbook
│       ├── guestbook-ui-deployment.yaml
│       ├── guestbook-ui-svc.yaml
│       └── kustomization.yaml
├── cluster-config
│   └── engineering
│       ├── dev
│       │   └── config.json
│       └── prod
│           └── config.json
└── git-generator-files.yaml
```

目錄為：

- `guestbook` 包含一個簡單的訪客留言簿應用程式的 Kubernetes 資源
- `cluster-config` 包含描述個別工程叢集的 JSON/YAML 檔案：一個用於 `dev`，一個用於 `prod`。
- `git-generator-files.yaml` 是將 `guestbook` 部署到指定叢集的範例 `ApplicationSet` 資源。

`config.json` 檔案包含描述叢集的資訊（以及額外的範例資料）：
```json
{
  "aws_account": "123456",
  "asset_id": "11223344",
  "cluster": {
    "owner": "cluster-admin@company.com",
    "name": "engineering-dev",
    "address": "https://1.2.3.4"
  }
}
```

Git 產生器會自動偵測包含 `config.json` 檔案變更的 Git 提交，並將這些檔案的內容解析並轉換為範本參數。以下是為上述 JSON 產生的參數：
```text
aws_account: 123456
asset_id: 11223344
cluster.owner: cluster-admin@company.com
cluster.name: engineering-dev
cluster.address: https://1.2.3.4
```


所有找到的 `config.json` 檔案產生的參數將會被替換到 ApplicationSet 範本中：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      files:
      - path: "applicationset/examples/git-generator-files-discovery/cluster-config/**/config.json"
  template:
    metadata:
      name: '{{.cluster.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: "applicationset/examples/git-generator-files-discovery/apps/guestbook"
      destination:
        server: '{{.cluster.address}}'
        namespace: guestbook
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-files-discovery)找到。*）

在 `cluster-config` 目錄下找到的任何 `config.json` 檔案都將根據指定的 `path` 萬用字元模式進行參數化。在每個檔案中，JSON 欄位都會被展平為鍵/值對，此 ApplicationSet 範例在範本中使用 `cluster.address` 和 `cluster.name` 參數。

與其他產生器一樣，叢集**必須**已在 Argo CD 中定義，才能為它們產生應用程式。

除了從組態檔中展平的鍵/值對之外，還提供了以下產生器參數：

- `{{.path.path}}`：Git 儲存庫中包含匹配組態檔的目錄路徑。範例：`/clusters/clusterA`，如果組態檔是 `/clusters/clusterA/config.json`
- `{{index .path.segments n}}`：Git 儲存庫中匹配組態檔的路徑，分割為陣列元素（`n` - 陣列索引）。範例：`index .path.segments 0: clusters`、`index .path.segments 1: clusterA`
- `{{.path.basename}}`：包含組態檔的目錄路徑的基底名稱（例如，在上面的範例中是 `clusterA`。）
- `{{.path.basenameNormalized}}`：此欄位與 `.path.basename` 相同，但不支援的字元會被取代為 `-`（例如，`/directory/directory_2` 的 `path` 和 `directory_2` 的 `.path.basename` 在此處將產生 `directory-2`）。
- `{{.path.filename}}`：匹配的檔名。例如，在上面的範例中是 `config.json`。
- `{{.path.filenameNormalized}}`：匹配的檔名，但不支援的字元會被取代為 `-`。

**注意**：最右側的**目錄**名稱始終成為 `{{.path.basename}}`。例如，從 `- path: /one/two/three/four/config.json`，`{{.path.basename}}` 將是 `four`。
檔名始終可以使用 `{{.path.filename}}` 來存取。

**注意**：如果指定了 `pathParamPrefix` 選項，則上述所有與 `path` 相關的參數名稱都將以指定的值和一個點分隔符號為前綴。例如，如果 `pathParamPrefix` 是 `myRepo`，則產生的參數名稱將是 `myRepo.path` 而不是 `path`。在 Matrix 產生器中，如果兩個子產生器都是 Git 產生器，則必須使用此選項（以避免在合併子產生器的項目時發生衝突）。

**注意**：Git 檔案產生器的預設行為非常貪婪。如需更多資訊，請參閱[Git 檔案產生器 Globbing](./Generators-Git-File-Globbing.md)。

### 排除檔案

Git 檔案產生器也支援 `exclude` 選項，以從 ApplicationSet 控制器的掃描中排除儲存庫中的檔案：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - git:
        repoURL: https://github.com/argoproj/argo-cd.git
        revision: HEAD
        files:
          - path: "applicationset/examples/git-generator-files-discovery/cluster-config/**/config.json"
          - path: "applicationset/examples/git-generator-files-discovery/cluster-config/*/dev/config.json"
            exclude: true
  template:
    metadata:
      name: '{{.cluster.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: "applicationset/examples/git-generator-files-discovery/apps/guestbook"
      destination:
        server: https://kubernetes.default.svc
        #server: '{{.cluster.address}}'
        namespace: guestbook
```

此範例會將 `dev` 目錄中的 `config.json` 檔案從為此 `ApplicationSet` 資源掃描的檔案清單中排除。

（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-files-discovery/excludes)找到。*）

### 透過 `values` 欄位傳遞額外的鍵值對

您可以透過 git 檔案產生器的 `values` 欄位傳遞額外的、任意的字串鍵值對。透過 `values` 欄位新增的值會新增為 `values.(field)`。

在此範例中，傳遞了一個 `base_dir` 參數值。它從 `path` 片段中插值，然後用於確定來源路徑。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      files:
      - path: "applicationset/examples/git-generator-files-discovery/cluster-config/**/config.json"
      values:
        base_dir: "{{index .path.segments 0}}/{{index .path.segments 1}}/{{index .path.segments 2}}"
  template:
    metadata:
      name: '{{.cluster.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: "{{.values.base_dir}}/apps/guestbook"
      destination:
        server: '{{.cluster.address}}'
        namespace: guestbook
```

> [!NOTE]
> `values.` 前綴總是會附加到透過 `generators.git.values` 欄位提供的值。在使用時，請確保在 `template` 中的參數名稱中包含此前綴。

在 `values` 中，我們也可以插入上面提到的由 git 檔案產生器設定的所有欄位。

## Git 輪詢間隔

使用 Git 產生器時，ApplicationSet 控制器預設每 3 分鐘輪詢一次 Git
儲存庫以偵測變更，除非
`ARGOCD_APPLICATIONSET_CONTROLLER_REQUEUE_AFTER` 環境變數設定了不同的預設值。
您可以使用
`requeueAfterSeconds` 為每個 ApplicationSet 自訂此間隔。

> [!NOTE]
> Git 產生器使用 ArgoCD Repo Server 從 Git 擷取檔案
> 和目錄清單。因此，Git 產生器會受到
> Repo Server 的修訂版本快取到期設定的影響
> （請參閱 [argocd-cm.yaml](../argocd-cm-yaml.md/#:~:text=timeout.reconciliation%3A) 中 `timeout.reconciliation` 參數的說明）。
> 如果此值超過設定的 Git 輪詢間隔，
> Git 產生器可能無法看到新提交的檔案或目錄，
> 直到先前的快取項目到期為止。
>
## `argocd.argoproj.io/application-set-refresh` 註釋

設定 `argocd.argoproj.io/application-set-refresh` 註釋
（為任何值）會觸發 ApplicationSet 重新整理。此註釋
會強制 Git 提供者直接解析 Git 參考，繞過
修訂版本快取。ApplicationSet 控制器會在協調後移除此
註釋。

## Webhook 組態

為了消除輪詢延遲，可以將 ApplicationSet webhook
伺服器設定為接收 webhook 事件。ApplicationSet
支援來自 GitHub 和 GitLab 的 Git webhook 通知。
以下說明如何為 GitHub 設定 Git webhook，但
相同的流程也應適用於其他提供者。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      # 使用 Git 產生器時，ApplicationSet 控制器會每隔 `requeueAfterSeconds` 間隔（預設為每 3 分鐘）輪詢一次以偵測變更。
      requeueAfterSeconds: 180
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      # ...
```

> [!NOTE]
> ApplicationSet 控制器 webhook 不使用與[此處](../webhook.md)定義的 API 伺服器相同的 webhook。ApplicationSet 將 webhook 伺服器公開為 ClusterIP 類型的服務。需要建立一個 ApplicationSet 特定的 Ingress 資源以將此服務公開給 webhook 來源。

### 1. 在 Git 提供者中建立 webhook

在您的 Git 提供者中，導覽至可以設定 webhook 的設定頁面。
在 Git 提供者中設定的承載 URL 應使用您 ApplicationSet 執行個體的 `/api/webhook` 端點
（例如 `https://applicationset.example.com/api/webhook`）。如果您希望使用共用密鑰，請在密鑰中輸入任意值。此值將在下一步中設定 webhook 時使用。

![新增 Webhook](../../assets/applicationset/webhook-config.png "新增 Webhook")

> [!NOTE]
> 在 GitHub 中建立 webhook 時，「內容類型」需要設定為「application/json」。用於處理 hook 的函式庫不支援預設值「application/x-www-form-urlencoded」

### 2. 使用 webhook 密鑰設定 ApplicationSet（可選）

設定 webhook 共用密鑰是可選的，因為即使使用未經身份驗證的 webhook 事件，ApplicationSet
仍會重新整理由 Git 產生器產生的應用程式。這樣做是安全的，因為
webhook 承載的內容被視為不受信任，只會導致
應用程式重新整理（此過程已每三分鐘發生一次）。如果 ApplicationSet
可公開存取，則建議設定 webhook 密鑰以防止 DDoS 攻擊。

在 `argocd-secret` Kubernetes secret 中，包含步驟 1 中設定的 Git 提供者的 webhook 密鑰。

編輯 Argo CD Kubernetes secret：

```bash
kubectl edit secret argocd-secret -n argocd
```

提示：為了方便輸入密鑰，Kubernetes 支援在 `stringData` 欄位中輸入密鑰，
這可以省去您對值進行 base64 編碼並將其複製到 `data` 欄位的麻煩。
只需將步驟 1 中建立的共用 webhook 密鑰複製到 `stringData` 欄位下對應的
GitHub/GitLab/BitBucket 鍵即可：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
data:
...

stringData:
  # github webhook 密鑰
  webhook.github.secret: shhhh! it's a github secret

  # gitlab webhook 密鑰
  webhook.gitlab.secret: shhhh! it's a gitlab secret
```

儲存後，請重新啟動 ApplicationSet pod 以使變更生效。

## ApplicationSets 的儲存庫憑證
如果您的 [ApplicationSets](index.md) 使用需要憑證才能存取的儲存庫，**而且**
ApplicationSet 專案欄位是範本化的（即 ApplicationSet 的 `project` 欄位包含 `{{ ... }}`），您需要將儲存庫新增為「非專案範圍」儲存庫。
- 透過 UI 執行此操作時，請在下拉式選單中將此設定為**空白**值。
- 透過 CLI 執行此操作時，請確保您**不要**提供 `--project` 參數（[argocd repo add 文件](../../user-guide/commands/argocd_repo_add.md)）
- 透過宣告式執行此操作時，請確保您在 `stringData:` 下**沒有**定義 `project:`（[完整的 yaml 範例](../argocd-repositories-yaml.md)）
