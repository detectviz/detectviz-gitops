# 清單產生器

清單產生器會根據任意的鍵/值對清單（只要值是字串值）來產生參數。在此範例中，我們的目標是一個名為 `engineering-dev` 的本地叢集：
```yaml
apiVersion: argroj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - list:
      elements:
      - cluster: engineering-dev
        url: https://kubernetes.default.svc
      # - cluster: engineering-prod
      #   url: https://kubernetes.default.svc
  template:
    metadata:
      name: '{{.cluster}}-guestbook'
    spec:
      project: "my-project"
      source:
        repoURL: https://github.com/argoproj/argo-cd.git
        targetRevision: HEAD
        path: applicationset/examples/list-generator/guestbook/{{.cluster}}
      destination:
        server: '{{.url}}'
        namespace: guestbook
```
（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/list-generator)找到。*）

在此範例中，清單產生器會將 `url` 和 `cluster` 欄位作為參數傳遞到範本中。如果我們想要新增第二個環境，我們可以取消註解第二個元素，ApplicationSet 控制器將會自動使用定義的應用程式來鎖定它。

在 ApplicationSet v0.1.0 版本中，只能指定 `url` 和 `cluster` 元素欄位（以及任意的 `values`）。自 ApplicationSet v0.2.0 起，支援任何鍵/值 `element` 對（這也與 v0.1.0 的形式完全向後相容）：
```yaml
spec:
  generators:
  - list:
      elements:
        # v0.1.0 形式 - 需要 cluster/url 鍵：
        - cluster: engineering-dev
          url: https://kubernetes.default.svc
          values:
            additional: value
        # v0.2.0+ 形式 - 不需要 cluster/URL 鍵
        # （但仍然支援）。
        - staging: "true"
          gitRepo: https://kubernetes.default.svc
# (...)
```

> [!NOTE]
> **叢集必須在 Argo CD 中預先定義**
>
> 這些叢集*必須*已在 Argo CD 中定義，才能為這些值產生應用程式。ApplicationSet 控制器不會在 Argo CD 中建立叢集（例如，它沒有這樣做的憑證）。

## 動態產生的元素
清單產生器還可以根據從先前的產生器（例如 git）取得的 yaml/json 動態產生其元素，方法是將兩者與矩陣產生器結合。在此範例中，我們使用矩陣產生器，其後跟著 git 和清單產生器，並將 git 中檔案的內容作為輸入傳遞給清單產生器的 `elementsYaml` 欄位：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: elements-yaml
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - matrix:
      generators:
      - git:
          repoURL: https://github.com/argoproj/argo-cd.git
          revision: HEAD
          files:
          - path: applicationset/examples/list-generator/list-elementsYaml-example.yaml
      - list:
          elementsYaml: "{{ .key.components | toJson }}"
  template:
    metadata:
      name: '{{.name}}'
    spec:
      project: default
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
      sources:
        - chart: '{{.chart}}'
          repoURL: '{{.repoUrl}}'
          targetRevision: '{{.version}}'
          helm:
            releaseName: '{{.releaseName}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.namespace}}'
```

其中 `list-elementsYaml-example.yaml` 的內容為：
```yaml
key:
  components:
    - name: component1
      chart: podinfo
      version: "6.3.2"
      releaseName: component1
      repoUrl: "https://stefanprodan.github.io/podinfo"
      namespace: component1
    - name: component2
      chart: podinfo
      version: "6.3.3"
      releaseName: component2
      repoUrl: "ghcr.io/stefanprodan/charts"
      namespace: component2
```
