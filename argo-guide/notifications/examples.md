在此處，您可以找到一些關於 Argo CD 中通知服務可以做什麼的範例。

## 在同步發生時收到通知並了解您的資源如何變更

透過 Argo CD，您可以建立一個通知系統，告訴您同步何時發生以及它變更了什麼。
若要在同步發生時透過 webhook 收到通知，您可以新增以下觸發器：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.on-deployed-webhook: |
    url: <your-webhook-url>
    headers:
    - name: "Content-Type"
      value: "application/json"

  template.on-deployed-template: |
    webhook:
      on-deployed-webhook:
        method: POST
        body: |
              {{toJson .app.status.operationState.syncResult}}


  trigger.on-deployed-trigger: |
    when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
    oncePer: app.status.sync.revision
    send: [on-deployed-template]
```

如[觸發器部分](triggers/#avoid-sending-same-notification-too-often)所述，這將在應用程式同步並健康時產生通知。然後，我們需要為 webhook 整合建立訂閱：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-deployed-trigger.on-deployed-webhook: ""
```

您可以透過新增任何 webhook 網站並同步我們的應用程式來測試此功能是否正常運作並查看回應的外觀。在此處，您可以看到我們收到一個資源清單，其中包含訊息和它們的一些屬性。例如：

```json
{
  "resources": [
    {
      "group": "apps",
      "hookPhase": "Running",
      # 影像陣列遵循與資源 yaml 中相同的順序
      "images": [
        "nginx:1.27.1"
      ],
      "kind": "Deployment",
      "message": "deployment.apps/test configured",
      "name": "test",
      "namespace": "argocd",
      "status": "Synced",
      "syncPhase": "Sync",
      "version": "v1"
    },
    {
      "group": "autoscaling",
      "hookPhase": "Running",
      "kind": "HorizontalPodAutoscaler",
      "message": "horizontalpodautoscaler.autoscaling/test-hpa unchanged",
      "name": "test-hpa",
      "namespace": "argocd",
      "status": "Synced",
      "syncPhase": "Sync",
      "version": "v2"
    }
  ],
  "revision": "f3937462080c6946ff5ec4b5fa393e7c22388e4c",
  ...
}
```

我們可以利用此資訊來了解：

1. 哪些資源已變更（不適用於伺服器端套用）
2. 它們如何變更

若要了解哪些資源已變更，我們可以檢查與每個資源相關聯的訊息。那些顯示未變更的資源在同步操作期間未受影響。有了已變更資源的清單，我們可以透過查看影像陣列來了解它們如何變更。

有了這些資訊，您可以，例如：

1. 監控您正在部署的映像版本
2. 復原部署了組織內已知有問題的映像的部署
3. 偵測意外的映像變更：透過監控 webhook 負載中的影像陣列，您可以驗證是否只部署了預期的容器映像

這有助於您建立一個通知系統，讓您能夠以更進階的方式了解部署的狀態。

## 將影像清單傳送到 Slack

在此處，我們可以使用與上面類似的設定，但將接收者變更為 Slack：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
data:
  service.slack: |
    token: <your-slack-bot-token>

  template.on-deployed-template: |
    slack:
      message: |
        *部署通知*
        *應用程式：* `{{.app.metadata.name}}`
        *命名空間：* `{{.app.spec.destination.namespace}}`
        *修訂版本：* `{{.app.status.sync.revision}}`
        *已部署映像：*
          {{- range $resource := .app.status.operationState.syncResult.resources -}}
            {{- range $image := $resource.images -}}
              - "{{$image}}"
            {{- end }}
          {{- end }}
  trigger.on-deployed-trigger: |
    when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
    oncePer: app.status.sync.revision
    send: [on-deployed-template]
```

現在，透過上述設定，同步將會將影像清單傳送到您的 Slack 應用程式。如需有關與 Slack 整合的更多資訊，請參閱 [Slack 整合指南](/operator-manual/notifications/services/slack/)。

### 重複資料刪除影像

雖然 `syncResult.resources` 中的欄位僅包含使用者在 GitOps 儲存庫中宣告的資源，但您可能會根據您的設定而出現重複的影像。為了避免出現重複的影像，您需要建立一個外部 webhook 接收器來對影像進行重複資料刪除，然後再將訊息傳送到 Slack。
