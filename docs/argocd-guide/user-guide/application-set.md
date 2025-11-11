### 使用 ApplicationSet 控制器自動化產生 Argo CD 應用程式

[ApplicationSet 控制器](../operator-manual/applicationset/index.md) 新增了應用程式自動化功能，並尋求改善 Argo CD 內部對多叢集和叢集多租戶的支援。Argo CD 應用程式可以從多個不同的來源進行範本化，包括從 Git 或 Argo CD 自行定義的叢集清單。

ApplicationSet 控制器提供的工具集也可用於讓開發人員（在沒有存取 Argo CD 命名空間權限的情況下）獨立地建立應用程式，而無需叢集管理員的介入。

> [!WARNING]
> 在允許開發人員透過 ApplicationSets 建立應用程式之前，請注意[安全隱憂](../operator-manual/applicationset/Security.md)。

ApplicationSet 控制器會根據 `ApplicationSet` 自訂資源 (CR) 的內容自動產生 Argo CD 應用程式。

以下是一個 `ApplicationSet` 資源的範例，可用於將 Argo CD 應用程式部署到多個叢集：
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

List 產生器將 `url` 和 `cluster` 欄位作為 `{{param}}` 樣式的參數傳遞到範本中，然後將其呈現為三個對應的 Argo CD 應用程式（每個定義的叢集一個）。要部署到新叢集（或移除現有叢集），只需更改 `ApplicationSet` 資源，對應的 Argo CD 應用程式就會自動建立。

同樣地，對 ApplicationSet `template` 欄位所做的變更將自動應用於每個產生的應用程式。因此，管理一組多個 Argo CD 應用程式就像管理單一 `ApplicationSet` 資源一樣簡單。

除了 List 產生器之外，ApplicationSet 中還存在其他更強大的產生器，包括叢集產生器（它會自動使用 Argo CD 定義的叢集來範本化應用程式）和 Git 產生器（它會使用 Git 儲存庫的檔案/目錄來範本化應用程式）。

要了解更多關於 ApplicationSet 控制器的資訊，請參閱 [ApplicationSet 文件](../operator-manual/applicationset/index.md)。
