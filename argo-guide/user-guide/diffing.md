# 差異比較自訂

即使在成功同步操作後，應用程式仍有可能立即處於 `OutOfSync` 狀態。這可能的一些原因包括：

- 資訊清單中有錯誤，其中包含來自實際 K8s 規格的額外/未知欄位。在查詢 Kubernetes 以取得即時狀態時，這些額外欄位會被捨棄，
  導致 `OutOfSync` 狀態，表示偵測到遺失的欄位。
- 執行了同步（停用了刪減功能），並且有需要刪除的資源。
- 控制器或[變動中的 webhook](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#mutatingadmissionwebhook) 在物件提交至 Kubernetes 後對其進行了修改，使其與 Git 中的物件不同。
- Helm chart 使用了範本函式，例如 [`randAlphaNum`](https://github.com/helm/charts/blob/master/stable/redis/templates/secret.yaml#L16)，
  每次叫用 `helm template` 時都會產生不同的資料。
- 對於水平 Pod 自動擴展 (HPA) 物件，已知 HPA 控制器會以特定順序重新排序 `spec.metrics`
  。請參閱 [kubernetes issue #74099](https://github.com/kubernetes/kubernetes/issues/74099)。
  為了解決此問題，您可以在 Git 中以控制器
  偏好的相同順序對 `spec.metrics` 進行排序。

如果無法修正上游問題，Argo CD 允許您選擇性地忽略有問題資源的差異。
差異比較自訂可以在單一或多個應用程式資源層級或在系統層級進行設定。

## 應用程式層級組態

Argo CD 允許使用 [RFC6902 JSON patches](https://tools.ietf.org/html/rfc6902) 和 [JQ path expressions](<https://stedolan.github.io/jq/manual/#path(path_expression)>) 在特定的 JSON 路徑上忽略差異。也可以忽略由即時資源中 `metadata.managedFields` 中定義的特定管理者所擁有的欄位的差異。

以下範例應用程式設定為忽略所有部署中 `spec.replicas` 的差異：

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
```

請注意，`group` 欄位與不含版本的 [Kubernetes API 群組](https://kubernetes.io/docs/reference/using-api/#api-groups) 相關。
上述自訂可以縮小到具有指定名稱和可選命名空間的資源：

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: guestbook
      namespace: default
      jsonPointers:
        - /spec/replicas
```

若要忽略清單中的元素，您可以使用 JQ 路徑表達式根據項目內容來識別清單項目：

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jqPathExpressions:
        - .spec.template.spec.initContainers[] | select(.name == "injected-init-container")
```

若要忽略您即時資源中由特定管理者定義的欄位：

```yaml
spec:
  ignoreDifferences:
    - group: '*'
      kind: '*'
      managedFieldsManagers:
        - kube-controller-manager
```

上述組態將忽略屬於此應用程式的所有資源中由 `kube-controller-manager` 擁有的所有欄位的差異。

如果您的指標路徑中有斜線 `/`，您需要將其替換為 `~1` 字元。例如：

```yaml
spec:
  ignoreDifferences:
    - kind: Node
      jsonPointers:
        - /metadata/labels/node-role.kubernetes.io~1worker
```

## 系統層級組態

對於有已知問題的資源的比較，可以在系統層級進行自訂。可以在 `argocd-cm` ConfigMap 的 `resource.customizations` 索引鍵中為指定的群組和種類設定忽略的差異。以下是一個自訂的範例，它忽略了 `MutatingWebhookConfiguration` webhook 的 `caBundle` 欄位：

```yaml
data:
  resource.customizations.ignoreDifferences.admissionregistration.k8s.io_MutatingWebhookConfiguration:
    |
    jqPathExpressions:
    - '.webhooks[]?.clientConfig.caBundle'
```

資源自訂也可以設定為在系統層級忽略由 `managedField.manager` 所做的所有差異。以下範例顯示如何設定 Argo CD 以忽略 `kube-controller-manager` 在 `Deployment` 資源中所做的變更。

```yaml
data:
  resource.customizations.ignoreDifferences.apps_Deployment: |
    managedFieldsManagers:
    - kube-controller-manager
```

可以將 `ignoreDifferences` 設定為適用於由 Argo CD 實例管理的所有應用程式中的所有資源。為此，可以像下面的範例一樣設定資源自訂：

```yaml
data:
  resource.customizations.ignoreDifferences.all: |
    managedFieldsManagers:
    - kube-controller-manager
    jsonPointers:
    - /spec/replicas
```

許多資源的 `status` 欄位通常儲存在 Git/Helm 資訊清單中，在差異比較期間應予以忽略。`status` 欄位由
Kubernetes 控制器用於保留資源的目前狀態，因此不能作為期望的組態套用。

```yaml
data:
  resource.compareoptions: |
    # 停用指定資源類型中的狀態欄位差異比較
    # 'crd' - 自訂資源定義
    # 'all' - 所有資源 (預設)
    # 'none' - 停用
    ignoreResourceStatusField: all
```

如果您依賴於 `status` 欄位作為您期望狀態的一部分，雖然不建議這樣做，但可以使用 `ignoreResourceStatusField` 設定來設定此行為。

> [!NOTE]
> 由於 `CustomResourceDefinitions` 的 `status` 通常會提交到 Git，請考慮使用 `crd` 而非 `none`。

### 忽略由 AggregateRoles 所做的 RBAC 變更

如果您正在使用[聚合的 ClusterRoles](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#aggregated-clusterroles) 且不希望 Argo CD 將 `rules` 的變更偵測為漂移，您可以設定 `resource.compareoptions.ignoreAggregatedRoles: true`。這樣 Argo CD 將不再將這些變更偵測為需要同步的事件。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  resource.compareoptions: |
    # 停用指定資源類型中的狀態欄位差異比較
    ignoreAggregatedRoles: true
```

## CRD 中的已知 Kubernetes 類型（資源限制、磁碟區掛載等）

一些 CRD 重複使用了 Kubernetes 原始碼庫中定義的資料結構，因此繼承了自訂的
JSON/YAML 封送處理。自訂封送器可能會以稍微不同的格式序列化 CRD，這會在漂移偵測期間導致誤報。

一個典型的例子是 `argoproj.io/Rollout` CRD，它重複使用了 `core/v1/PodSpec` 資料結構。Pod 資源請求
可能會被 `IntOrString` 資料類型的自訂封送器重新格式化：

從：

```yaml
resources:
  requests:
    cpu: 100m
```

到：

```yaml
resources:
  requests:
    cpu: 0.1
```

解決方案是在 `argocd-cm` ConfigMap 的 `resource.customizations`
區段中指定哪些 CRD 欄位正在使用內建的 Kubernetes 類型：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  resource.customizations.knownTypeFields.argoproj.io_Rollout: |
    - field: spec.template.spec
      type: core/v1/PodSpec
```

支援的 Kubernetes 類型清單可在 [diffing_known_types.txt](https://raw.githubusercontent.com/argoproj/argo-cd/master/util/argo/normalizers/diffing_known_types.txt) 中找到，此外還有：

- `core/Quantity`
- `meta/v1/duration`

### JQ 路徑表達式逾時

預設情況下，JQPathExpression 的評估限制為一秒。如果您因為一個需要更多時間評估的複雜 JQPathExpression 而遇到「JQ patch execution timed out」的錯誤訊息，您可以透過在 `argocd-cmd-params-cm` ConfigMap 中設定 `ignore.normalizer.jq.timeout` 來延長逾時期間。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  ignore.normalizer.jq.timeout: '5s'
```
