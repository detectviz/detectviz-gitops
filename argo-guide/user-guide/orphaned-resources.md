# 孤立資源監控

[孤立的 Kubernetes 資源](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#orphaned-dependents) 是不屬於任何 Argo CD 應用程式的頂層命名空間資源。孤立資源監控功能允許
偵測孤立資源、使用 Argo CD UI 檢查/移除資源，並產生警告。

孤立資源監控是在[專案](projects.md)設定中啟用的。
以下是使用 AppProject 自訂資源啟用此功能的範例。

```yaml
kind: AppProject
metadata:
  ...
spec:
  ...
  orphanedResources:
    warn: true
...
```

一旦啟用此功能，每個在其目標命名空間中具有任何孤立資源的專案應用程式
都會收到警告。可以透過啟用「顯示孤立」篩選器，在應用程式詳細資料頁面中找到孤立資源：

![孤立資源](../assets/orphaned-resources.png)

啟用此功能時，您可能需要考慮先停用警告。

```yaml
spec:
  orphanedResources:
    warn: false # 停用警告
```

停用警告時，應用程式使用者仍然可以在 UI 中檢視孤立資源。

## 例外

並非 Kubernetes 叢集中的每個資源都由終端使用者控制並由 Argo CD 管理。叢集中的其他運算子可以自動建立資源（例如，cert-manager 建立 secret），然後這些資源會被視為孤立的。

以下資源永遠不會被視為孤立的：

* 在專案中被拒絕的命名空間資源。通常，此類資源由叢集管理員管理，不應由命名空間使用者修改。
* 名稱為 `default` 的 `ServiceAccount`（以及對應的自動產生的 `ServiceAccountToken`）。
* `default` 命名空間中名為 `kubernetes` 的 `Service`。
* 所有命名空間中名為 `kube-root-ca.crt` 的 `ConfigMap`。

您可以透過提供一個忽略規則清單來防止資源被宣告為孤立的，每個規則都定義了一個群組、種類和名稱。

```yaml
spec:
  orphanedResources:
    ignore:
    - kind: ConfigMap
      name: orphaned-but-ignored-configmap
```

`name` 可以是 [glob 模式](https://github.com/gobwas/glob)，例如：

```yaml
spec:
  orphanedResources:
    ignore:
    - kind: Secret
      name: *.example.com
```
