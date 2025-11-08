# Mattermost

## 參數

* `apiURL` - 伺服器網址，例如 https://mattermost.example.com
* `token` - 機器人權杖
* `insecureSkipVerify` - 可選布林值，true 或 false

## 組態

1. 建立一個機器人帳戶並在建立後複製權杖
![1](https://user-images.githubusercontent.com/18019529/111499520-62ed0500-8786-11eb-88b0-d0aade61fed4.png)
2. 邀請團隊
![2](https://user-images.githubusercontent.com/18019529/111500197-1229dc00-8787-11eb-98e5-587ee36c94a9.png)
3. 將權杖儲存在 `argocd-notifications-secret` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中設定 Mattermost 整合

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.mattermost: |
    apiURL: <api-url>
    token: $mattermost-token
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  mattermost-token: token
```

4. 複製頻道 ID
![4](https://user-images.githubusercontent.com/18019529/111501289-333efc80-8788-11eb-9731-8353170cd73a.png)

5. 為您的 Mattermost 整合建立訂閱

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argocroj.io/subscribe.<trigger-name>.mattermost: <channel-id>
```

## 範本

![](https://user-images.githubusercontent.com/18019529/111502636-5fa74880-8789-11eb-97c5-5eac22c00a37.png)

您可以重複使用 slack 的範本。
Mattermost 與 Slack 的附件相容。請參閱 [Mattermost 整合指南](https://docs.mattermost.com/developer/message-attachments.html)。

```yaml
template.app-deployed: |
  message: |
    應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
  mattermost:
    attachments: |
      [{
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
```
