# ApplicationSet 控制器如何與 Argo CD 互動

當您建立、更新或刪除 `ApplicationSet` 資源時，ApplicationSet 控制器會透過建立、更新或刪除一個或多個對應的 Argo CD `Application` 資源來回應。

事實上，ApplicationSet 控制器的**唯一**職責是在 Argo CD 命名空間內建立、更新和刪除 `Application` 資源。控制器的唯一工作是確保 `Application` 資源與定義的宣告式 `ApplicationSet` 資源保持一致，僅此而已。

因此，ApplicationSet 控制器：

- 不會建立/修改/刪除 Kubernetes 資源（`Application` CR 除外）
- 不會連接到 Argo CD 部署所在的叢集以外的叢集
- 不會與 Argo CD 部署所在的命名空間以外的命名空間互動

> [!IMPORTANT]
> **使用 Argo CD 命名空間**
>
> 所有 ApplicationSet 資源和 ApplicationSet 控制器都必須安裝在與 Argo CD 相同的命名空間中。
> 不同命名空間中的 ApplicationSet 資源將被忽略。

Argo CD 本身負責實際部署產生的子 `Application` 資源，例如 Deployments、Services 和 ConfigMaps。

因此，ApplicationSet 控制器可以被視為一個 `Application` 的「工廠」，它以 `ApplicationSet` 資源為輸入，並輸出一或多個與該集合參數對應的 Argo CD `Application` 資源。

![ApplicationSet 控制器與 Argo CD 的互動圖](../../assets/applicationset/Argo-CD-Integration/ApplicationSet-Argo-Relationship-v2.png)

在此圖中，定義了一個 `ApplicationSet` 資源，ApplicationSet 控制器的職責是建立對應的 `Application` 資源。然後，產生的 `Application` 資源由 Argo CD 管理：也就是說，Argo CD 負責實際部署子資源。

Argo CD 根據 Application `spec` 欄位中定義的 Git 儲存庫內容產生應用程式的 Kubernetes 資源，例如部署 Deployments、Service 和其他資源。

ApplicationSets 的建立、更新或刪除將直接影響 Argo CD 命名空間中存在的應用程式。同樣地，叢集事件（使用叢集產生器時，新增/刪除 Argo CD 叢集密鑰）或 Git 中的變更（使用 Git 產生器時），將被用作 ApplicationSet 控制器建構 `Application` 資源的輸入。

Argo CD 和 ApplicationSet 控制器共同確保存在一組一致的應用程式資源，並將其部署到目標叢集中。
