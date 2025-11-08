# 應用程式的多個來源

預設情況下，Argo CD 應用程式是單一來源與叢集之間的連結。然而，有時您會想要將
來自多個位置的檔案合併成一個單一的應用程式。

Argo CD 能夠為單一應用程式指定多個來源。Argo CD 會編譯所有來源
並協調合併後的資源。

您可以使用 `sources` 欄位提供多個來源。當您指定 `sources` 欄位時，Argo CD 會忽略
`source` (單數) 欄位。

請參閱以下範例以指定多個來源：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-billing-app
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  sources:
    - repoURL: https://github.com/mycompany/billing-app.git
      path: manifests
      targetRevision: 8.5.1
    - repoURL: https://github.com/mycompany/common-settings.git
      path: configmaps-billing
      targetRevision: HEAD
```

上述範例指定了兩個需要合併以建立「帳務」應用程式的來源。Argo CD 將為每個來源分別產生資訊清單，並將
產生的資訊清單合併。

> [!WARNING]
> **請勿濫用多個來源**
>
> 請注意，此功能並**非**旨在作為將不同/不相關的應用程式分組的通用方法。如果您想為多個應用程式建立一個單一實體，請參考 [applicationsets](../user-guide/application-set.md) 和 [app-of-apps](../../operator-manual/cluster-bootstrapping/) 模式。如果您發現自己在 `sources` 陣列中使用了超過 2-3 個項目，那麼您幾乎可以肯定是在濫用此功能，您需要重新考慮您的應用程式分組策略。

如果多個來源產生相同的資源 (相同的 `group`、`kind`、`name` 和 `namespace`)，則最後一個
產生該資源的來源將優先。在這種情況下，Argo CD 將產生 `RepeatedResourceWarning`，但它會
同步資源。這提供了一種方便的方法，可以用來自 Git 儲存庫的資源覆寫來自 chart 的資源。

## 來自外部 Git 儲存庫的 Helm value 檔案

使用多個來源最常見的情境之一如下：

1. 您的組織希望使用外部/公開的 Helm chart
2. 您希望使用自己的本地值覆寫 Helm 值
3. 您不希望也在本地複製 Helm chart，因為這會導致重複，而且您需要手動監控其上游變更。

在這種情況下，您可以使用多個來源功能將外部 chart 與您自己的本地值合併。

Helm 來源可以參照來自 git 來源的值檔案。這讓您可以使用第三方 Helm chart 搭配自訂的、
git 託管的值。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
  - repoURL: 'https://prometheus-community.github.io/helm-charts'
    chart: prometheus
    targetRevision: 15.7.1
    helm:
      valueFiles:
      - $values/charts/prometheus/values.yaml
  - repoURL: 'https://git.example.com/org/value-files.git'
    targetRevision: dev
    ref: values
```

在上述範例中，`prometheus` chart 將使用來自 `git.example.com/org/value-files.git` 的值檔案。
為了讓 Argo 能夠參照包含值檔案的外部 Git 儲存庫，您必須在
儲存庫上設定 `ref` 參數。在上述範例中，參數 `ref: values` 對應到變數 `$values`，該變數會解析
為 `value-files` 儲存庫的根目錄。
請注意，`$values` 變數只能在值檔案路徑的開頭使用，而且其路徑永遠相對於所參照來源的根目錄。

如果在 `$values` 來源中設定了 `path` 欄位，Argo CD 會嘗試從該 URL 的 git 儲存庫
產生資源。如果未設定 `path` 欄位，Argo CD 將僅將該儲存庫用作值檔案的來源。

> [!NOTE]
> 設定 `ref` 欄位的來源不能包含 `chart` 欄位。目前，Argo CD 不支援使用另一個 Helm chart 作為值檔案的來源。

> [!NOTE]
> 即使 `ref` 欄位已與 `path` 欄位一起設定，`$value` 仍然代表具有 `ref` 欄位的來源的根目錄。因此，`valueFiles` 必須指定為來源根目錄的相對路徑。
