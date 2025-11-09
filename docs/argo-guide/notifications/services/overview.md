通知服務代表與 slack、電子郵件或自訂 webhook 等服務的整合。服務在 `argocd-notifications-cm` ConfigMap 中使用 `service.<type>.(<custom-name>)` 鍵進行設定，並可能參考 `argocd-notifications-secret` Secret 中的敏感資料。以下範例示範了 slack 服務的設定：

```yaml
  service.slack: |
    token: $slack-token
```


`slack` 表示服務傳送 slack 通知；名稱遺失，預設為 `slack`。

## 敏感資料

敏感資料（例如驗證權杖）應儲存在 `<secret-name>` Secret 中，並可以在服務設定中使用 `$<secret-key>` 格式進行參考。例如，`$slack-token` 參考 `<secret-name>` Secret 中 `slack-token` 鍵的值。

## 自訂名稱

服務自訂名稱允許設定相同服務類型的兩個執行個體。

```yaml
  service.slack.workspace1: |
    token: $slack-token-workspace1
  service.slack.workspace2: |
    token: $slack-token-workspace2
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.workspace1: my-channel
    notifications.argoj.io/subscribe.on-sync-succeeded.workspace2: my-channel
```

## 服務類型

* [AwsSqs](./awssqs.md)
* [電子郵件](./email.md)
* [GitHub](./github.md)
* [Slack](./slack.md)
* [Mattermost](./mattermost.md)
* [Opsgenie](./opsgenie.md)
* [Grafana](./grafana.md)
* [Webhook](./webhook.md)
* [Telegram](./telegram.md)
* [Teams](./teams.md)
* [Google Chat](./googlechat.md)
* [Rocket.Chat](./rocketchat.md)
* [Pushover](./pushover.md)
* [Alertmanager](./alertmanager.md)
