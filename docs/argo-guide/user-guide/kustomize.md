# Kustomize

## 宣告式

您可以用宣告式的 GitOps 方式定義 Kustomize 應用程式資訊清單。以下是一個範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kustomize-example
spec:
  project: default
  source:
    path: examples/helloWorld
    repoURL: 'https://github.com/kubernetes-sigs/kustomize'
    targetRevision: HEAD
  destination:
    namespace: default
    server: 'https://kubernetes.default.svc'
```

如果 `kustomization.yaml` 檔案存在於 `repoURL` 和 `path` 所指向的位置，Argo CD 將會使用 Kustomize 來呈現資訊清單。

以下是 Kustomize 可用的組態選項：

* `namePrefix` 是附加到 Kustomize 應用程式資源的前綴
* `nameSuffix` 是附加到 Kustomize 應用程式資源的後綴
* `images` 是 Kustomize 映像檔覆寫的清單
* `replicas` 是 Kustomize 副本覆寫的清單
* `commonLabels` 是額外標籤的字串對應
* `labelWithoutSelector` 是一個布林值，定義是否應將通用標籤應用於資源選取器。除非 `labelIncludeTemplates` 設定為 true，否則它也會從範本中排除通用標籤。
* `labelIncludeTemplates` 是一個布林值，定義是否應將通用標籤應用於資源範本。
* `forceCommonLabels` 是一個布林值，定義是否允許覆寫現有標籤
* `commonAnnotations` 是額外註釋的字串對應
* `namespace` 是 Kubernetes 資源命名空間
* `forceCommonAnnotations` 是一個布林值，定義是否允許覆寫現有註釋
* `commonAnnotationsEnvsubst` 是一個布林值，可在註釋值中啟用環境變數替換
* `patches` 是支援內嵌更新的 Kustomize 修補程式清單
* `components` 是 Kustomize 元件的清單
* `ignoreMissingComponents` 可防止 kustomize 在元件在本機不存在時因未將其附加到 kustomization 檔案而失敗

若要將 Kustomize 與覆蓋搭配使用，請將您的路徑指向覆蓋。

> [!TIP]
> 如果您正在產生資源，您應該閱讀如何使用 [`IgnoreExtraneous` 比較選項](compare-options.md)來忽略那些產生的資源。

## 修補程式
修補程式是一種在 Argo CD 應用程式中使用內嵌組態來自訂資源的方法。`patches` 遵循與對應的 Kustomization 相同的邏輯。任何針對現有 Kustomization 檔案的修補程式都將被合併。

這個 Kustomize 範例從 `argoproj/argocd-example-apps` 儲存庫的 `/kustomize-guestbook` 資料夾中取得資訊清單，並修補 `Deployment` 以在容器上使用埠 `443`。
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: kustomize-inline-example
namespace: test1
resources:
  - https://github.com/argoproj/argocd-example-apps//kustomize-guestbook/
patches:
  - target:
      kind: Deployment
      name: guestbook-ui
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/ports/0/containerPort
        value: 443
```

此 `Application` 使用內嵌的 `kustomize.patches` 組態來執行相同的操作。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kustomize-inline-guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: test1
    server: https://kubernetes.default.svc
  project: default
  source:
    path: kustomize-guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: master
    kustomize:
      patches:
        - target:
            kind: Deployment
            name: guestbook-ui
          patch: |-
            - op: replace
              path: /spec/template/spec/containers/0/ports/0/containerPort
              value: 443
```

內嵌的 kustomize 修補程式也適用於 `ApplicationSets`。與其為每個叢集維護一個修補程式或覆蓋，現在可以在 `Application` 範本中完成修補，並利用產生器的屬性。例如，使用 [`external-dns`](https://github.com/kubernetes-sigs/external-dns/) 將 [`txt-owner-id`](https://github.com/kubernetes-sigs/external-dns/blob/e1adc9079b12774cccac051966b2c6a3f18f7872/docs/registry/registry.md?plain=1#L6) 設定為叢集名稱。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: external-dns
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - clusters: {}
  template:
    metadata:
      name: 'external-dns'
    spec:
      project: default
      source:
        repoURL: https://github.com/kubernetes-sigs/external-dns/
        targetRevision: v0.14.0
        path: kustomize
        kustomize:
          patches:
          - target:
              kind: Deployment
              name: external-dns
            patch: |-
              - op: add
                path: /spec/template/spec/containers/0/args/3
                value: --txt-owner-id={{.name}}   # 使用產生器的屬性進行修補
      destination:
        name: 'in-cluster'
        namespace: default
```

## 元件
Kustomize [元件](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/components.md) 將資源和修補程式封裝在一起。它們為 Kubernetes 應用程式中的組態模組化和重複使用提供了強大的方法。
如果 Kustomize 傳遞了不存在的元件目錄，它將會出錯。可以使用 `ignoreMissingComponents` 忽略遺失的元件目錄（也就是說，不傳遞給 Kustomize）。這對於實作[預設/覆寫模式]特別有幫助。

