# 叢集產生器

在 Argo CD 中，受控叢集[儲存在 Argo CD 命名空間中的 Secrets](../../declarative-setup/#clusters) 內。ApplicationSet 控制器使用這些相同的 Secrets 來產生參數，以識別和鎖定可用的叢集。

對於每個註冊到 Argo CD 的叢集，叢集產生器會根據叢集 Secret 中找到的項目清單來產生參數。

它會自動為每個叢集的應用程式範本提供以下參數值：

- `name`
- `nameNormalized` *（「name」但正規化為僅包含小寫字母數字字元、「-」或「.」）*
- `server`
- `project` *（Secret 的「project」欄位，如果存在；否則，預設為 ''）*
- `metadata.labels.<key>` *（對於 Secret 中的每個標籤）*
- `metadata.annotations.<key>` *（對於 Secret 中的每個註釋）*

> [!NOTE]
> 如果您的叢集名稱包含無效的 Kubernetes 資源名稱字元（例如底線），請使用 `nameNormalized` 參數。這可以防止呈現無效的 Kubernetes 資源，例如 `my_cluster-app1`，而會將其轉換為 `my-cluster-app1`。


在 [Argo CD 叢集 Secrets](../../declarative-setup/#clusters) 中是描述叢集的資料欄位：
```yaml
kind: Secret
data:
  # 在 Kubernetes 中，這些欄位實際上是以 Base64 編碼的；為了方便起見，此處已解碼。
  # （當叢集產生器將它們作為參數傳遞時，它們同樣會被解碼）
  config: "{'tlsClientConfig':{'insecure':false}}"
  name: "in-cluster2"
  server: "https://kubernetes.default.svc"
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
# (...)
```

叢集產生器將自動識別使用 Argo CD 定義的叢集，並將叢集資料擷取為參數：
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
  - clusters: {} # 自動使用 Argo CD 中定義的所有叢集
  template:
    metadata:
      name: '{{.name}}-guestbook' # Secret 的 'name' 欄位
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{.server}}' # Secret 的 'server' 欄位
        namespace: guestbook
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/cluster)找到。*）

在此範例中，叢集 Secret 的 `name` 和 `server` 欄位用於填入 `Application` 資源的 `name` 和 `server`（然後用於鎖定該相同叢集）。

### 標籤選擇器

標籤選擇器可用於將目標叢集的範圍縮小到僅符合特定標籤的叢集：
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
  - clusters:
      selector:
        matchLabels:
          staging: "true"
        # 叢集產生器也支援 matchExpressions。
        #matchExpressions:
        #  - key: staging
        #    operator: In
        #    values:
        #      - "true"
  template:
  # (...)
```

這將匹配包含以下內容的 Argo CD 叢集 Secret：
```yaml
apiVersion: v1
kind: Secret
data:
  # (... 如上所述的欄位 ...)
metadata:
  labels:
    argocd.argoproj.io/secret-type: cluster
    staging: "true"
# (...)
```

叢集選擇器也支援基於集合的需求，就像[幾個核心 Kubernetes 資源](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#resources-that-support-set-based-requirements)所使用的那樣。

### 部署到本地叢集

在 Argo CD 中，「本地叢集」是安裝 Argo CD（和 ApplicationSet 控制器）的叢集。這是為了將其與「遠端叢集」區分開來，遠端叢集是那些[宣告式](../../declarative-setup/#clusters)或透過 [Argo CD CLI](../../getting_started.md/#5-register-a-cluster-to-deploy-apps-to-optional) 新增到 Argo CD 的叢集。

叢集產生器將自動鎖定本地和非本地叢集，適用於每個符合叢集選擇器的叢集。

如果您希望只將應用程式鎖定到遠端叢集（例如，您希望排除本地叢集），則請使用帶有標籤的叢集選擇器，例如：
```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/secret-type: cluster
        # 叢集產生器也支援 matchExpressions。
        #matchExpressions:
        #  - key: staging
        #    operator: In
        #    values:
        #      - "true"
```

此選擇器將不匹配預設的本地叢集，因為預設的本地叢集沒有 Secret（因此在該 Secret 上沒有 `argocd.argoproj.io/secret-type` 標籤）。任何根據該標籤進行選擇的叢集選擇器都將自動排除預設的本地叢集。

但是，如果您確實希望同時鎖定本地和非本地叢集，同時也使用標籤匹配，您可以在 Argo CD 網頁 UI 中為本地叢集建立一個 Secret：

1. 在 Argo CD 網頁 UI 中，選擇*設定*，然後選擇*叢集*。
2. 選擇您的本地叢集，通常名為 `in-cluster`。
3. 按一下*編輯*按鈕，並將叢集的*名稱*變更為其他值，例如 `in-cluster-local`。此處的任何其他值都可以。
4. 保持所有其他欄位不變。
5. 按一下*儲存*。

這些步驟可能看起來違反直覺，但變更本地叢集的其中一個預設值的行為會導致 Argo CD 網頁 UI 為此叢集建立一個新的 Secret。在 Argo CD 命名空間中，您現在應該會看到一個名為 `cluster-(叢集後綴)` 的 Secret 資源，其標籤為 `argocd.argoproj.io/secret-type": "cluster"`。您也可以[宣告式](../../declarative-setup/#clusters)或使用 CLI `argocd cluster add "(上下文名稱)" --in-cluster` 來建立本地[叢集 Secret](../../declarative-setup/#clusters)，而不是透過網頁 UI。

