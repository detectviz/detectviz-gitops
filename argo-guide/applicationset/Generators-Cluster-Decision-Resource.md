# 叢集決策資源產生器

叢集決策資源會產生 Argo CD 叢集的清單。這是透過使用[鴨子型別](https://pkg.go.dev/knative.dev/pkg/apis/duck)來完成的，它不需要知道所參考的 Kubernetes 資源的完整形狀。以下是基於叢集決策資源的 ApplicationSet 產生器的範例：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
 name: guestbook
 namespace: argocd
spec:
 goTemplate: true
 goTemplateOptions: ["missingkey=error"]
 generators:
 - clusterDecisionResource:
    # 包含鴨子型別資源 GVK 資訊的 ConfigMap
    configMapRef: my-configmap
    name: quak           # 選擇資源的「名稱」或「labelSelector」
    labelSelector:
      matchLabels:       # 可選
        duck: spotted
      matchExpressions:  # 可選
      - key: duck
        operator: In
        values:
        - "spotted"
        - "canvasback"
    # 可選：每 60 秒檢查一次變更（預設 3 分鐘）
    requeueAfterSeconds: 60
 template:
   metadata:
     name: '{{.name}}-guestbook'
   spec:
      project: "default"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{.clusterName}}' # 密鑰的「server」欄位
        namespace: guestbook
```
`ApplicationSet` `clusterDecisionResource` 產生器所參考的 `quak` 資源：
```yaml
apiVersion: mallard.io/v1beta1
kind: Duck
metadata:
  name: quak
spec: {}
status:
  # 鴨子型別會忽略資源的所有其他方面，除了
  # 「decisions」清單
  decisions:
  - clusterName: cluster-01
  - clusterName: cluster-02
```
`ApplicationSet` 資源會參考一個 `ConfigMap`，該 `ConfigMap` 會定義在此鴨子型別中使用的資源。每個 `ArgoCD` 執行個體只需要一個 ConfigMap 來識別一個資源。您可以透過為每種資源類型建立一個 `ConfigMap` 來支援多種資源類型。
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-configmap
data:
  # 目標資源的 apiVersion
  apiVersion: mallard.io/v1beta1
  # 目標資源的 kind
  kind: ducks
  # 保存 Argo CD 叢集清單的狀態鍵名稱
  statusListKey: decisions
  # 狀態清單中的鍵，其值為在 Argo CD 中找到的叢集名稱
  matchKey: clusterName
```

（*完整範例可以在[此處](https://github.com/argoproj/argo-cd/tree/master/applicationset/examples/clusterDecisionResource)找到。*）

此範例利用了 [open-cluster-management.io 社群](https://open-cluster-management.io/) 的叢集管理功能。透過為 `open-cluster-management.io` Placement 規則的 GVK 建立一個 `ConfigMap`，您的 ApplicationSet 可以用多種新穎的方式佈建到不同的叢集。一個範例是讓 ApplicationSet 在 3 個或更多叢集中只維護兩個 Argo CD 應用程式。然後，當發生維護或中斷時，ApplicationSet 將始終維護兩個應用程式，並根據 Placement 規則的指示將應用程式移至可用的叢集。

## 運作方式
ApplicationSet 需要在 Argo CD 命名空間中建立，將 `ConfigMap` 放在相同的命名空間中可讓 ClusterDecisionResource 產生器讀取它。`ConfigMap` 儲存 GVK 資訊以及狀態鍵定義。在 open-cluster-management 範例中，ApplicationSet 產生器將讀取 `placementrules` 種類，其 apiVersion 為 `apps.open-cluster-management.io/v1`。它會嘗試從鍵 `decisions` 中提取叢集的**清單**。然後，它會根據清單中每個元素中鍵 `clusterName` 的**值**來驗證在 Argo CD 中定義的實際叢集名稱。

ClusterDecisionResource 產生器會將鴨子型別資源狀態清單中的「name」、「server」和任何其他鍵/值作為參數傳遞到 ApplicationSet 範本中。在此範例中，decision 陣列包含一個額外的鍵 `clusterName`，現在可供 ApplicationSet 範本使用。

> [!NOTE]
> **`Status.Decisions` 中列出的叢集必須在 Argo CD 中預先定義**
>
> `Status.Decisions` 中列出的叢集名稱*必須*在 Argo CD 中定義，才能為這些值產生應用程式。ApplicationSet 控制器不會在 Argo CD 中建立叢集。
>
> 預設的叢集清單鍵是 `clusters`。
