# 矩陣產生器

矩陣產生器會結合兩個子產生器產生的參數，並逐一查看每個產生器所產生參數的每個組合。

透過結合兩個產生器的參數來產生所有可能的組合，您可以獲得兩個產生器的內在屬性。例如，許多可能的使用案例中的一小部分包括：

- *SCM 提供者產生器 + 叢集產生器*：掃描 GitHub 組織的儲存庫以尋找應用程式資源，並將這些資源鎖定到所有可用的叢集。
- *Git 檔案產生器 + 清單產生器*：透過組態檔提供要部署的應用程式清單，並提供可選的組態選項，然後將它們部署到固定的叢集清單中。
- *Git 目錄產生器 + 叢集決策資源產生器*：尋找包含在 Git 儲存庫資料夾中的應用程式資源，並將它們部署到透過外部自訂資源提供的叢集清單中。
- 諸如此類…

可以使用任何一組產生器，並將這些產生器的組合值像往常一樣插入到 `template` 參數中。

**注意**：如果兩個子產生器都是 Git 產生器，則其中一個或兩個都必須使用 `pathParamPrefix` 選項，以避免在合併子產生器的項目時發生衝突。

## 範例：Git 目錄產生器 + 叢集產生器

舉例來說，假設我們有兩個叢集：

- 一個 `staging` 叢集（位於 `https://1.2.3.4`）
- 一個 `production` 叢集（位於 `https://2.4.6.8`）

而我們的應用程式 YAML 定義在一個 Git 儲存庫中：

- [Argo Workflows 控制器](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-directory/cluster-addons/argo-workflows)
- [Prometheus operator](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/git-generator-directory/cluster-addons/prometheus-operator)

我們的目標是將這兩個應用程式部署到這兩個叢集上，而且，更一般地說，未來也要自動部署 Git 儲存庫中的新應用程式，以及 Argo CD 中定義的新叢集。

為此，我們將使用矩陣產生器，並以 Git 和叢集作為子產生器：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-git
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    # 矩陣「父」產生器
    - matrix:
        generators:
          # git 產生器，「子」#1
          - git:
              repoURL: https://github.com/argoproj/argo-cd.git
              revision: HEAD
              directories:
                - path: applicationset/examples/matrix/cluster-addons/*
          # 叢集產生器，「子」#2
          - clusters:
              selector:
                matchLabels:
                  argocd.argoproj.io/secret-type: cluster
  template:
    metadata:
      name: '{{.path.basename}}-{{.name}}'
    spec:
      project: '{{index .metadata.labels "environment"}}'
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: '{{.server}}'
        namespace: '{{.path.basename}}'
```

首先，Git 目錄產生器將掃描 Git 儲存庫，尋找指定路徑下的目錄。它會找到 argo-workflows 和 prometheus-operator 應用程式，並產生兩組對應的參數：
```yaml
- path: /examples/git-generator-directory/cluster-addons/argo-workflows
  path.basename: argo-workflows

- path: /examples/git-generator-directory/cluster-addons/prometheus-operator
  path.basename: prometheus-operator
```

接下來，叢集產生器會掃描[在 Argo CD 中定義的叢集集合](Generators-Cluster.md)，找到預備和生產叢集的密鑰，並產生兩組對應的參數：
```yaml
- name: staging
  server: https://1.2.3.4

- name: production
  server: https://2.4.6.8
```

最後，矩陣產生器將結合兩組輸出，並產生：
```yaml
- name: staging
  server: https://1.2.3.4
  path: /examples/git-generator-directory/cluster-addons/argo-workflows
  path.basename: argo-workflows

- name: staging
  server: https://1.2.3.4
  path: /examples/git-generator-directory/cluster-addons/prometheus-operator
  path.basename: prometheus-operator

- name: production
  server: https://2.4.6.8
  path: /examples/git-generator-directory/cluster-addons/argo-workflows
  path.basename: argo-workflows

- name: production
  server: https://2.4.6.8
  path: /examples/git-generator-directory/cluster-addons/prometheus-operator
  path.basename: prometheus-operator
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/matrix)找到。*）

## 在另一個子產生器中使用一個子產生器的參數

矩陣產生器允許在另一個子產生器中使用由一個子產生器產生的參數。
以下範例使用 git-files 產生器與叢集產生器結合。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-git
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    # 矩陣「父」產生器
    - matrix:
        generators:
          # git 產生器，「子」#1
          - git:
              repoURL: https://github.com/argoproj/applicationset.git
              revision: HEAD
              files:
                - path: "examples/git-generator-files-discovery/cluster-config/**/config.json"
          # 叢集產生器，「子」#2
          - clusters:
              selector:
                matchLabels:
                  argocd.argoproj.io/secret-type: cluster
                  kubernetes.io/environment: '{{.path.basename}}'
  template:
    metadata:
      name: '{{.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/applicationset.git
        targetRevision: HEAD
        path: "examples/git-generator-files-discovery/apps/guestbook"
      destination:
        server: '{{.server}}'
        namespace: guestbook
