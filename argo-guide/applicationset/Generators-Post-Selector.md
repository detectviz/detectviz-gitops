# 所有產生器的後置選擇器

產生器上的 `selector` 欄位可讓 `ApplicationSet` 使用 [Kubernetes 通用 labelSelector 格式](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors) 和產生的值來對結果進行後置篩選。

`matchLabels` 是一個 `{key,value}` 對的對應。此 `list` 產生器會產生一組兩個 `Applications`，然後使用 `matchLabels` 將其篩選為僅包含鍵 `env` 值為 `staging` 的清單元素：
```
spec:
  generators:
  - list:
      elements:
        - cluster: engineering-dev
          url: https://kubernetes.default.svc
          env: staging
        - cluster: engineering-prod
          url: https://kubernetes.default.svc
          env: prod
    selector:
      matchLabels:
        env: staging
```

`list` 產生器 + `matchLabels` 選擇器會產生一組參數：
```yaml
- cluster: engineering-dev
  url: https://kubernetes.default.svc
  env: staging
```

也可以使用 `matchExpressions` 來進行更強大的選取。

`matchLabels` 對應中的單一 `{key,value}` 等同於 `matchExpressions` 的一個元素，其 `key` 欄位是「key」，`operator` 是「In」，而 `values` 陣列僅包含「value」。因此，使用 `matchExpressions` 的相同範例如下所示：
```yaml
spec:
  generators:
  - list:
      elements:
        - cluster: engineering-dev
          url: https://kubernetes.default.svc
          env: staging
        - cluster: engineering-prod
          url: https://kubernetes.default.svc
          env: prod
    selector:
      matchExpressions:
        - key: env
          operator: In
          values:
            - staging
```

有效的 `operators` 包括 `In`、`NotIn`、`Exists` 和 `DoesNotExist`。在 `In` 和 `NotIn` 的情況下，`values` 集合必須為非空。

## 完整範例
在範例中，清單產生器會產生一組兩個應用程式，然後按鍵值篩選以僅選擇 `env` 值為 `staging` 的應用程式：
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
          env: staging
        - cluster: engineering-prod
          url: https://kubernetes.default.svc
          env: prod
    selector:
      matchLabels:
        env: staging
  template:
    metadata:
      name: '{{.cluster}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj-labs/applicationset.git
        targetRevision: HEAD
        path: examples/list-generator/guestbook/{{.cluster}}
      destination:
        server: '{{.url}}'
        namespace: guestbook
```
