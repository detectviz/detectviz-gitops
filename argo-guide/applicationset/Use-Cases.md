# ApplicationSet 控制器支援的使用案例

透過產生器的概念，ApplicationSet 控制器提供了一套強大的工具來自動化 Argo CD 應用程式的範本化和修改。產生器從各種來源產生範本參數資料，包括 Argo CD 叢集和 Git 儲存庫，支援並啟用新的使用案例。

雖然這些工具可以用於任何期望的目的，但以下是 ApplicationSet 控制器設計用來支援的一些特定使用案例。

## 使用案例：叢集附加元件

ApplicationSet 控制器的初始設計重點是讓基礎設施團隊的 Kubernetes 叢集管理員能夠自動建立大量、多樣化的 Argo CD 應用程式，跨越大量的叢集，並將這些應用程式作為一個單元進行管理。需要這樣做的一個例子是**叢集附加元件使用案例**。

在**叢集附加元件使用案例**中，管理員負責將叢集附加元件佈建到一個或多個 Kubernetes 叢集：叢集附加元件是運算子，例如 [Prometheus 運算子](https://github.com/prometheus-operator/prometheus-operator)，或控制器，例如 [argo-workflows 控制器](https://argoproj.github.io/argo-workflows/)（[Argo 生態系統](https://argoproj.github.io/)的一部分）。

通常，開發團隊的應用程式需要這些附加元件（例如，作為多租戶叢集的租戶，他們可能希望向 Prometheus 提供指標資料或透過 Argo Workflows 協調工作流程）。

由於安裝這些附加元件需要叢集層級的權限，而個別開發團隊沒有這些權限，因此安裝是組織的基礎設施/維運團隊的責任，而在大型組織中，此團隊可能負責數十、數百或數千個 Kubernetes 叢集（新叢集會定期新增/修改/移除）。

需要擴展到大量叢集，並自動回應新叢集的生命週期，勢必需要某種形式的自動化。進一步的要求是允許使用特定標準（例如，預備與生產）將附加元件鎖定到叢集的子集。

![叢集附加元件圖](../../assets/applicationset/Use-Cases/Cluster-Add-Ons.png)

在此範例中，基礎設施團隊維護一個 Git 儲存庫，其中包含 Argo Workflows 控制器和 Prometheus 運算子的應用程式資訊清單。

基礎設施團隊希望使用 Argo CD 將這兩個附加元件部署到大量叢集，並且同樣希望輕鬆管理新叢集的建立/刪除。

在此使用案例中，我們可以使用 ApplicationSet 控制器的清單、叢集或 Git 產生器來提供所需的行為：

- *清單產生器*：管理員維護兩個 `ApplicationSet` 資源，每個應用程式一個（Workflows 和 Prometheus），並在每個資源的清單產生器元素中包含他們希望鎖定的叢集清單。
    - 使用此產生器，新增/移除叢集需要手動更新 `ApplicationSet` 資源的清單元素。
- *叢集產生器*：管理員維護兩個 `ApplicationSet` 資源，每個應用程式一個（Workflows 和 Prometheus），並確保所有新叢集都在 Argo CD 中定義。
    - 由於叢集產生器會自動偵測並鎖定 Argo CD 中定義的叢集，因此[從 Argo CD 新增/移除叢集](../../declarative-setup/#clusters)將自動導致 ApplicationSet 控制器為每個應用程式建立 Argo CD 應用程式資源。
- *Git 產生器*：Git 產生器是所有產生器中最靈活/最強大的，因此有許多不同的方法可以解決此使用案例。以下是幾種方法：
    - 使用 Git 產生器 `files` 欄位：叢集清單以 JSON 檔案的形式保存在 Git 儲存庫中。透過 Git 提交對 JSON 檔案的更新會導致新增/移除新叢集。
    - 使用 Git 產生器 `directories` 欄位：對於每個目標叢集，Git 儲存庫中都存在一個同名的對應目錄。透過 Git 提交新增/修改目錄將觸發與目錄名稱相同的叢集的更新。

有關每個產生器的詳細資訊，請參閱[產生器部分](Generators.md)。

## 使用案例：單一儲存庫

在**單一儲存庫使用案例**中，Kubernetes 叢集管理員從單一 Git 儲存庫管理單一 Kubernetes 叢集的整個狀態。

合併到 Git 儲存庫中的資訊清單變更應自動部署到叢集。

![單一儲存庫圖](../../assets/applicationset/Use-Cases/Monorepos.png)

在此範例中，基礎設施團隊維護一個 Git 儲存庫，其中包含 Argo Workflows 控制器和 Prometheus 運算子的應用程式資訊清單。獨立的開發團隊也新增了他們希望部署到叢集的其他服務。

對 Git 儲存庫所做的變更——例如，更新已部署成品的版本——應自動導致 Argo CD 將該更新應用於對應的 Kubernetes 叢集。

Git 產生器可用於支援此使用案例：

- Git 產生器 `directories` 欄位可用於指定包含要部署的個別應用程式的特定子目錄（使用萬用字元）。
- Git 產生器 `files` 欄位可以參考包含 JSON 元資料的 Git 儲存庫檔案，該元資料描述要部署的個別應用程式。
- 如需更多詳細資訊，請參閱 Git 產生器文件。

## 使用案例：在多租戶叢集上自助服務 Argo CD 應用程式

**自助服務使用案例**旨在讓開發人員（作為多租戶 Kubernetes 叢集的最終使用者）能夠更靈活地：

- 使用 Argo CD 以自動化方式將多個應用程式部署到單一叢集
- 使用 Argo CD 以自動化方式部署到多個叢集
- 但是，在這兩種情況下，都賦予這些開發人員能夠這樣做的權力，而無需叢集管理員介入（代表他們建立必要的 Argo CD 應用程式/AppProject 資源）

此使用案例的一個潛在解決方案是讓開發團隊在 Git 儲存庫（包含他們希望部署的資訊清單）中以[應用程式的應用程式模式](../../cluster-bootstrapping/#app-of-apps-pattern)定義 Argo CD `Application` 資源，然後讓叢集管理員透過合併請求來審查/接受對此儲存庫的變更。

雖然這聽起來像是一個有效的解決方案，但一個主要的缺點是需要高度的信任/審查才能接受包含 Argo CD `Application` 規格變更的提交。這是因為 `Application` 規格中包含許多敏感欄位，包括 `project`、`cluster` 和 `namespace`。一次不經意的合併可能會讓應用程式存取它們不應存取的命名空間/叢集。

因此，在自助服務使用案例中，管理員希望只允許開發人員控制 `Application` 規格的某些欄位（例如 Git 來源儲存庫），而不允許其他欄位（例如目標命名空間或目標叢集應受到限制）。

幸運的是，ApplicationSet 控制器為此使用案例提供了另一種解決方案：叢集管理員可以安全地建立一個包含 Git 產生器的 `ApplicationSet` 資源，該產生器將應用程式資源的部署限制為具有 `template` 欄位的固定值，同時允許開發人員隨意自訂「安全」欄位。

`config.json` 檔案包含描述應用程式的資訊。

```json
{
  (...)
  "app": {
    "source": "https://github.com/argoproj/argo-cd",
    "revision": "HEAD",
    "path": "applicationset/examples/git-generator-files-discovery/apps/guestbook"
  }
  (...)
}
```

```yaml
kind: ApplicationSet
# (...)
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - git:
      repoURL: https://github.com/argoproj/argo-cd.git
      files:
      - path: "apps/**/config.json"
  template:
    spec:
      project: dev-team-one # 專案受限
      source:
        # 開發人員可以使用上述儲存庫 URL 中的 JSON 檔案自訂應用程式詳細資訊
        repoURL: {{.app.source}}
        targetRevision: {{.app.revision}}
        path: {{.app.path}}
      destination:
        name: production-cluster # 叢集受限
        namespace: dev-team-one # 命名空間受限
```
如需更多詳細資訊，請參閱 [Git 產生器](Generators-Git.md)。
