# Alertmanager

## 參數

通知服務用於將事件推播至 [Alertmanager](https://github.com/prometheus/alertmanager)，需要指定以下設定：

* `targets` - alertmanager 服務位址，陣列類型
* `scheme` - 可選，預設為「http」，例如 http 或 https
* `apiPath` - 可選，預設為「/api/v2/alerts」
* `insecureSkipVerify` - 可選，預設為「false」，當 scheme 為 https 時是否跳過 ca 的驗證
* `basicAuth` - 可選，伺服器驗證
* `bearerToken` - 可選，伺服器驗證
* `timeout` - 可選，傳送警示時使用的逾時秒數，預設為「3 秒」

`basicAuth` 或 `bearerToken` 用於驗證，您可以選擇其中一種。如果兩者同時設定，`basicAuth` 優先於 `bearerToken`。

## 範例

### Prometheus Alertmanager 組態

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'
receivers:
- name: 'default'
  webhook_configs:
  - send_resolved: false
    url: 'http://10.5.39.39:10080/api/alerts/webhook'
```

您應該關閉「send_resolved」，否則在「resolve_timeout」之後您將會收到不必要的復原通知。

### 傳送一個沒有驗證的 alertmanager

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.alertmanager: |
    targets:
    - 10.5.39.39:9093
```

### 傳送具有自訂 api 路徑的 alertmanager 叢集

如果您的 alertmanager 已變更預設 api，您可以自訂「apiPath」。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.alertmanager: |
    targets:
    - 10.5.39.39:443
    scheme: https
    apiPath: /api/events
    insecureSkipVerify: true
```

### 傳送具有驗證的高可用性 alertmanager

將驗證權杖儲存在 `argocd-notifications-secret` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中使用組態。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  alertmanager-username: <username>
  alertmanager-password: <password>
  alertmanager-bearer-token: <token>
```

- 使用 basicAuth

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.alertmanager: |
    targets:
    - 10.5.39.39:19093
    - 10.5.39.39:29093
    - 10.5.39.39:39093
    scheme: https
    apiPath: /api/v2/alerts
    insecureSkipVerify: true
    basicAuth:
      username: $alertmanager-username
      password: $alertmanager-password
```

- 使用 bearerToken

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.alertmanager: |
    targets:
    - 10.5.39.39:19093
    - 10.5.39.39:29093
    - 10.5.39.39:39093
    scheme: https
    apiPath: /api/v2/alerts
    insecureSkipVerify: true
    bearerToken: $alertmanager-bearer-token
```

## 範本

* `labels` - 至少需要一對標籤，根據 alertmanager 路由實作不同的通知策略
* `annotations` - 可選，指定一組資訊標籤，可用於儲存較長的附加資訊，但僅供顯示
* `generatorURL` - 可選，預設為 '{{.app.spec.source.repoURL}}'，用於在用戶端識別造成此警示的實體的反向連結

`label` 或 `annotations` 或 `generatorURL` 的值可以範本化。

```yaml
context: |
  argocdUrl: https://example.com/argocd

template.app-deployed: |
  message: 應用程式 {{.app.metadata.name}} 已健康。
  alertmanager:
    labels:
      fault_priority: "P5"
      event_bucket: "deploy"
      event_status: "succeed"
      recipient: "{{.recipient}}"
    annotations:
      application: '<a href="{{.context.argocdUrl}}/applications/{{.app.metadata.name}}">{{.app.metadata.name}}</a>'
      author: "{{(call .repo.GetCommitMetadata .app.status.sync.revision).Author}}"
      message: "{{(call .repo.GetCommitMetadata .app.status.sync.revision).Message}}"
```

您可以根據標籤在 [Alertmanager](https://github.com/prometheus/alertmanager) 上進行針對性推播。

```yaml
template.app-deployed: |
  message: 應用程式 {{.app.metadata.name}} 已健康。
  alertmanager:
    labels:
      alertname: app-deployed
      fault_priority: "P5"
      event_bucket: "deploy"
```

有一個特殊的標籤 `alertname`。如果您沒有設定它的值，它將預設等於範本名稱。
