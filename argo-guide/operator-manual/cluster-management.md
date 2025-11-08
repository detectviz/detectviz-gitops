# 叢集管理

本指南適用於希望在 CLI 上管理叢集的操作員。如果您想為此使用 Kubernetes 資源，請參閱[宣告式設定](./declarative-setup.md#clusters)。

此處並未描述所有指令，請參閱 [argocd cluster 指令參考](../user-guide/commands/argocd_cluster.md)以取得所有可用指令。

## 新增叢集

執行 `argocd cluster add context-name`。

如果您不確定上下文名稱，請執行 `kubectl config get-contexts` 以列出所有名稱。

這將連接到叢集並安裝 ArgoCD 連接到它所需的必要資源。
請注意，您將需要對叢集的特權存取權限。

## 移除叢集

執行 `argocd cluster rm context-name`。

這會移除具有指定名稱的叢集。

> [!NOTE]
> **in-cluster 無法被移除**
>
> `in-cluster` 叢集無法透過此方式移除。如果您想停用 `in-cluster` 設定，您需要更新您的 `argocd-cm` ConfigMap。將 [`cluster.inClusterEnabled`](./argocd-cm-yaml.md) 設定為 `"false"`。
