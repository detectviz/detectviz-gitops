# 漸進式同步

> [!WARNING]
> **Alpha 功能 (自 v2.6.0 起)**
>

    這是一個實驗性的 [alpha 品質](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#alpha)
    功能，可讓您控制 ApplicationSet 控制器建立或更新
    由 ApplicationSet 資源擁有的應用程式的順序。它可能會在未來的版本中移除或以不向後相容的方式修改。

## 使用案例

漸進式同步功能集的設計目標是輕量且靈活。此功能僅與受控應用程式的健康狀態互動。它不支援與其他 Rollout 控制器（例如原生的 ReplicaSet 控制器或 Argo Rollouts）的直接整合。

- 漸進式同步會監看受控應用程式資源變為「健康」，然後再繼續進行下一階段。
- 支援 Deployments、DaemonSets、StatefulSets 和 [Argo Rollouts](https://argoproj.github.io/argo-rollouts/)，因為應用程式在推出 Pod 時會進入「進行中」狀態。事實上，任何具有健康檢查且可以報告「進行中」狀態的資源都受支援。
- 支援 [Argo CD 資源勾點](../../user-guide/resource_hooks.md)。對於無法使用 Argo Rollout 時需要進階功能的使用者，例如在 DaemonSet 變更後進行煙霧測試，我們建議使用此方法。

## 啟用漸進式同步

作為一個實驗性功能，必須明確啟用漸進式同步，方法如下。

1. 將 `--enable-progressive-syncs` 傳遞給 ApplicationSet 控制器參數。
1. 在 ApplicationSet 控制器環境變數中設定 `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS=true`。
1. 在 Argo CD `argocd-cmd-params-cm` ConfigMap 中設定 `applicationsetcontroller.enable.progressive.syncs: true`。

## 策略

ApplicationSet 策略控制應用程式的建立（或更新）和刪除方式。這些操作使用兩個獨立的欄位進行設定：

- **建立策略** (`type` 欄位)：控制應用程式的建立和更新
- **刪除策略** (`deletionOrder` 欄位)：控制應用程式的刪除順序

### 建立策略

`type` 欄位控制應用程式的建立和更新方式。可用值：

- **AllAtOnce** (預設)
- **RollingSync**

#### AllAtOnce

此預設應用程式更新行為與原始 ApplicationSet 實作相同。

當 ApplicationSet 更新時，由 ApplicationSet 資源管理的所有應用程式都會同時更新。

```yaml
spec:
  strategy:
    type: AllAtOnce # 明確指定，但這是預設值
```

#### RollingSync

此更新策略可讓您根據產生的應用程式資源上的標籤將應用程式分組。
當 ApplicationSet 變更時，變更將會循序套用到每個應用程式資源群組。

- 應用程式群組是使用其標籤和 `matchExpressions` 來選取的。
- 所有 `matchExpressions` 都必須為 true，應用程式才會被選取（多個運算式以 AND 行為進行比對）。
- `In` 和 `NotIn` 運算子必須至少符合一個值才被視為 true（OR 行為）。
- 如果 `NotIn` 和 `In` 運算子都產生符合項目，則 `NotIn` 運算子優先。
- 每個群組中的所有應用程式都必須變為 Healthy，ApplicationSet 控制器才會繼續更新下一個應用程式群組。
- 群組中同時更新的應用程式數量不會超過其 `maxUpdate` 參數（預設為 100%，無限制）。
- RollingSync 會擷取 ApplicationSet 資源外部的變更，因為它依賴於監看受控應用程式的 OutOfSync 狀態。
- RollingSync 會強制所有產生的應用程式停用自動同步。對於任何啟用自動 syncPolicy 的應用程式規格，applicationset-controller 記錄檔中都會印出警告。
- 同步操作的觸發方式與透過 UI 或 CLI 觸發的方式相同（透過直接在應用程式資源上設定 `operation` 狀態欄位）。這表示 RollingSync 會尊重同步視窗，就像使用者在 Argo UI 中按一下「同步」按鈕一樣。
- 觸發同步時，同步會使用為應用程式設定的相同 syncPolicy 執行。例如，這會保留應用程式的重試設定。
- 如果應用程式在任何步驟中都未被選取，則會從滾動同步中排除，需要透過 CLI 或 UI 手動同步。

```yaml
spec:
  strategy:
    type: RollingSync
    rollingSync:
      steps:
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-dev
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-prod
          maxUpdate: 10%
```

### 刪除策略

`deletionOrder` 欄位控制從 ApplicationSet 中移除應用程式時的刪除順序。可用值：

- **AllAtOnce** (預設)
- **Reverse**

#### AllAtOnce 刪除

這是預設行為，所有需要刪除的應用程式都會同時被移除。這適用於 `AllAtOnce` 和 `RollingSync` 建立策略。

```yaml
spec:
  strategy:
    type: RollingSync # 或 AllAtOnce
    deletionOrder: AllAtOnce # 明確指定，但這是預設值
```

#### 反向刪除

當使用 `deletionOrder: Reverse` 搭配 RollingSync 策略時，應用程式會以 `rollingSync.steps` 中定義的步驟的反向順序刪除。這可確保在較晚步驟中部署的應用程式會先於在較早步驟中部署的應用程式被刪除。
當您需要以特定順序拆除相依服務時，此策略特別有用。

**反向刪除的需求：**

- 必須與 `type: RollingSync` 一起使用
- 需要定義 `rollingSync.steps`
- 應用程式會以步驟順序的反向順序刪除

**重要事項：** 在所有應用程式成功刪除之前，不會移除 ApplicationSet finalizer。這可確保正確的清理，並防止在受控應用程式之前移除 ApplicationSet。

```yaml
spec:
  strategy:
    type: RollingSync
    deletionOrder: Reverse
    rollingSync:
      steps:
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-dev # 步驟 1：最先建立，最後刪除
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-prod # 步驟 2：第二個建立，最先刪除
```

在此範例中，刪除應用程式時：

1. `env-prod` 應用程式（步驟 2）會先被刪除
2. `env-dev` 應用程式（步驟 1）會第二個被刪除

此刪除順序對於您需要以正確順序拆除相依服務的場景很有用，例如在後端相依性之前刪除前端服務。

#### 範例

以下範例說明如何對具有明確設定的環境標籤的應用程式進行漸進式同步。

推送變更後，將會依序發生以下情況。

- 所有 `env-dev` 應用程式將會同時更新。
- 推出將會等待所有 `env-qa` 應用程式透過 `argocd` CLI 或按一下 UI 中的「同步」按鈕手動同步。
- 一次將會更新 10% 的 `env-prod` 應用程式，直到所有 `env-prod` 應用程式都已更新為止。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
    - list:
        elements:
          - cluster: engineering-dev
            url: https://1.2.3.4
            env: env-dev
          - cluster: engineering-qa
            url: https://2.4.6.8
            env: env-qa
          - cluster: engineering-prod
            url: https://9.8.7.6/
            env: env-prod
  strategy:
    type: RollingSync
    deletionOrder: Reverse # 應用程式將會以步驟的反向順序刪除
    rollingSync:
      steps:
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-dev
          #maxUpdate: 100%  # 如果未定義，所有符合的應用程式都會一起更新（預設為 100%）
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-qa
          maxUpdate: 0 # 如果為 0，則不會更新任何符合的應用程式
        - matchExpressions:
            - key: envLabel
              operator: In
              values:
                - env-prod
          maxUpdate: 10% # maxUpdate 支援整數和百分比字串值（向下取整，但對於 >0% 的應用程式，最低為 1 個）
  goTemplate: true
  goTemplateOptions: ['missingkey=error']
  template:
    metadata:
      name: '{{.cluster}}-guestbook'
      labels:
        envLabel: '{{.env}}'
    spec:
      project: my-project
      source:
        repoURL: https://github.com/infra-team/cluster-deployments.git
        targetRevision: HEAD
        path: guestbook/{{.cluster}}
      destination:
        server: '{{.url}}'
        namespace: guestbook
```
