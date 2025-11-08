# 協調最佳化

預設情況下，每當屬於 Argo CD 應用程式的資源發生變更時，該應用程式都會被重新整理。

Kubernetes 控制器通常會定期更新其監看的資源，這會導致應用程式持續進行協調操作，並在 `argocd-application-controller` 上造成高 CPU 使用率。Argo CD 可讓您選擇性地忽略特定欄位上[受追蹤資源](../user-guide/resource_tracking.md)的資源更新。對於未受追蹤的資源，您可以使用 [argocd.argoproj.io/ignore-resource-updates 註解](#ignoring-updates-for-untracked-resources)。

當資源更新被忽略時，如果資源的[健康狀態](./health.md)沒有改變，則該資源所屬的應用程式將不會進行協調。

## 系統級組態

預設情況下，`resource.ignoreResourceUpdatesEnabled` 設定為 `true`，使 Argo CD 能夠忽略資源更新。此預設設定可確保 Argo CD 透過減少不必要的協調操作來維持可持續的效能。如果您需要變更此行為，可以在 `argocd-cm` ConfigMap 中明確地將 `resource.ignoreResourceUpdatesEnabled` 設定為 `false`：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.ignoreResourceUpdatesEnabled: 'false'
```

Argo CD 允許使用 [RFC6902 JSON 修補程式](https://tools.ietf.org/html/rfc6902)和 [JQ 路徑運算式](<https://stedolan.github.io/jq/manual/#path(path_expression)>)在特定的 JSON 路徑上忽略資源更新。可以在 `argocd-cm` ConfigMap 的 `resource.customizations` 金鑰中為指定的群組和種類進行設定。

以下是一個自訂範例，它忽略了 [`ExternalSecret`](https://external-secrets.io/main/api/externalsecret/) 資源的 `refreshTime` 狀態欄位：

```yaml
data:
  resource.customizations.ignoreResourceUpdates.external-secrets.io_ExternalSecret:
    |
    jsonPointers:
    - /status/refreshTime
    # 上述的 JQ 等效寫法：
    # jqPathExpressions:
    # - .status.refreshTime
```

可以將 `ignoreResourceUpdates` 設定為應用於由 Argo CD 執行個體管理的所有應用程式中的所有受追蹤資源。為此，可以如下範例所示設定資源自訂：

```yaml
data:
  resource.customizations.ignoreResourceUpdates.all: |
    jsonPointers:
    - /status
```

### 使用 ignoreDifferences 忽略協調

預設情況下，現有的系統級 `ignoreDifferences` 自訂也將被新增以忽略資源更新。這有助於減少組態管理，因為可以防止您複製所有現有的忽略差異組態。

若要停用此行為，可以停用 `ignoreDifferencesOnResourceUpdates` 設定：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  resource.compareoptions: |
    ignoreDifferencesOnResourceUpdates: false
```

## 預設組態

預設情況下，對於所有資源，中繼資料欄位 `generation`、`resourceVersion` 和 `managedFields` 始終被忽略。

## 尋找要忽略的資源

應用程式控制器會在資源變更觸發重新整理時記錄日誌。您可以使用這些日誌來尋找高變動率的資源種類，然後檢查這些資源以尋找要忽略的欄位。

若要尋找這些日誌，請搜尋 `"Requesting app refresh caused by object update"`。日誌包含 `api-version` 和 `kind` 的結構化欄位。按 api-version/kind 計算觸發的重新整理次數，應該可以找出高變動率的資源種類。

> [!NOTE]
> 這些日誌的層級為 `debug`。請將應用程式控制器的日誌層級設定為 `debug`。

一旦您確定了某些經常變更的資源，就可以嘗試確定哪些欄位正在變更。以下是一種方法：

```shell
kubectl get <resource> -o yaml > /tmp/before.yaml
# 等待一兩分鐘。
kubectl get <resource> -o yaml > /tmp/after.yaml
diff /tmp/before.yaml /tmp/after.yaml
```

差異可以讓您了解哪些欄位正在變更，或許應該被忽略。

## 檢查資源更新是否被忽略

每當 Argo CD 因忽略的資源更新而跳過重新整理時，控制器都會記錄以下一行：
"Ignoring change of object because none of the watched resource fields have changed"。

在應用程式控制器日誌中搜尋此行，以確認您的資源忽略規則正在被應用。

> [!NOTE]
> 這些日誌的層級為 `debug`。請將應用程式控制器的日誌層級設定為 `debug`。

## 範例

### argoproj.io/Application

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  resource.customizations.ignoreResourceUpdates.argoproj.io_Application: |
    jsonPointers:
    # 忽略 ownerReferences 變更時，例如當父 ApplicationSet 經常變更時。
    - /metadata/ownerReferences
    # 忽略 reconciledAt，因為它本身並不表示任何重要的變更。
    - /status/reconciledAt
    jqPathExpressions:
    # 忽略條件的 lastTransitionTime；當 SharedResourceWarning 定期更新但內容實際上沒有變更時很有用。
    - .status?.conditions[]?.lastTransitionTime
```

## 忽略未受追蹤資源的更新

ArgoCD 僅會將 `ignoreResourceUpdates` 組態應用於應用程式的受追蹤資源。這表示相依的資源，例如由 `Deployment` 建立的 `ReplicaSet` 和 `Pod`，將不會忽略任何更新，並且會因為任何變更而觸發應用程式的協調。

如果您想將 `ignoreResourceUpdates` 組態應用於未受追蹤的資源，可以在相依資源的清單中新增 `argocd.argoproj.io/ignore-resource-updates=true` 註解。

## 範例

### CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hello
  namespace: test-cronjob
spec:
  schedule: '* * * * *'
  jobTemplate:
    metadata:
      annotations:
        argocd.argoproj.io/ignore-resource-updates: 'true'
    spec:
      template:
        metadata:
          annotations:
            argocd.argoproj.io/ignore-resource-updates: 'true'
        spec:
          containers:
            - name: hello
              image: busybox:1.28
              imagePullPolicy: IfNotPresent
              command:
                - /bin/sh
                - -c
                - date; echo Hello from the Kubernetes cluster
          restartPolicy: OnFailure
```

資源更新將根據您在 `argocd-cm` configMap 中的 `ignoreResourceUpdates` 組態被忽略：

`argocd-cm`:

```yaml
resource.customizations.ignoreResourceUpdates.batch_Job: |
  jsonPointers:
    - /status
resource.customizations.ignoreResourceUpdates.Pod: |
  jsonPointers:
    - /status
```
