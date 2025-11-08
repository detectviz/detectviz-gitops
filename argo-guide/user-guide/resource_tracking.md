# 資源追蹤

## 透過註解追蹤 Kubernetes 資源

可以指示 Argo CD 使用以下方法進行追蹤：

1. `annotation`（預設）- Argo CD 使用 `argocd.argoproj.io/tracking-id` 註解來追蹤應用程式資源。當您不需要同時維護標籤和註解時，請使用此方法。
2. `annotation+label` - Argo CD 使用 `app.kubernetes.io/instance` 標籤，但僅供參考。該標籤不用於追蹤目的，如果長度超過 63 個字元，該值仍會被截斷。`argocd.argoproj.io/tracking-id` 註解則用於追蹤應用程式資源。對於您使用 Argo CD 管理的資源，但仍需要與需要實例標籤的其他工具相容，請使用此方法。
3. `label` - Argo CD 使用 `app.kubernetes.io/instance` 標籤


以下是使用註解方法追蹤資源的範例：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: default
  annotations:
    argocd.argoproj.io/tracking-id: my-app:apps/Deployment:default/my-deployment
```

使用追蹤 ID 註解的優點是，不再與其他 Kubernetes 工具發生衝突，Argo CD 也絕不會對資源的所有者感到困惑。如果您希望其他工具理解由 Argo CD 管理的資源，也可以使用 `annotation+label`。

### 安裝 ID

如果您使用多個 Argo CD 實例管理一個叢集，您需要在 Argo CD ConfigMap 中設定 `installationID`。這將防止不同 Argo CD 實例之間的衝突：

* 每個受管理的資源都將具有註解 `argocd.argoproj.io/installation-id: <installation-id>`
* 可以在 Argo CD 實例中擁有相同名稱的應用程式而不會引起衝突。

### 非自我參照註解
當使用追蹤方法 `annotation` 或 `annotation+label` 時，Argo CD 會考慮註解中的資源屬性（名稱、命名空間、群組和種類），以確定是否應將該資源與期望狀態進行比較。如果追蹤註解未參照其所套用的資源，則該資源既不會影響應用程式的同步狀態，也不會被標記為待刪除。

這允許其他 kubernetes 工具（例如 [HNC](https://github.com/kubernetes-sigs/hierarchical-namespaces)）將資源複製到不同的命名空間，而不會影響 Argo CD 應用程式的同步狀態。複製的資源將在 UI 的頂層可見。它們將沒有同步狀態，也不會影響應用程式的同步狀態。


## 透過標籤追蹤 Kubernetes 資源

在此模式下，Argo CD 透過在所有受管理（即從 Git 中協調）的資源上將應用程式實例標籤設定為管理應用程式的名稱來識別其管理的資源。使用的預設標籤是眾所周知的標籤 `app.kubernetes.io/instance`。

範例：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: default
  labels:
    app.kubernetes.io/instance: some-application
```

這種方法在大多數情況下運作良好，因為標籤的名稱是標準化的，並且可以被 Kubernetes 生態系統中的其他工具理解。

然而，有幾個限制：

* 標籤被截斷為 63 個字元。根據標籤的大小，您可能希望為您的應用程式儲存更長的名稱
* 其他外部工具可能會寫入/附加到此標籤，並與 Argo CD 產生衝突。例如，一些 Helm 圖表和運算子也將此標籤用於產生的資訊清單，這會讓 Argo CD 對應用程式的所有者感到困惑
* 您可能希望在同一叢集上部署多個 Argo CD 實例（具有叢集範圍的權限），並有一種簡單的方法來識別哪個資源由哪個 Argo CD 實例管理

### 使用自訂標籤

Argo CD 可以設定為使用自訂標籤，而不是使用預設的 `app.kubernetes.io/instance` 標籤進行資源追蹤。以下範例將資源追蹤標籤設定為 `argocd.argoproj.io/instance`。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  application.instanceLabelKey: argocd.argoproj.io/instance
```

## 選擇追蹤方法

若要實際選擇您偏好的追蹤方法，請編輯 `argocd-cm` configmap 中包含的 `resourceTrackingMethod` 值。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  application.resourceTrackingMethod: annotation
```
可能的值為 `label`、`annotation+label` 和 `annotation`，如上所述。

請注意，一旦您變更了值，您需要再次同步您的應用程式（或等待同步機制啟動），才能套用您的變更。

您可以再次變更 configmap，以還原到先前的選擇。