### 根據其 K8s 版本擷取叢集

也可以根據其 Kubernetes 版本擷取叢集。為此，需要在叢集 Secret 上將標籤 `argocd.argoproj.io/auto-label-cluster-info` 設定為 `true`。
設定完成後，控制器將使用其執行所在的 Kubernetes 版本動態標記叢集 Secret。若要擷取該值，您需要使用
`argocd.argoproj.io/kubernetes-version`，如下例所示：

```yaml
spec:
  goTemplate: true
  generators:
  - clusters:
      selector:
        matchLabels:
          argocd.argoproj.io/kubernetes-version: 1.28
        # 也支援 matchExpressions。
        #matchExpressions:
        #  - key: argocd.argoproj.io/kubernetes-version
        #    operator: In
        #    values:
        #      - "1.27"
        #      - "1.28"
```

### 透過 `values` 欄位傳遞額外的鍵值對

您可以透過叢集產生器的 `values` 欄位傳遞額外的、任意的字串鍵值對。透過 `values` 欄位新增的值會新增為 `values.(field)`

在此範例中，會根據叢集 Secret 上的匹配標籤傳遞一個 `revision` 參數值：
```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - clusters:
      selector:
        matchLabels:
          type: 'staging'
      # 一個用於任意參數的鍵值對應
      values:
        revision: HEAD # 預備叢集使用 HEAD 分支
  - clusters:
      selector:
        matchLabels:
          type: 'production'
      values:
        # 生產叢集使用不同的修訂版本值，用於 'stable' 分支
        revision: stable
  template:
    metadata:
      name: '{{.name}}-guestbook'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        # 每個產生器的叢集值欄位將會在此處被替換：
        targetRevision: '{{.values.revision}}'
        path: guestbook
      destination:
        server: '{{.server}}'
        namespace: guestbook
```

在此範例中，來自 `generators.clusters` 欄位的 `revision` 值會以 `values.revision` 的形式傳入範本，其值為 `HEAD` 或 `stable`（取決於是哪個產生器產生的參數集）。

> [!NOTE]
> `values.` 前綴總是會附加到透過 `generators.clusters.values` 欄位提供的值。在使用時，請確保在 `template` 中的參數名稱中包含此前綴。

在 `values` 中，我們也可以插入以下參數值（即與本頁開頭呈現的值相同）

- `name`
- `nameNormalized` *（「name」但正規化為僅包含小寫字母數字字元、「-」或「.」）*
- `server`
- `metadata.labels.<key>` *（對於 Secret 中的每個標籤）*
- `metadata.annotations.<key>` *（對於 Secret 中的每個註釋）*

擴展上面的範例，我們可以這樣做：

```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - clusters:
      selector:
        matchLabels:
          type: 'staging'
      # 一個用於任意參數的鍵值對應
      values:
        # 如果您的叢集 Secret 中有 `my-custom-annotation`，`revision` 將會被其替換。
        revision: '{{index .metadata.annotations "my-custom-annotation"}}'
        clusterName: '{{.name}}'
  - clusters:
      selector:
        matchLabels:
          type: 'production'
      values:
        # 生產叢集使用不同的修訂版本值，用於 'stable' 分支
        revision: stable
        clusterName: '{{.name}}'
  template:
    metadata:
      name: '{{.name}}-guestbook'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        # 每個產生器的叢集值欄位將會在此處被替換：
        targetRevision: '{{.values.revision}}'
        path: guestbook
      destination:
        # 在這種情況下，這相當於只使用 {{name}}
        server: '{{.values.clusterName}}'
        namespace: guestbook
```
### 將叢集資訊收集為平面清單

有時您可能需要收集叢集資訊，而無需為找到的每個叢集部署一個應用程式。
為此，您可以在叢集產生器中使用 `flatList` 選項。

以下是使用此選項的叢集產生器範例：
```yaml
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - clusters:
      selector:
        matchLabels:
          type: 'staging'
      flatList: true
  template:
    metadata:
      name: 'flat-list-guestbook'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        # 每個產生器的叢集值欄位將會在此處被替換：
        targetRevision: 'HEAD'
        path: helm-guestbook
        helm:
          values: |
            clusters:
            {{- range .clusters }}
              - name: {{ .name }}
            {{- end }}
      destination:
        # 在這種情況下，這相當於只使用 {{name}}
        server: 'my-cluster'
        namespace: guestbook
```

假設您有兩個符合名稱 cluster1 和 cluster2 的叢集 Secret，這將產生**單一**的以下應用程式：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: flat-list-guestbook
  namespace: guestbook
spec:
  project: "my-project"
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps/
    targetRevision: 'HEAD'
    path: helm-guestbook
    helm:
      values: |
        clusters:
          - name: cluster1
          - name: cluster2
```

如果您使用多個叢集產生器，每個都帶有 flatList 選項，則每個叢集產生器都會產生一個應用程式，因為我們無法簡單地合併每個產生器中可能不同的值和範本。