```
以下是 git-files 產生器使用的 git 儲存庫的對應資料夾結構：

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
在上述範例中，由 git-files 產生器產生的 `{{.path.basename}}` 參數將解析為 `dev` 和 `prod`。
在第二個子產生器中，標籤選擇器與標籤 `kubernetes.io/environment: {{.path.basename}}` 將會使用第一個子產生器的參數所產生的值來解析（`kubernetes.io/environment: prod` 和 `kubernetes.io/environment: dev`）。

因此，在上述範例中，具有標籤 `kubernetes.io/environment: prod` 的叢集將只會套用生產環境特定的組態（即 `prod/config.json`），而具有標籤
`kubernetes.io/environment: dev` 的叢集將只會套用開發環境特定的組態（即 `dev/config.json`）。

## 在另一個子產生器中覆寫一個子產生器的參數

矩陣產生器允許多個子產生器中定義同名參數。例如，這對於在一個產生器中定義所有階段的預設值，並在另一個產生器中使用特定於階段的值來覆寫它們很有用。以下範例使用一個矩陣產生器和兩個 git 產生器來產生一個基於 Helm 的應用程式：第一個提供特定於階段的值（每個階段一個目錄），第二個提供所有階段的全域值。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: parameter-override-example
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://github.com/example/values.git
              revision: HEAD
              files:
                - path: "**/stage.values.yaml"
          - git:
               repoURL: https://github.com/example/values.git
               revision: HEAD
               files:
                  - path: "global.values.yaml"
  goTemplate: true
  template:
    metadata:
      name: example
    spec:
      project: default
      source:
        repoURL: https://github.com/example/example-app.git
        targetRevision: HEAD
        path: .
        helm:
          values: |
            {{ `{{ . | mustToPrettyJson }}` }}
      destination:
        server: in-cluster
        namespace: default
```

給定範例/值儲存庫的以下結構/內容：

```
├── test
│   └── stage.values.yaml
│         stageName: test
│         cpuRequest: 100m
│         debugEnabled: true
├── staging
│   └── stage.values.yaml
│         stageName: staging
├── production
│   └── stage.values.yaml
│         stageName: production
│         memoryLimit: 512Mi
│         debugEnabled: false
└── global.values.yaml
      cpuRequest: 200m
      memoryLimit: 256Mi
      debugEnabled: true
```

上述矩陣產生器將產生以下結果：

```yaml
- stageName: test
  cpuRequest: 100m
  memoryLimit: 256Mi
  debugEnabled: true

- stageName: staging
  cpuRequest: 200m
  memoryLimit: 256Mi
  debugEnabled: true

- stageName: production
  cpuRequest: 200m
  memoryLimit: 512Mi
  debugEnabled: false
```

## 範例：使用 `pathParamPrefix` 的兩個 Git 產生器

如果子產生器產生的結果包含具有不同值的相同鍵，則矩陣產生器將會失敗。
這對矩陣產生器來說是一個問題，其中兩個子產生器都是 Git 產生器，因為它們會在其輸出中自動填入與 `path` 相關的參數。
為了解決此問題，請在一個或兩個子產生器上指定 `pathParamPrefix`，以避免輸出中出現衝突的參數鍵。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: two-gits-with-path-param-prefix
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          # git 檔案產生器，參考包含每個
          # 要部署的應用程式詳細資訊的檔案（例如，`appName`）。
          - git:
              repoURL: https://github.com/some-org/some-repo.git
              revision: HEAD
              files:
                - path: "apps/*.json"
              pathParamPrefix: app
          # git 檔案產生器，參考包含每個
          # 應用程式應部署到的位置詳細資訊的檔案（例如，`region` 和
          # `clusterName`）。
          - git:
              repoURL: https://github.com/some-org/some-repo.git
              revision: HEAD
              files:
                - path: "targets/{{.appName}}/*.json"
              pathParamPrefix: target
  template: {} # ...
