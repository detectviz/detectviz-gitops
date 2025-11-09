# 控制 ApplicationSet 控制器修改 `Application` 資源的時機

ApplicationSet 控制器支援許多設定，可限制控制器對產生的應用程式進行變更的能力，例如，防止控制器刪除子應用程式。

這些設定可讓您控制應用程式及其對應的叢集資源（`Deployments`、`Services` 等）進行變更的時機和方式。

以下是一些可修改以變更 ApplicationSet 控制器資源處理行為的控制器設定。

## 試執行：防止 ApplicationSet 建立、修改或刪除所有應用程式

若要防止 ApplicationSet 控制器建立、修改或刪除任何 `Application` 資源，您可以啟用 `dry-run` 模式。這基本上會將控制器切換為「唯讀」模式，其中控制器協調迴圈將會執行，但不會修改任何資源。

若要啟用試執行，請將 `--dryrun true` 新增至 ApplicationSet Deployment 的容器啟動參數中。

有關如何將此參數新增至控制器的詳細步驟，請參閱下方的「如何修改 ApplicationSet 容器參數」。

## 受控應用程式修改原則

ApplicationSet 控制器支援一個 `--policy` 參數，該參數在啟動時（在控制器 Deployment 容器內）指定，並限制對受控 Argo CD `Application` 資源進行的修改類型。

`--policy` 參數有四個值：`sync`、`create-only`、`create-delete` 和 `create-update`。（`sync` 是預設值，如果未指定 `--policy` 參數，則會使用此值；其他原則如下所述）。

也可以為每個 ApplicationSet 設定此原則。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  # (...)
  syncPolicy:
    applicationsSync: create-only # create-update, create-delete sync

```

- 原則 `create-only`：防止 ApplicationSet 控制器修改或刪除應用程式。**警告**：它不會在刪除 ApplicationSet 時根據 [ownerReferences](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) 防止應用程式控制器刪除應用程式。
- 原則 `create-update`：防止 ApplicationSet 控制器刪除應用程式。允許更新。**警告**：它不會在刪除 ApplicationSet 時根據 [ownerReferences](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) 防止應用程式控制器刪除應用程式。
- 原則 `create-delete`：防止 ApplicationSet 控制器修改應用程式。允許刪除。
- 原則 `sync`：允許建立、更新和刪除。

如果設定了控制器參數 `--policy`，則它優先於 `applicationsSync` 欄位。可以透過將變數 `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_POLICY_OVERRIDE` 設定為 argocd-cmd-params-cm `applicationsetcontroller.enable.policy.override` 或直接使用控制器參數 `--enable-policy-override`（預設為 `false`）來允許每個 ApplicationSet 的同步原則。

### 原則 - `create-only`：防止 ApplicationSet 控制器修改和刪除應用程式

若要允許 ApplicationSet 控制器**建立** `Application` 資源，但防止任何進一步的修改，例如**刪除**或修改應用程式欄位，請在 ApplicationSet 控制器中新增此參數：

**警告**：「**刪除**」表示比較前後產生的應用程式後，有些應用程式不再存在的情況。它不表示應用程式根據 ApplicationSet 的 ownerReferences 被刪除的情況。請參閱[如何在刪除 ApplicationSet 時防止應用程式控制器刪除應用程式](#how-to-prevent-application-controller-from-deleting-applications-when-deleting-applicationset)

```
--policy create-only
```

在 ApplicationSet 層級

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  # (...)
  syncPolicy:
    applicationsSync: create-only
```

### 原則 - `create-update`：防止 ApplicationSet 控制器刪除應用程式

若要允許 ApplicationSet 控制器建立或修改 `Application` 資源，但防止應用程式被刪除，請將以下參數新增至 ApplicationSet 控制器 `Deployment`：

