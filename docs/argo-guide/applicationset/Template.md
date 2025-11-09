# 範本

ApplicationSet `spec` 的範本欄位用於產生 Argo CD `Application` 資源。

ApplicationSet 使用 [fasttemplate](https://github.com/valyala/fasttemplate)，但很快將被棄用，改用 Go 範本。

## 範本欄位

Argo CD 應用程式是透過將產生器的參數與範本的欄位（透過 `{{values}}`）結合而建立的，從中產生一個具體的 `Application` 資源並將其應用於叢集。

以下是來自叢集產生器的範本子欄位：

```yaml
# (...)
 template:
   metadata:
     name: '{{ .nameNormalized }}-guestbook'
   spec:
     source:
       repoURL: https://github.com/infra-team/cluster-deployments.git
       targetRevision: HEAD
       path: guestbook/{{ .nameNormalized }}
     destination:
       server: '{{ .server }}'
       namespace: guestbook
```

有關所有可用參數（例如 `.name`、`.nameNormalized` 等）的詳細資訊，請參閱[叢集產生器文件](./Generators-Cluster.md)。

範本子欄位直接對應於 [Argo CD `Application` 資源的規格](../../declarative-setup.md#applications)：

- `project` 指的是正在使用的 [Argo CD 專案](../../user-guide/projects.md)（此處可以使用 `default` 來利用預設的 Argo CD 專案）
- `source` 定義從哪個 Git 儲存庫中擷取所需的應用程式資訊清單
    - **repoURL**：儲存庫的 URL（例如 `https://github.com/argoproj/argocd-example-apps.git`）
    - **targetRevision**：儲存庫的修訂版本（標籤/分支/提交）（例如 `HEAD`）
    - **path**：儲存庫中 Kubernetes 資訊清單（和/或 Helm、Kustomize、Jsonnet 資源）所在的路徑
- `destination`：定義要部署到的 Kubernetes 叢集/命名空間
    - **name**：要部署到的叢集名稱（在 Argo CD 中）
    - **server**：叢集的 API 伺服器 URL（範例：`https://kubernetes.default.svc`）
    - **namespace**：部署 `source` 中資訊清單的目標命名空間（範例：`my-app-namespace`）

注意：

- 被引用的叢集必須已在 Argo CD 中定義，ApplicationSet 控制器才能使用它們
- 只能指定 `name` 或 `server` **其中一個**：如果兩者都指定，則會傳回錯誤。
- 使用 git 產生器時，簽章驗證不適用於範本化的 `project` 欄位。

範本的 `metadata` 欄位也可用於設定應用程式 `name`，或為應用程式新增標籤或註釋。

雖然 ApplicationSet 規格提供了一種基本的範本形式，但它並非旨在取代 Kustomize、Helm 或 Jsonnet 等工具的完整組態管理功能。

### 將 ApplicationSet 資源作為 Helm 圖表的一部分部署

ApplicationSet 使用與 Helm 相同的範本表示法 (`{{}}`)。當 Helm 渲染圖表範本時，它也會
處理用於 ApplicationSet 渲染的範本。如果 ApplicationSet 範本使用如下函式：

```yaml
    metadata:
      name: '{{ "guestbook" | normalize }}'
```

Helm 將擲回類似以下的錯誤：`function "normalize" not defined`。如果 ApplicationSet 範本使用如下的產生器參數：

```yaml
    metadata:
      name: '{{.cluster}}-guestbook'
```

Helm 將會靜默地將 `.cluster` 替換為空字串。

為避免這些錯誤，請將範本寫為 Helm 字串文字。例如：

```yaml
    metadata:
      name: '{{`{{ .cluster | normalize }}`}}-guestbook'
```

這**僅**適用於您使用 Helm 來部署 ApplicationSet 資源的情況。

## 產生器範本

除了在 `ApplicationSet` 資源的 `.spec.template` 中指定範本之外，也可以在產生器中指定範本。這對於覆寫 `spec` 層級範本的值很有用。

產生器的 `template` 欄位優先於 `spec` 的範本欄位：

- 如果兩個範本都包含相同的欄位，則將使用產生器的欄位值。
- 如果這些範本的欄位中只有一個有值，則將使用該值。

因此，產生器範本可以被視為對外部 `spec` 層級範本欄位的修補程式。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - list:
      elements:
        - cluster: engineering-dev
          url: https://kubernetes.default.svc
      template:
        metadata: {}
        spec:
          project: "default"
          source:
            targetRevision: HEAD
            repoURL: https://github.com/argoproj/argo-cd.git
            # 此處產生新的路徑值：
            path: 'applicationset/examples/template-override/{{ .nameNormalized }}-override'
          destination: {}

  template:
    metadata:
      name: '{{ .nameNormalized }}-guestbook'
    spec:
      project: "default"
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        # 這個「預設」值未使用：它被上面的產生器範本路徑所取代
        path: applicationset/examples/template-override/default
      destination:
        server: '{{ .server }}'
        namespace: guestbook
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/template-override)找到。*）

在此範例中，ApplicationSet 控制器將使用由清單產生器產生的 `path` 來產生 `Application` 資源，而不是使用在 `.spec.template` 中定義的 `path` 值。

## 範本修補

範本化僅適用於字串類型。然而，某些使用案例可能需要在其他類型上套用範本化。

範例：

- 有條件地設定自動同步原則。
- 有條件地將修剪布林值切換為 `true`。
- 從清單中新增多個 helm 值檔案。

`templatePatch` 功能可啟用進階範本化，支援 `json` 和 `yaml`。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  goTemplate: true
  generators:
  - list:
      elements:
        - cluster: engineering-dev
          url: https://kubernetes.default.svc
          autoSync: true
          prune: true
          valueFiles:
            - values.large.yaml
            - values.debug.yaml
  template:
    metadata:
      name: '{{ .nameNormalized }}-deployment'
    spec:
      project: "default"
      source:
        repoURL: https://github.com/infra-team/cluster-deployments.git
        targetRevision: HEAD
        path: guestbook/{{ .nameNormalized }}
      destination:
        server: '{{ .server }}'
        namespace: guestbook
  templatePatch: |
    spec:
      source:
        helm:
          valueFiles:
          {{- range $valueFile := .valueFiles }}
            - {{ $valueFile }}
          {{- end }}
    {{- if .autoSync }}
      syncPolicy:
        automated:
          prune: {{ .prune }}
    {{- end }}
```

> [!IMPORTANT]
> `templatePatch` 僅在啟用 [go 範本化](../applicationset/GoTemplate.md) 時才有效。
> 這意味著 `spec` 下的 `goTemplate` 欄位需要設定為 `true`，範本修補才能運作。

> [!IMPORTANT]
> `templatePatch` 可以對範本套用任意變更。如果參數包含不受信任的使用者輸入，
> 則可能可以將惡意變更注入範本中。建議僅在
> 可信任的輸入下使用 `templatePatch`，或在使用之前仔細逸出輸入。將輸入傳遞給 `toJson` 應該有助於
> 防止（例如）使用者成功注入帶有換行符的字串。
>
> `spec.project` 欄位在 `templatePatch` 中不受支援。如果您需要變更專案，可以使用
> `template` 欄位中的 `spec.project` 欄位。

> [!IMPORTANT]
> 在撰寫 `templatePatch` 時，您正在建立一個修補程式。因此，如果修補程式包含一個空的 `spec: # 裡面沒有東西`，它將有效地清除現有的欄位。有關此行為的範例，請參閱 [#17040](https://github.com/argoproj/argo-cd/issues/17040)。