```

然後，給定以下檔案結構/內容：

```
├── apps
│   ├── app-one.json
│   │   { "appName": "app-one" }
│   └── app-two.json
│       { "appName": "app-two" }
└── targets
    ├── app-one
    │   ├── east-cluster-one.json
    │   │   { "region": "east", "clusterName": "cluster-one" }
    │   └── east-cluster-two.json
    │       { "region": "east", "clusterName": "cluster-two" }
    └── app-two
        ├── east-cluster-one.json
        │   { "region": "east", "clusterName": "cluster-one" }
        └── west-cluster-three.json
            { "region": "west", "clusterName": "cluster-three" }
```

…上述矩陣產生器將產生以下結果：

```yaml
- appName: app-one
  app.path: /apps
  app.path.filename: app-one.json
  # 加上來自第一個子產生器的其他與路徑相關的參數，全部
  # 以「app」為前綴。
  region: east
  clusterName: cluster-one
  target.path: /targets/app-one
  target.path.filename: east-cluster-one.json
  # 加上來自第二個子產生器的其他與路徑相關的參數，全部
  # 以「target」為前綴。

- appName: app-one
  app.path: /apps
  app.path.filename: app-one.json
  region: east
  clusterName: cluster-two
  target.path: /targets/app-one
  target.path.filename: east-cluster-two.json

- appName: app-two
  app.path: /apps
  app.path.filename: app-two.json
  region: east
  clusterName: cluster-one
  target.path: /targets/app-two
  target.path.filename: east-cluster-one.json

- appName: app-two
  app.path: /apps
  app.path.filename: app-two.json
  region: west
  clusterName: cluster-three
  target.path: /targets/app-two
  target.path.filename: west-cluster-three.json
```

## 限制

1. 矩陣產生器目前僅支援結合兩個子產生器的輸出（例如，不支援為 3 個或更多個產生組合）。

1. 您應該在每個陣列項目中僅指定一個產生器，例如，這是不合法的：

        - matrix:
            generators:
            - list: # (...)
              git: # (...)

    - 雖然這**將**被 Kubernetes API 驗證接受，但控制器將在產生時報告錯誤。每個產生器都應在單獨的陣列元素中指定，如上面的範例所示。

1. 矩陣產生器目前不支援在子產生器上指定的 [`template` 覆寫](Template.md#generator-templates)，例如，這個 `template` 將不會被處理：

        - matrix:
            generators:
              - list:
                  elements:
                    - # (...)
                  template: { } # 未處理

1. 組合類型產生器（矩陣或合併）只能巢狀一次。例如，這將無法運作：

        - matrix:
            generators:
              - matrix:
                  generators:
                    - matrix:  # 第三層無效。
                        generators:
                          - list:
                              elements:
                                - # (...)

1. 在另一個子產生器中使用一個子產生器的參數時，**使用**參數的子產生器**必須**在**產生**參數的子產生器之後。
例如，下面的範例將是無效的（叢集產生器必須在 git-files 產生器之後）：

        - matrix:
            generators:
              # 叢集產生器，「子」#1
              - clusters:
                  selector:
                    matchLabels:
                      argocd.argoproj.io/secret-type: cluster
                      kubernetes.io/environment: '{{.path.basename}}' # {{.path.basename}} 由 git-files 產生器產生
              # git 產生器，「子」#2
              - git:
                  repoURL: https://github.com/argoproj/applicationset.git
                  revision: HEAD
                  files:
                    - path: "examples/git-generator-files-discovery/cluster-config/**/config.json"

1. 您不能讓兩個子產生器都從彼此那裡取用參數。在下面的範例中，叢集產生器正在取用由 git-files 產生器產生的 `{{.path.basename}}` 參數，而 git-files 產生器正在取用由叢集產生器產生的 `{{.name}}` 參數。這將導致循環相依性，這是無效的。

        - matrix:
            generators:
              # 叢集產生器，「子」#1
              - clusters:
                  selector:
                    matchLabels:
                      argocd.argoproj.io/secret-type: cluster
                      kubernetes.io/environment: '{{.path.basename}}' # {{.path.basename}} 由 git-files 產生器產生
              # git 產生器，「子」#2
              - git:
                  repoURL: https://github.com/argoproj/applicationset.git
                  revision: HEAD
                  files:
                    - path: "examples/git-generator-files-discovery/cluster-config/engineering/{{.name}}**/config.json" # {{.name}} 由叢集產生器產生