**警告**：「**刪除**」表示比較前後產生的應用程式後，有些應用程式不再存在的情況。它不表示應用程式根據 ApplicationSet 的 ownerReferences 被刪除的情況。請參閱[如何在刪除 ApplicationSet 時防止應用程式控制器刪除應用程式](#how-to-prevent-application-controller-from-deleting-applications-when-deleting-applicationset)

```
--policy create-update
```

這對於尋求額外保護以防止控制器產生的應用程式被刪除的使用者可能很有用。

在 ApplicationSet 層級

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  # (...)
  syncPolicy:
    applicationsSync: create-update
```

### 如何在刪除 ApplicationSet 時防止應用程式控制器刪除應用程式

預設情況下，`create-only` 和 `create-update` 原則對於在刪除 ApplicationSet 時防止刪除應用程式是無效的。
在這種情況下，您必須將 finalizer 設定為 ApplicationSet 以防止刪除，並使用背景級聯刪除。
如果您使用前景級聯刪除，則無法保證保留應用程式。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  # (...)
```

## 忽略對應用程式的某些變更

ApplicationSet 規格包含一個 `ignoreApplicationDifferences` 欄位，可讓您指定在比較應用程式時應忽略 ApplicationSet 的哪些欄位。

該欄位支援多個忽略規則。每個忽略規則可以指定要忽略的 `jsonPointers` 或 `jqPathExpressions` 清單。

您也可以選擇性地指定 `name` 以將忽略規則應用於特定應用程式，或省略 `name` 以將忽略規則應用於所有應用程式。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  ignoreApplicationDifferences:
    - jsonPointers:
        - /spec/source/targetRevision
    - name: some-app
      jqPathExpressions:
        - .spec.source.helm.values
```

### 允許暫時切換自動同步

忽略差異最常見的用例之一是允許暫時切換應用程式的自動同步。

例如，如果您有一個設定為自動同步應用程式的 ApplicationSet，您可能希望暫時停用特定應用程式的自動同步。您可以透過為 `spec.syncPolicy.automated` 欄位新增忽略規則來執行此操作。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  ignoreApplicationDifferences:
    - jsonPointers:
        - /spec/syncPolicy
```

### `ignoreApplicationDifferences` 的限制

當 ApplicationSet 被協調時，控制器會將 ApplicationSet 規格與其管理的每個應用程式的規格進行比較。如果存在任何差異，控制器將產生一個修補程式以更新應用程式以符合 ApplicationSet 規格。

產生的修補程式是 MergePatch。根據 MergePatch 文件，「當清單有變更時，現有清單將被新清單完全取代」。

這限制了當被忽略的欄位在清單中時 `ignoreApplicationDifferences` 的有效性。例如，如果您有一個具有多個來源的應用程式，並且您希望忽略其中一個來源的 `targetRevision` 的變更，則其他欄位或其他來源的變更將導致整個 `sources` 清單被取代，並且 `targetRevision` 欄位將被重設為 ApplicationSet 中定義的值。

例如，考慮這個 ApplicationSet：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  ignoreApplicationDifferences:
    - jqPathExpressions:
        - .spec.sources[] | select(.repoURL == "https://git.example.com/org/repo1").targetRevision
  template:
    spec:
      sources:
      - repoURL: https://git.example.com/org/repo1
        targetRevision: main
      - repoURL: https://git.example.com/org/repo2
        targetRevision: main
```

您可以自由變更 `repo1` 來源的 `targetRevision`，ApplicationSet 控制器不會覆寫您的變更。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
  - repoURL: https://git.example.com/org/repo1
    targetRevision: fix/bug-123
  - repoURL: https://git.example.com/org/repo2
    targetRevision: main
```

但是，如果您變更 `repo2` 來源的 `targetRevision`，ApplicationSet 控制器將覆寫整個 `sources` 欄位。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
  - repoURL: https://git.example.com/org/repo1
    targetRevision: main
  - repoURL: https://git.example.com/org/repo2
    targetRevision: main
```

> [!NOTE]
> ApplicationSet 控制器的[未來改進](https://github.com/argoproj/argo-cd/issues/15975) 可能會
> 消除此問題。例如，`ref` 欄位可能會成為合併鍵，允許 ApplicationSet
> 控制器產生並使用 StrategicMergePatch 而不是 MergePatch。然後，您可以透過 `ref` 鎖定特定
> 來源，忽略該來源中欄位的變更，而其他來源的變更不會導致被忽略的
> 欄位被覆寫。

## 防止在父應用程式被刪除時刪除 `Application` 的子資源

預設情況下，當 ApplicationSet 控制器刪除 `Application` 資源時，該應用程式的所有子資源也將被刪除（例如，應用程式的所有 `Deployments`、`Services` 等）。

若要防止在父應用程式被刪除時刪除應用程式的子資源，請將 `preserveResourcesOnDeletion: true` 欄位新增至 ApplicationSet 的 `syncPolicy`：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  # (...)
  syncPolicy:
    preserveResourcesOnDeletion: true
```

有關 `preserveResourcesOnDeletion` 的具體行為以及 ApplicationSet 控制器和 Argo CD 中刪除的更多資訊，請參閱[應用程式刪除](Application-Deletion.md) 頁面。

## 防止修改應用程式的子資源

對 ApplicationSet 所做的變更將傳播到 ApplicationSet 管理的應用程式，然後 Argo CD 會將應用程式變更傳播到底層叢集資源（根據[Argo CD 整合](Argo-CD-Integration.md)）。

應用程式變更傳播到叢集是由[自動同步設定](../../user-guide/auto_sync.md) 管理的，這些設定在 ApplicationSet `template` 欄位中引用：

- `spec.template.syncPolicy.automated`：如果啟用，應用程式的變更將自動傳播到叢集的叢集資源。
    - 在 ApplicationSet 範本中取消設定此項以「暫停」對 `Application` 資源管理的叢集資源的更新。
- `spec.template.syncPolicy.automated.prune`：預設情況下，當 Argo CD 偵測到資源不再在 Git 中定義時，自動同步不會刪除資源。
    - 為了額外安全，請將此設定為 false 以防止對備份 Git 儲存庫的意外變更影響叢集資源。

## 如何修改 ApplicationSet 容器啟動參數

有幾種方法可以修改 ApplicationSet 容器參數，以啟用上述設定。

### A) 使用 `kubectl edit` 修改叢集上的部署

編輯叢集上的 applicationset-controller `Deployment` 資源：
```
kubectl edit deployment/argocd-applicationset-controller -n argocd
```

找到 `.spec.template.spec.containers[0].command` 欄位，並新增所需的參數：
```yaml
spec:
    # (...)
  template:
    # (...)
    spec:
      containers:
      - command:
        - entrypoint.sh
        - argocd-applicationset-controller
        # 在此處插入新參數，例如：
        # --policy create-only
    # (...)
```

儲存並退出編輯器。等待一個新的 `Pod` 啟動，其中包含更新的參數。

### 或，B) 編輯 ApplicationSet 安裝的 `install.yaml` 資訊清單

您可以選擇修改用於安裝 ApplicationSet 控制器的安裝 YAML，而不是直接編輯叢集資源：

適用於 applicationset 版本小於 0.4.0。
```bash
# 克隆儲存庫

git clone https://github.com/argoproj/applicationset

# 簽出與您安裝的版本對應的版本。
git checkout "(applicationset 的版本)"
# 範例：git checkout "0.1.0"

cd applicationset/manifests

# 在文字編輯器中開啟 'install.yaml'，對 Deployment 進行與
# 上一節所述相同的修改。

# 將變更應用到叢集
kubectl apply -n argocd -f install.yaml
```

## 保留對應用程式註釋和標籤所做的變更

> [!NOTE]
> 使用上述的 [`ignoreApplicationDifferences`](#ignore-certain-changes-to-applications) 功能
> 可以在每個應用程式的基礎上實現相同的行為。但是，保留的欄位可以全域設定，此功能尚不適用於
> `ignoreApplicationDifferences`。

在 Kubernetes 中，將狀態儲存在註釋中是一種常見的做法，操作員經常會利用這一點。為了允許這樣做，可以設定一個 ApplicationSet 在協調時應保留的註釋清單。

例如，假設我們有一個從 ApplicationSet 建立的應用程式，但此後（在應用程式上）新增了一個自訂註釋和標籤，而該註釋和標籤在 `ApplicationSet` 資源中不存在：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # 此註釋和標籤僅存在於此應用程式上，而不在
  # 父 ApplicationSet 範本中：
  annotations:
    my-custom-annotation: some-value
  labels:
    my-custom-label: some-value
spec:
  # (...)
```

為了保留此註釋和標籤，我們可以像這樣使用 `ApplicationSet` 的 `preservedFields` 屬性：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  # (...)
  preservedFields:
    annotations: ["my-custom-annotation"]
    labels: ["my-custom-label"]
```

ApplicationSet 控制器在協調時會將此註釋和標籤保持原樣，即使它未在 ApplicationSet 本身的元資料中定義。

預設情況下，Argo CD 通知和 Argo CD 重新整理類型註釋也會被保留。

> [!NOTE]
> 也可以透過將逗號分隔的註釋和標籤清單分別傳遞給
> `ARGOCD_APPLICATIONSET_CONTROLLER_GLOBAL_PRESERVED_ANNOTATIONS` 和 `ARGOCD_APPLICATIONSET_CONTROLLER_GLOBAL_PRESERVED_LABELS` 來為控制器設定全域保留欄位。

## 偵錯對應用程式的意外變更

當 ApplicationSet 控制器對應用程式進行變更時，它會以偵錯層級記錄修補程式。若要查看這些
日誌，請在 `argocd` 命名空間中的 `argocd-cmd-params-cm` ConfigMap 中將日誌層級設定為偵錯：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd
data:
  applicationsetcontroller.log.level: debug
```

## 預覽變更

若要預覽 ApplicationSet 控制器將對應用程式進行的變更，您可以在試執行
模式下建立 AppSet。無論 AppSet 是否已存在，此方法都有效。

```shell
argocd appset create --dry-run ./appset.yaml -o json | jq -r '.status.resources[].name'
```

試執行將會使用將由
給定組態管理的應用程式填入傳回的 ApplicationSet 的狀態。您可以將其與現有的應用程式進行比較，以查看將會發生什麼變化。
