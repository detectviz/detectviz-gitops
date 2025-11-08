# 動態叢集分佈

> [!WARNING]
> **Alpha 功能 (自 v2.9.0 起)**
>
> 這是一個實驗性的、[alpha 品質](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#alpha) 的功能。
> 它可能會在未來的版本中被移除或以不向後相容的方式進行修改。

*目前狀態：[Alpha][1] (自 v2.9.0 起)*

預設情況下，叢集會無限期地分配給分片。對於使用預設的、基於雜湊的分片演算法的使用者來說，這種靜態分配是沒有問題的：分片將始終由基於雜湊的演算法大致平衡。但對於使用[輪詢](high_availability.md#argocd-application-controller)或其他自訂分片分配演算法的使用者來說，當新增或移除副本時，這種靜態分配可能會導致分片不平衡。

從 v2.9 開始，Argo CD 支援動態叢集分佈功能。當新增或移除副本時，會重新執行分片演算法以確保叢集根據演算法進行分佈。如果演算法是均衡的，例如輪詢，那麼分片將是均衡的。

以前，分片計數是透過 `ARGOCD_CONTROLLER_REPLICAS` 環境變數設定的。變更環境變數會強制重新啟動所有應用程式控制器 pod。現在，分片計數是透過部署的 `replicas` 欄位設定的，這不需要重新啟動應用程式控制器 pod。

## 啟用叢集的動態分佈

此功能在 alpha 階段預設為停用。為了利用此功能，可以將 `manifests/ha/base/controller-deployment/` 中的清單作為 Kustomize 覆蓋來應用。此覆蓋會將 StatefulSet 副本設定為 `0`，並將應用程式控制器部署為 Deployment。此外，當將應用程式控制器作為部署執行時，您必須將環境變數 `ARGOCD_ENABLE_DYNAMIC_CLUSTER_DISTRIBUTION` 設定為 true。

> [!IMPORTANT]
> 使用 Deployment 而不是 StatefulSet 是一個實作細節，可能會在此功能的未來版本中發生變化。因此，Kustomize 覆蓋的目錄名稱也可能會改變。請注意版本說明以避免問題。

請注意新環境變數 `ARGOCD_CONTROLLER_HEARTBEAT_TIME` 的引入。該環境變數在[動態分佈心跳程序的運作方式](#working-of-dynamic-distribution)中有說明。

## 動態分佈的運作方式

為了實現叢集的執行時期分佈，應用程式控制器使用 ConfigMap 將控制器 pod 與分片號碼關聯起來，並使用心跳來確保控制器 pod 仍然存活並處理其分片，實際上是它們的工作份額。

應用程式控制器將建立一個名為 `argocd-app-controller-shard-cm` 的新 ConfigMap 來儲存控制器 <-> 分片對應。每個分片的對應如下所示：

```yaml
ShardNumber    : 0
ControllerName : "argocd-application-controller-hydrxyt"
HeartbeatTime  : "2009-11-17 20:34:58.651387237 +0000 UTC"
```

* `ControllerName`：儲存應用程式控制器 pod 的主機名稱
* `ShardNumber`：儲存由控制器 pod 管理的分片號碼
* `HeartbeatTime`：儲存此心跳上次更新的時間。

控制器分片對應在 pod 的每次就緒探測檢查期間更新到 ConfigMap 中，也就是每 10 秒（或另行設定）。控制器將在每次就緒探測檢查的迭代中獲取分片，並嘗試使用 `HeartbeatTime` 更新 ConfigMap。預設的 `HeartbeatDuration`（心跳應更新的時間間隔）為 `10` 秒。如果任何控制器 pod 的 ConfigMap 超過 `3 * HeartbeatDuration` 沒有更新，則該應用程式 pod 的就緒探測會被標記為 `Unhealthy`。若要增加預設的 `HeartbeatDuration`，您可以設定環境變數 `ARGOCD_CONTROLLER_HEARTBEAT_TIME` 並指定所需的值。

新的分片機制不會監控環境變數 `ARGOCD_CONTROLLER_REPLICAS`，而是直接從應用程式控制器 Deployment 中讀取副本計數。控制器透過比較應用程式控制器 Deployment 中的副本計數和 `argocd-app-controller-shard-cm` ConfigMap 中的對應數量來識別副本數量的變化。

在應用程式控制器副本數量增加的情況下，會在 `argocd-app-controller-shard-cm` ConfigMap 的對應清單中新增一個條目，並觸發叢集分佈以重新分佈叢集。

在應用程式控制器副本數量減少的情況下，`argocd-app-controller-shard-cm` ConfigMap 中的對應會被重置，每個控制器會再次獲取分片，從而觸發叢集的重新分佈。
