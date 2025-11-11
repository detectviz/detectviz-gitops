# 差異比較策略

Argo CD 會計算期望狀態與即時狀態之間的差異，以定義應用程式是否不同步。此相同
邏輯也用於 Argo CD UI 中，以顯示應用程式所有資源的即時狀態與期望狀態
之間的差異。

Argo CD 目前有 3 種不同的策略來計算差異：

- **舊版**：這是預設使用的主要差異比較策略。它
  會根據即時狀態、期望狀態和
  last-applied-configuration（註釋）套用三向差異比較。
- **結構化合併差異**：啟用伺服器端套用同步選項時自動套用的策略。
- **伺服器端差異**：一種新策略，它以 dryrun 模式叫用伺服器端套用
  以產生預測的即時狀態。

## 結構化合併差異

> [!WARNING]
> **功能已停用**
>
> 在社群發現不同問題後，此策略正被淘汰，改用伺服器端差異。

此差異比較策略在啟用伺服器端套用
同步選項時會自動使用。它使用 Kubernetes 用於根據欄位所有權計算差異的 [structured-merge-diff][2] 函式庫。
使用此策略來計算定義預設值的 CRD 的差異時會遇到一些挑戰。

## 伺服器端差異
*目前狀態：穩定（自 v3.1.0 起）*

此差異比較策略將對應用程式的每個資源以 dryrun 模式執行伺服器端套用。
此操作的回應然後會與即時狀態進行比較，以提供差異比較結果。差異比較結果會被快取，並且只有在以下情況下才會觸發新的伺服器端套用請求到 Kube API
：

- 請求了應用程式重新整理或強制重新整理。
- Argo CD 應用程式所指向的儲存庫中有新的修訂版本。
- Argo CD 應用程式規格已變更。
- 即時狀態中資源本身的[資源版本][3]已變更

伺服器端差異的一個優點是 Kubernetes 准入
控制器將參與差異比較計算。例如，如果
驗證 webhook 將資源識別為無效，則會在差異比較階段而非同步
階段通知 Argo CD。

請注意，在建立新資源期間不會執行伺服器端差異。
這是為了節省對 KubeAPI 的額外呼叫，並在資源不存在以進行比較時提供更輕量且更快速的差異比較計算
（非伺服器端套用）。在資源建立期間執行
伺服器端差異將無法在差異比較階段獲得 Kubernetes 准入控制器的好處，因為如果資源尚未套用在叢集中，則在計算差異時不會執行驗證 webhook
。

### 啟用它

伺服器端差異可以在 Argo CD 控制器層級或每個
應用程式啟用。

**為所有應用程式啟用伺服器端差異**

在 argocd-cmd-params-cm configmap 中新增以下項目：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  controller.diff.server.side: "true"
...
```

注意：套用此組態後，需要重新啟動 `argocd-application-controller`
。

**為一個應用程式啟用伺服器端差異**

在 Argo CD 應用程式資源中新增以下註釋：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/compare-options: ServerSideDiff=true
...
```

**為一個應用程式停用伺服器端差異**

如果您的 Argo CD 實例中已全域啟用伺服器端差異，
則可以在應用程式層級停用它。為此，
在應用程式資源中新增以下註釋：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/compare-options: ServerSideDiff=false
...
```

*注意：請回報任何迫使您停用
伺服器端差異功能的問題*

### 變動中的 Webhook

預設情況下，伺服器端差異不包含由變動中的 webhook 所做的變更。
如果您想在 Argo CD 差異中包含變動中的 webhook，請在 Argo CD 應用程式資源中新增以下註釋：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/compare-options: IncludeMutationWebhook=true
...
```

注意：此註釋僅在啟用伺服器端差異時有效。
若要為給定的應用程式啟用這兩個選項，請在 Argo CD 應用程式資源中新增以下註釋：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/compare-options: ServerSideDiff=true,IncludeMutationWebhook=true
...
```

[1]: https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#beta
[2]: https://github.com/kubernetes-sigs/structured-merge-diff
[3]: https://kubernetes.io/docs/reference/using-api/api-concepts/#resourceversion-in-metadata
