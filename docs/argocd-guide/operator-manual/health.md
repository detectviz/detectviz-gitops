# 資源健康狀態

## 總覽
Argo CD 為多種標準 Kubernetes 類型提供內建的健康狀態評估，然後將其整體呈現為應用程式的健康狀態。針對特定類型的 Kubernetes 資源，會進行以下檢查：

### Deployment, ReplicaSet, StatefulSet, DaemonSet
* 觀察到的世代 (Observed generation) 等於期望的世代 (desired generation)。
* **已更新** 的副本數等於期望的副本數。

### Service
* 如果服務類型為 `LoadBalancer`，則 `status.loadBalancer.ingress` 列表不為空，
且至少有一個 `hostname` 或 `IP` 的值。

### Ingress
* `status.loadBalancer.ingress` 列表不為空，且至少有一個 `hostname` 或 `IP` 的值。

### Job
* 如果 job 的 `.spec.suspended` 設定為 'true'，則該 job 和應用程式的健康狀態將被標記為 suspended。
### PersistentVolumeClaim
* `status.phase` 為 `Bound`

### Argocd App

`argoproj.io/Application` CRD 的健康狀態評估已在 argocd 1.8 中移除（更多資訊請參閱 [#3781](https://github.com/argoproj/argo-cd/issues/3781)）。
如果您使用 app-of-apps 模式並使用同步波 (sync waves) 來協調同步，您可能需要恢復它。在 `argocd-cm` ConfigMap 中新增以下資源自訂：

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
```

## 自訂健康狀態檢查

Argo CD 支援以 [Lua](https://www.lua.org/) 撰寫的自訂健康狀態檢查。如果您遇到以下情況，這會很有用：

* 您的 `Ingress` 或 `StatefulSet` 資源因資源控制器中的錯誤而卡在 `Progressing` 狀態。
* 您有一個自訂資源，Argo CD 沒有內建的健康狀態檢查。

有兩種方法可以設定自訂健康狀態檢查。接下來的兩節將描述這兩種方法。

### 方法 1. 在 `argocd-cm` ConfigMap 中定義自訂健康狀態檢查

自訂健康狀態檢查可以在 `argocd-cm` 的
```yaml
  resource.customizations.health.<group>_<kind>: |
```
欄位中定義。如果您使用 argocd-operator，這會被 [argocd-operator 的 resourceCustomizations](https://argocd-operator.readthedocs.io/en/latest/reference/argocd/#resource-customizations) 覆寫。

以下範例展示了 `cert-manager.io/Certificate` 的健康狀態檢查。

```yaml
data:
  resource.customizations.health.cert-manager.io_Certificate: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end

    hs.status = "Progressing"
    hs.message = "Waiting for certificate"
    return hs
```

為了避免為可能的多個資源重複自訂健康狀態檢查，也可以在資源種類中以及資源群組的任何位置指定萬用字元，如下所示：

```yaml
  resource.customizations: |
    ec2.aws.crossplane.io/*:
      health.lua: |
        ...
```

```yaml
  # 如果金鑰以萬用字元 _開始_，請確保 GVK 金鑰被引號括起來。
  resource.customizations: |
    "*.aws.crossplane.io/*":
      health.lua: |
        ...
```

> [!IMPORTANT]
> 請注意，萬用字元僅在使用 `resource.customizations` 金鑰時才受支援，`resource.customizations.health.<group>_<kind>`
> 樣式的金鑰不起作用，因為 Kubernetes configmap 金鑰不支援萬用字元 (`*`)。

`obj` 是一個包含資源的全域變數。腳本必須傳回一個包含狀態和可選訊息欄位的物件。
自訂健康狀態檢查可能傳回以下健康狀態之一：

  * `Healthy` - 資源健康
  * `Progressing` - 資源尚未健康，但仍在進展中，可能很快就會健康
  * `Degraded` - 資源已降級
  * `Suspended` - 資源已暫停，正在等待某些外部事件恢復（例如，暫停的 CronJob 或暫停的 Deployment）

預設情況下，健康狀態通常傳回 `Progressing` 狀態。

注意：作為一項安全措施，預設情況下將停用對標準 Lua 函式庫的存取。管理員可以透過
設定 `resource.customizations.useOpenLibs.<group>_<kind>` 來控制存取。在以下範例中，為 `cert-manager.io/Certificate` 的健康狀態檢查啟用了標準函式庫。

```yaml
data:
  resource.customizations.useOpenLibs.cert-manager.io_Certificate: true
  resource.customizations.health.cert-manager.io_Certificate: |
    # 此腳本已啟用 Lua 標準函式庫
```

### 方法 2. 貢獻自訂健康狀態檢查

健康狀態檢查可以捆綁到 Argo CD 中。自訂健康狀態檢查腳本位於 [https://github.com/argoproj/argo-cd](https://github.com/argoproj/argo-cd) 的 `resource_customizations` 目錄中。這必須具有以下目錄結構：

```
argo-cd
|-- resource_customizations
|    |-- your.crd.group.io               # CRD 群組
|    |    |-- MyKind                     # 資源種類
|    |    |    |-- health.lua            # 健康狀態檢查
|    |    |    |-- health_test.yaml      # 測試輸入和預期結果
|    |    |    +-- testdata              # 包含測試資源 YAML 定義的目錄
```

每個健康狀態檢查都必須在 `health_test.yaml` 檔案中定義測試。`health_test.yaml` 是一個具有以下結構的 YAML 檔案：

```yaml
tests:
- healthStatus:
    status: ExpectedStatus
    message: Expected message
  inputPath: testdata/test-resource-definition.yaml
```

若要測試已實作的自訂健康狀態檢查，請執行 `go test -v ./util/lua/`。

[PR#1139](https://github.com/argoproj/argo-cd/pull/1139) 是 Cert Manager CRD 自訂健康狀態檢查的一個範例。

#### 內建健康狀態檢查的萬用字元支援

您可以透過在群組或種類目錄名稱中使用萬用字元，為多個資源使用單一健康狀態檢查。

`_` 字元的作用類似於 `*` 萬用字元。例如，考慮以下目錄結構：

```
argo-cd
|-- resource_customizations
|    |-- _.group.io               # CRD 群組
|    |    |-- _                   # 資源種類
|    |    |    |-- health.lua     # 健康狀態檢查
```

任何群組以 `.group.io` 結尾的資源都將使用 `health.lua` 中的健康狀態檢查。

僅當沒有針對該資源的特定檢查時，才會評估萬用字元檢查。

如果多個萬用字元檢查匹配，則使用目錄結構中的第一個。

我們使用 [doublestar](https://github.com/bmatcuk/doublestar) glob 函式庫來匹配萬用字元檢查。我們目前
僅在路徑包含 `_` 字元時才將其視為萬用字元，但這在未來可能會改變。

> [!IMPORTANT]
> **避免龐大的腳本**
>
> 避免編寫龐大的腳本來處理多個資源。它們會變得難以閱讀和維護。相反，只需在特定於資源的腳本中
> 複製相關部分。

## 覆寫基於 Go 的健康狀態檢查

某些資源的健康狀態檢查是[以 Go 程式碼硬式編碼](https://github.com/argoproj/argo-cd/tree/master/gitops-engine/pkg/health)的，
因為 Lua 支援是在之後才引入的。此外，某些資源的健康狀態檢查邏輯過於複雜，因此
以 Go 實作更容易。

可以覆寫內建資源的健康狀態檢查。Argo 將優先使用設定的健康狀態檢查，而不是
基於 Go 的內建檢查。

以下資源具有基於 Go 的健康狀態檢查：

* PersistentVolumeClaim
* Pod
* Service
* apiregistration.k8s.io/APIService
* apps/DaemonSet
* apps/Deployment
* apps/ReplicaSet
* apps/StatefulSet
* argoproj.io/Workflow
* autoscaling/HorizontalPodAutoscaler
* batch/Job
* extensions/Ingress
* networking.k8s.io/Ingress

## 健康狀態檢查

Argo CD 應用程式的健康狀態是從其在應用程式來源中表示的直接子資源的健康狀態推斷出來的。
應用程式的健康狀態將是其**直接子資源中最差的健康狀態**，基於以下優先順序（從最健康到最不健康）：
**Healthy, Suspended, Progressing, Missing, Degraded, Unknown.**
例如，如果一個應用程式有一個 Missing 資源和一個 Degraded 資源，則該應用程式的健康狀態將是 **Degraded**。

但資源的健康狀態不會從子資源繼承 - 它是僅使用有關
資源本身的資訊計算的。資源的狀態欄位可能包含也可能不包含有關子資源健康狀態的資訊，並且
資源的健康狀態檢查可能考慮也可能不考慮該資訊。

缺乏繼承是刻意設計的。無法從其子項推斷資源的健康狀態，因為
子資源的健康狀態可能與父資源的健康狀態無關。例如，Deployment 的健康狀態不
一定受其 Pod 的健康狀態影響。

```
App (healthy)
└── Deployment (healthy)
    └── ReplicaSet (healthy)
        └── Pod (healthy)
    └── ReplicaSet (unhealthy)
        └── Pod (unhealthy)
```

如果您希望子資源的健康狀態影響其父資源的健康狀態，您需要設定父資源的健康狀態
檢查以考慮子資源的健康狀態。由於只有父資源的狀態可供健康狀態檢查使用，
父資源的控制器需要將子資源的健康狀態提供在父資源的狀態
欄位中。

```
App (healthy)
└── CustomResource (healthy) <- 此資源的健康狀態檢查需要修正才能將應用程式標記為不健康
    └── CustomChildResource (unhealthy)
```
## 忽略應用程式中的子資源健康狀態檢查

若要忽略應用程式中直接子資源的健康狀態檢查，請將註解 `argocd.argoproj.io/ignore-healthcheck` 設定為 `true`。例如：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    argocd.argoproj.io/ignore-healthcheck: "true"
```

這樣做，Deployment 的健康狀態將不會影響其父應用程式的健康狀態。
