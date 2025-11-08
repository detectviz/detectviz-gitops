# 合併產生器

合併產生器會將由基礎（第一個）產生器產生的參數與由後續產生器產生的相符參數集結合。一個**相符**的參數集對於設定的**合併鍵**具有相同的值。**不相符**的參數集會被捨棄。覆寫優先順序是從下到上：由產生器 3 產生的相符參數集的值將優先於由產生器 2 產生的對應參數集的值。

當參數集的子集需要覆寫時，使用合併產生器是適當的。

## 範例：基礎叢集產生器 + 覆寫叢集產生器 + 清單產生器

舉例來說，假設我們有兩個叢集：

- 一個 `staging` 叢集（位於 `https://1.2.3.4`）
- 一個 `production` 叢集（位於 `https://2.4.6.8`）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-git
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    # 合併「父」產生器
    - merge:
        mergeKeys:
          - server
        generators:
          - clusters:
              values:
                kafka: 'true'
                redis: 'false'
          # 對於具有特定標籤的叢集，啟用 Kafka。
          - clusters:
              selector:
                matchLabels:
                  use-kafka: 'false'
              values:
                kafka: 'false'
          # 對於特定叢集，啟用 Redis。
          - list:
              elements:
                - server: https://2.4.6.8
                  values.redis: 'true'
  template:
    metadata:
      name: '{{.name}}'
    spec:
      project: '{{index .metadata.labels "environment"}}'
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: app
        helm:
          parameters:
            - name: kafka
              value: '{{.values.kafka}}'
            - name: redis
              value: '{{.values.redis}}'
      destination:
        server: '{{.server}}'
        namespace: default
```

基礎叢集產生器會掃描[在 Argo CD 中定義的叢集集合](Generators-Cluster.md)，找到預備和生產叢集的密鑰，並產生兩組對應的參數：
```yaml
- name: staging
  server: https://1.2.3.4
  values.kafka: 'true'
  values.redis: 'false'

- name: production
  server: https://2.4.6.8
  values.kafka: 'true'
  values.redis: 'false'
```

覆寫叢集產生器會掃描[在 Argo CD 中定義的叢集集合](Generators-Cluster.md)，找到預備叢集的密鑰（具有必要的標籤），並產生以下參數：
```yaml
- name: staging
  server: https://1.2.3.4
  values.kafka: 'false'
```

當與基礎產生器的參數合併時，預備叢集的 `values.kafka` 值會設定為 `'false'`。
```yaml
- name: staging
  server: https://1.2.3.4
  values.kafka: 'false'
  values.redis: 'false'

- name: production
  server: https://2.4.6.8
  values.kafka: 'true'
  values.redis: 'false'
```

最後，清單叢集會產生一組參數：
```yaml
- server: https://2.4.6.8
  values.redis: 'true'
```

當與更新後的基礎參數合併時，生產叢集的 `values.redis` 值會設定為 `'true'`。這是合併產生器的最終輸出：
```yaml
- name: staging
  server: https://1.2.3.4
  values.kafka: 'false'
  values.redis: 'false'

- name: production
  server: https://2.4.6.8
  values.kafka: 'true'
  values.redis: 'true'
```

## 範例：在合併中使用值插值

有些產生器支援額外的值，並從產生的變數內插到選定的值。這可以用來教導合併產生器使用哪些產生的變數來組合不同的產生器。

以下範例會根據叢集標籤和分支名稱來組合發現的叢集和 git 儲存庫：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-git
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    # 合併「父」產生器：
    # 使用由兩個子產生器設定的選擇器來組合它們。
    - merge:
        mergeKeys:
          # 請注意，這在啟用 goTemplate 的情況下將無法運作，
          # 那裡不支援巢狀合併鍵。
          - values.selector
        generators:
          # 假設所有設定的叢集都有其位置的標籤：
          # 將選擇器設定為此位置。
          - clusters:
              values:
                selector: '{{index .metadata.labels "location"}}'
          # git 儲存庫可能有不同的目錄，對應於
          # 叢集位置，將這些用作選擇器。
          - git:
              repoURL: https://github.com/argoproj/argocd-example-apps/
              revision: HEAD
              directories:
              - path: '*'
              values:
                selector: '{{.path.path}}'
  template:
    metadata:
      name: '{{.name}}'
    spec:
      project: '{{index .metadata.labels "environment"}}'
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        # 每個產生器的叢集值欄位將會在此處被替換：
        targetRevision: HEAD
        path: '{{.path.path}}'
      destination:
        server: '{{.server}}'
        namespace: default
```

假設一個名為 `germany01` 的叢集具有標籤 `metadata.labels.location=Germany`，而一個 git 儲存庫包含一個名為 `Germany` 的目錄，這可以組合成如下的值：

```yaml
  # 來自叢集產生器
- name: germany01
  server: https://1.2.3.4
  # 來自 git 產生器
  path: Germany
  # 使用合併產生器組合選擇器
  values.selector: 'Germany'
  # 更多來自叢集和 git 產生器的值
  # […]
```


## 限制

1. 您應該在每個陣列項目中僅指定一個產生器。這是不合法的：

        - merge:
            generators:
            - list: # (...)
              git: # (...)

    - 雖然這**將**被 Kubernetes API 驗證接受，但控制器將在產生時報告錯誤。每個產生器都應在單獨的陣列元素中指定，如上面的範例所示。

1. 合併產生器不支援在子產生器上指定的 [`template` 覆寫](Template.md#generator-templates)。這個 `template` 將不會被處理：

        - merge:
            generators:
              - list:
                  elements:
                    - # (...)
                  template: { } # 未處理

1. 組合類型產生器（矩陣或合併）只能巢狀一次。例如，這將無法運作：

        - merge:
            generators:
              - merge:
                  generators:
                    - merge:  # 第三層無效。
                        generators:
                          - list:
                              elements:
                                - # (...)

1. 目前不支援在使用 `goTemplate: true` 時合併巢狀值，這將無法運作

        spec:
          goTemplate: true
          generators:
          - merge:
              mergeKeys:
                - values.merge
