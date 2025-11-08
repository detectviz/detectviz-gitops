# NewRelic

## 參數

* `apiURL` - api 伺服器網址，例如 https://api.newrelic.com
* `apiKey` - 一個 [NewRelic ApiKey](https://docs.newrelic.com/docs/apis/rest-api-v2/get-started/introduction-new-relic-rest-api-v2/#api_key)

## 組態

1. 建立一個 NewRelic [Api 金鑰](https://docs.newrelic.com/docs/apis/intro-apis/new-relic-api-keys/#user-api-key)
2. 將 apiKey 儲存在 `argocd-notifications-secret` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中設定 NewRelic 整合

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.newrelic: |
    apiURL: <api-url>
    apiKey: $newrelic-apiKey
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  newrelic-apiKey: apiKey
```

3. 複製[應用程式 ID](https://docs.newrelic.com/docs/apis/rest-api-v2/get-started/get-app-other-ids-new-relic-one/#apm)
4. 為您的 NewRelic 整合建立訂閱

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.<trigger-name>.newrelic: <app-id>
```

## 範本

* `description` - **可選**，此部署的高階描述，可在[摘要](https://docs.newrelic.com/docs/apm/applications-menu/monitoring/apm-overview-page)頁面和[部署](https://docs.newrelic.com/docs/apm/applications-menu/events/deployments-page)頁面（當您選取個別部署時）中看到。
  * 預設為 `message`
* `changelog` - **可選**，此部署中變更的摘要，可在[部署](https://docs.newrelic.com/docs/apm/applications-menu/events/deployments-page)頁面（當您選取（選取的部署）> 變更記錄）中看到。
  * 預設為 `{{(call .repo.GetCommitMetadata .app.status.sync.revision).Message}}`
* `user` - **可選**，與部署關聯的使用者名稱，可在[摘要](https://docs.newrelic.com/docs/apm/applications-menu/events/deployments-page)和[部署](https://docs.newrelic.com/docs/apm/applications-menu/events/deployments-page)頁面中看到。
  * 預設為 `{{(call .repo.GetCommitMetadata .app.status.sync.revision).Author}}`

```yaml
context: |
  argocdUrl: https://example.com/argocd

template.app-deployed: |
  message: 應用程式 {{.app.metadata.name}} 已成功部署。
  newrelic:
    description: 應用程式 {{.app.metadata.name}} 已成功部署
```
