# UI 自訂

## 預設應用程式詳細資料檢視

預設情況下，「應用程式詳細資料」將顯示「樹狀」檢視。

這可以在每個應用程式的基礎上進行設定，方法是設定 `pref.argocd.argoproj.io/default-view` 註解，可接受的值為：`tree`、`pods`、`network`、`list`。

對於 Pods 檢視，可以使用 `pref.argocd.argoproj.io/default-pod-sort` 註解來設定預設的分組機制，可接受的值為：`node`、`parentResource`、`topLevelResource`。

## Pod 檢視中的節點標籤

可以透過在 [argocd-cm](argocd-cm-yaml.md) ConfigMap 中設定 `application.allowedNodeLabels`，將節點標籤傳播到 Pod 檢視中的節點資訊。

以下設定：
```yaml
application.allowedNodeLabels: topology.kubernetes.io/zone,karpenter.sh/capacity-type
```
將導致：
![Pod 檢視中的節點標籤](../assets/application-pod-view-node-labels.png)