在 Argo CD 之外，要利用元件，您必須將以下內容新增至應用程式參照的 `kustomization.yaml`。例如：
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
...
components:
- ../component
```

隨著 `v2.10.0` 中新增了對元件的支援，您現在可以直接在應用程式中參照元件：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: application-kustomize-components
spec:
  ...
  source:
    path: examples/application-kustomize-components/base
    repoURL: https://github.com/my-user/my-repo
    targetRevision: main
    
    # 這個！
    kustomize:
      components:
        - ../component  # 相對於 kustomization.yaml (`source.path`)。
      ignoreMissingComponents: true
```

## 私有遠端基礎

如果您的遠端基礎是 (a) HTTPS 且需要使用者名稱/密碼，或 (b) SSH 且需要 SSH 私鑰，那麼它們將會繼承應用程式儲存庫的這些資訊。

如果遠端基礎使用相同的憑證/私鑰，這將會運作。如果它們使用不同的，則無法運作。出於安全原因，您的應用程式只會知道自己的儲存庫（而不是其他團隊或使用者的儲存庫），因此您將無法存取其他私有儲存庫，即使 Argo CD 知道它們。

閱讀更多關於[私有儲存庫](private-repositories.md)的資訊。

## `kustomize build` 選項/參數

若要為預設 Kustomize 版本的 `kustomize build` 提供建置選項，請使用 `argocd-cm` ConfigMap 的 `kustomize.buildOptions` 欄位。使用 `kustomize.buildOptions.<version>` 來註冊特定版本的建置選項。

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
    kustomize.buildOptions: --load-restrictor LoadRestrictionsNone
    kustomize.buildOptions.v4.4.0: --output /tmp
```

修改 `kustomize.buildOptions` 後，您可能需要重新啟動 ArgoCD 才能使變更生效。

## 自訂 Kustomize 版本

Argo CD 支援同時使用多個 Kustomize 版本，並為每個應用程式指定所需的版本。
若要新增其他版本，請確保所需的版本已[綑綁](../operator-manual/custom_tools.md)，然後
使用 `argocd-cm` ConfigMap 的 `kustomize.path.<version>` 欄位來註冊已綑綁的其他版本。

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
    kustomize.path.v3.5.1: /custom-tools/kustomize_3_5_1
    kustomize.path.v3.5.4: /custom-tools/kustomize_3_5_4
```

設定新版本後，您可以在應用程式規格中如下參照它：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
spec:
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: kustomize-guestbook

    kustomize:
      version: v3.5.4
```

此外，可以使用應用程式詳細資料頁面的「參數」索引標籤或使用以下 CLI 指令來設定應用程式 kustomize 版本：

```bash
argocd app set <appName> --kustomize-version v3.5.4
```


## 建置環境

Kustomize 應用程式可以存取[標準建置環境](build-environment.md)，可以與[組態管理外掛程式](../operator-manual/config-management-plugins.md)結合使用來變更呈現的資訊清單。

您可以在 Argo CD 應用程式資訊清單中使用這些建置環境變數。您可以透過在應用程式資訊清單中將 `.spec.source.kustomize.commonAnnotationsEnvsubst` 設定為 `true` 來啟用此功能。

例如，以下應用程式資訊清單會將 `app-source` 註釋設定為應用程式的名稱：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-app
  namespace: argocd
spec:
  project: default
  destination:
    namespace: demo
    server: https://kubernetes.default.svc
  source:
    path: kustomize-guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    kustomize:
      commonAnnotationsEnvsubst: true
      commonAnnotations:
        app-source: ${ARGOCD_APP_NAME}
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

## Kustomizing Helm charts

可以[使用 Kustomize 呈現 Helm chart](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/chart.md)。
這樣做需要在 `kustomize build` 指令中傳遞 `--enable-helm` 旗標。
此旗標不屬於 Argo CD 中的 Kustomize 選項。
如果您想在 Argo CD 應用程式中透過 Kustomize 呈現 Helm chart，您有兩種選擇：
您可以建立一個[自訂外掛程式](https://argo-cd.readthedocs.io/en/stable/user-guide/config-management-plugins/)，或修改 `argocd-cm` ConfigMap 以在所有 Kustomize 應用程式中全域包含 `--enable-helm` 旗標：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  kustomize.buildOptions: --enable-helm
```

## 設定資訊清單的命名空間

`spec.destination.namespace` 欄位只會在 Kustomize 產生的資訊清單中缺少命名空間時新增命名空間。它也使用 `kubectl` 來設定命名空間，這有時會在某些資源中遺漏命名空間欄位（例如，自訂資源）。在這些情況下，您可能會收到類似以下的錯誤訊息：`ClusterRoleBinding.rbac.authorization.k8s.io "example" is invalid: subjects[0].namespace: Required value.`

直接使用 Kustomize 來設定遺失的命名空間可以解決此問題。設定 `spec.source.kustomize.namespace` 會指示 Kustomize 將命名空間欄位設定為給定的值。

如果同時設定了 `spec.destination.namespace` 和 `spec.source.kustomize.namespace`，Argo CD 會以後者為準，也就是 Kustomize 設定的命名空間值。
