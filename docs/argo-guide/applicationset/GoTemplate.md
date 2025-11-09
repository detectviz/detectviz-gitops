# Go 範本

## 簡介

ApplicationSet 能夠使用 [Go 文字範本](https://pkg.go.dev/text/template)。若要啟用此功能，請在
您的 ApplicationSet 資訊清單中新增 `goTemplate: true`。

除了預設的 Go 文字範本函式外，還提供 [Sprig 函式庫](https://masterminds.github.io/sprig/)（`env`、`expandenv` 和 `getHostByName` 除外）。

額外的 `normalize` 函式可將任何字串參數轉換為有效的 DNS 名稱，方法是將無效字元
取代為連字號，並截斷至 253 個字元。這對於使參數安全（例如應用程式
名稱）很有用。

另一個新增的 `slugify` 函式，預設會清理並智慧截斷（它不會將單字切成兩半）。此函式接受幾個引數：

- 第一個引數（如果提供）是一個整數，指定 slug 的最大長度。
- 第二個引數（如果提供）是一個布林值，表示是否啟用智慧截斷。
- 最後一個引數（如果提供）是需要進行 slugify 的輸入名稱。

#### 使用範例

```
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: test-appset
spec:
  ...
  template:
    metadata:
      name: 'hellos3-{{.name}}-{{ cat .branch | slugify 23 }}'
      annotations:
        label-1: '{{ cat .branch | slugify }}'
        label-2: '{{ cat .branch | slugify 23 }}'
        label-3: '{{ cat .branch | slugify 50 false }}'
```

如果您想自訂 [text/template 定義的選項](https://pkg.go.dev/text/template#Template.Option)，您可以
在您的 ApplicationSet 中 `goTemplate: true` 旁邊新增 `goTemplateOptions: ["opt1", "opt2", ...]` 鍵。請注意，在
撰寫本文時，只有一個有用的選項定義，即 `missingkey=error`。

建議的 `goTemplateOptions` 設定是 `["missingkey=error"]`，這可確保如果您的範本查閱未定義的值
，則會報告錯誤，而不是被靜默忽略。為了向後相容，這目前不是預設
行為。

## 動機

Go 範本是 Go 語言中用於字串範本化的標準。它也比 fasttemplate（預設的範本
引擎）更強大，因為它允許進行複雜的範本邏輯。

## 限制

Go 範本是按欄位套用的，且僅適用於字串欄位。以下是一些 Go 文字範本**無法**
辦到的範例：

- 範本化布林值欄位。

        ::yaml
        apiVersion: argoproj.io/v1alpha1
        kind: ApplicationSet
        spec:
          goTemplate: true
          goTemplateOptions: ["missingkey=error"]
          template:
            spec:
              source:
                helm:
                  useCredentials: "{{.useCredentials}}"  # 此欄位不可範本化，因為它是布林值欄位。

- 範本化物件欄位：

        ::yaml
        apiVersion: argoproj.io/v1alpha1
        kind: ApplicationSet
        spec:
          goTemplate: true
          goTemplateOptions: ["missingkey=error"]
          template:
            spec:
              syncPolicy: "{{.syncPolicy}}"  # 此欄位不可範本化，因為它是物件欄位。

- 在欄位之間使用控制關鍵字：

        ::yaml
        apiVersion: argoproj.io/v1alpha1
        kind: ApplicationSet
        spec:
          goTemplate: true
          goTemplateOptions: ["missingkey=error"]
          template:
            spec:
              source:
                helm:
                  parameters:
                  # 每個欄位都被評估為一個獨立的範本，因此第一個欄位將會失敗並出現錯誤。
                  - name: "{{range .parameters}}"
                  - name: "{{.name}}"
                    value: "{{.value}}"
                  - name: throw-away
                    value: "{{end}}"

- 使用 Git 產生器時，不支援對範本化的 `project` 欄位進行簽章驗證。

        ::yaml
        apiVersion: argoproj.io/v1alpha1
        kind: ApplicationSet
        spec:
          goTemplate: true
          template:
            spec:
              project: {{.project}}


## 遷移指南

### 全域

您所有的範本都必須將參數取代為 GoTemplate 語法：

範例：`{{ some.value }}` 變成 `{{ .some.value }}`

### 叢集產生器

啟用 Go 範本化後，`{{ .metadata }}` 會變成一個物件。

- `{{ metadata.labels.my-label }}` 變成 `{{ index .metadata.labels "my-label" }}`
- `{{ metadata.annotations.my/annotation }}` 變成 `{{ index .metadata.annotations "my/annotation" }}`

### Git 產生器

啟用 Go 範本化後，`{{ .path }}` 會變成一個物件。因此，必須對 Git
產生器的範本化進行一些變更：

- `{{ path }}` 變成 `{{ .path.path }}`
- `{{ path.basename }}` 變成 `{{ .path.basename }}`
- `{{ path.basenameNormalized }}` 變成 `{{ .path.basenameNormalized }}`
- `{{ path.filename }}` 變成 `{{ .path.filename }}`
- `{{ path.filenameNormalized }}` 變成 `{{ .path.filenameNormalized }}`
- `{{ path[n] }}` 變成 `{{ index .path.segments n }}`
- 如果在檔案產生器中使用 `{{ values }}`，則變成 `{{ .values }}`

以下是一個範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
spec:
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      revision: HEAD
      directories:
      - path: applicationset/examples/git-generator-directory/cluster-addons/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
```

變成

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
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
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
```

也可以使用 Sprig 函式手動建構路徑變數：

| `goTemplate: false` | `goTemplate: true` | `goTemplate: true` + Sprig |
| ------------ | ----------- | --------------------- |
| `{{path}}` | `{{.path.path}}` | `{{.path.path}}` |
| `{{path.basename}}` | `{{.path.basename}}` | `{{base .path.path}}` |
| `{{path.filename}}` | `{{.path.filename}}` | `{{.path.filename}}` |
| `{{path.basenameNormalized}}` | `{{.path.basenameNormalized}}` | `{{normalize .path.path}}` |
| `{{path.filenameNormalized}}` | `{{.path.filenameNormalized}}` | `{{normalize .path.filename}}` |
| `{{path[N]}}` | `-` | `{{index .path.segments N}}` |

## 可用的範本函式

ApplicationSet 控制器提供：

- 除了 `env`、`expandenv` 和 `getHostByName` 之外的所有 [sprig](http://masterminds.github.io/sprig/) Go 範本函式
- `normalize`：清理輸入，使其符合以下規則：
    1. 不超過 253 個字元
    2. 僅包含小寫字母數字字元、「-」或「.」
    3. 以字母數字字元開頭和結尾

- `slugify`：像 `normalize` 一樣清理，並像 [簡介](#introduction) 部分所述的那樣智慧截斷（它不會將單字切成兩半）。
- `toYaml` / `fromYaml` / `fromYamlArray` 類似 helm 的函式


## 範例

### 基本 Go 範本用法

此範例顯示基本的字串參數替換。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - list:
      elements:
      - cluster: engineering-dev
        url: https://1.2.3.4
      - cluster: engineering-prod
        url: https://2.4.6.8
      - cluster: finance-preprod
        url: https://9.8.7.6
  template:
    metadata:
      name: '{{.cluster}}-guestbook'
    spec:
      project: my-project
      source:
        repoURL: https://github.com/infra-team/cluster-deployments.git
        targetRevision: HEAD
        path: guestbook/{{.cluster}}
      destination:
        server: '{{.url}}'
        namespace: guestbook
```

### 未設定參數的備用方案

對於某些產生器，特定名稱的參數可能不會總是填入（例如，使用值產生器
或 git 檔案產生器）。在這些情況下，您可以使用 Go 範本來提供備用值。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - list:
      elements:
      - cluster: engineering-dev
        url: https://kubernetes.default.svc
      - cluster: engineering-prod
        url: https://kubernetes.default.svc
        nameSuffix: -my-name-suffix
  template:
    metadata:
      name: '{{.cluster}}{{dig "nameSuffix" "" .}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: applicationset/examples/list-generator/guestbook/{{.cluster}}
      destination:
        server: '{{.url}}'
        namespace: guestbook
```

此 ApplicationSet 將產生一個名為 `engineering-dev` 的應用程式和另一個名為
`engineering-prod-my-name-suffix` 的應用程式。

請注意，未設定的參數是錯誤的，因此您需要避免查閱不存在的屬性。相反，請使用
像 `dig` 這樣的範本函式來進行查閱並提供預設值。如果您希望未設定的參數預設為零，
您可以移除 `goTemplateOptions: ["missingkey=error"]` 或將其設定為 `goTemplateOptions: ["missingkey=invalid"]`
