# Webhook

webhook 通知服務允許使用範本化的請求主體和 URL 傳送通用的 HTTP 請求。
使用 Webhook，您可以觸發 Jenkins 工作、更新 GitHub 提交狀態。

## 參數

Webhook 通知服務組態包含以下設定：

- `url` - 要傳送 webhook 的 url
- `headers` - 可選，與 webhook 一起傳遞的標頭
- `basicAuth` - 可選，與 webhook 一起傳遞的基本驗證
- `insecureSkipVerify` - 可選布林值，true 或 false
- `retryWaitMin` - 可選，重試之間的最小等待時間。預設值：1s。
- `retryWaitMax` - 可選，重試之間的最大等待時間。預設值：5s。
- `retryMax` - 可選，最大重試次數。預設值：3。

## 重試行為

如果請求因網路錯誤而失敗，或者伺服器傳回 5xx 狀態碼，webhook 服務將自動重試請求。可以使用 `retryMax`、`retryWaitMin` 和 `retryWaitMax` 參數來設定重試次數和重試之間的等待時間。

重試之間的等待時間介於 `retryWaitMin` 和 `retryWaitMax` 之間。如果所有重試都失敗，`Send` 方法將傳回錯誤。

## 組態

使用以下步驟設定 webhook：

1 在 `argocd-notifications-cm` ConfigMap 中註冊 webhook：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.<webhook-name>: |
    url: https://<hostname>/<optional-path>
    headers: #optional headers
    - name: <header-name>
      value: <header-value>
    basicAuth: #optional username password
      username: <username>
      password: <api-key>
    insecureSkipVerify: true #optional bool
```

2 定義範本以自訂 webhook 請求方法、路徑和主體：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.github-commit-status: |
    webhook:
      <webhook-name>:
        method: POST # one of: GET, POST, PUT, PATCH. Default value: GET
        path: <optional-path-template>
        body: |
          <optional-body-template>
  trigger.<trigger-name>: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [github-commit-status]
```

3 為 webhook 整合建立訂閱：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.<trigger-name>.<webhook-name>: ""
```

## 範例

### 設定 GitHub 提交狀態

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.github: |
    url: https://api.github.com
    headers: #optional headers
    - name: Authorization
      value: token $github-token
```

2 定義範本以自訂 webhook 請求方法、路徑和主體：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.github: |
    url: https://api.github.com
    headers: #optional headers
    - name: Authorization
      value: token $github-token

  template.github-commit-status: |
    webhook:
      github:
        method: POST
        path: /repos/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL}}/statuses/{{.app.status.operationState.operation.sync.revision}}
        body: |
          {
            {{if eq .app.status.operationState.phase "Running"}} "state": "pending"{{end}}
            {{if eq .app.status.operationState.phase "Succeeded"}} "state": "success"{{end}}
            {{if eq .app.status.operationState.phase "Error"}} "state": "error"{{end}}
            {{if eq .app.status.operationState.phase "Failed"}} "state": "error"{{end}},
            "description": "ArgoCD",
            "target_url": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
            "context": "continuous-delivery/{{.app.metadata.name}}"
          }
```

### 啟動 Jenkins 工作

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.jenkins: |
    url: http://<jenkins-host>/job/<job-name>/build?token=<job-secret>
    basicAuth:
      username: <username>
      password: <api-key>

type: Opaque
```

### 傳送 form-data

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.form: |
    url: https://form.example.com
    headers:
    - name: Content-Type
      value: application/x-www-form-urlencoded

  template.form-data: |
    webhook:
      form:
        method: POST
        body: key1=value1&key2=value2
```

### 傳送 Slack

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.slack_webhook: |
    url: https://hooks.slack.com/services/xxxxx
    headers:
    - name: Content-Type
      value: application/json

  template.send-slack: |
    webhook:
      slack_webhook:
        method: POST
        body: |
          {
            "attachments": [{
              "title": "{{.app.metadata.name}}",
              "title_link": "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}",
              "color": "#18be52",
              "fields": [{
                "title": "同步狀態",
                "value": "{{.app.status.sync.status}}",
                "short": true
              }, {
                "title": "儲存庫",
                "value": "{{.app.spec.source.repoURL}}",
                "short": true
              }]
            }]
          }
```
