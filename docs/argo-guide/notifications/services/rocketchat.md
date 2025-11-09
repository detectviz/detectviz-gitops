# Rocket.Chat

## 參數

Rocket.Chat 通知服務組態包含以下設定：

* `email` - Rocker.Chat 使用者的 SAMAccountName
* `password` - Rocker.Chat 使用者的密碼
* `alias` - 可選，應用於發布訊息的別名
* `icon` - 可選的訊息圖示
* `avatar` - 可選的訊息頭像
* `serverUrl` - 可選的 Rocket.Chat 伺服器網址

## 組態

1. 登入您的 RocketChat 執行個體
2. 前往使用者管理

![2](https://user-images.githubusercontent.com/15252187/115824993-7ccad900-a411-11eb-89de-6a0c4438ffdf.png)

3. 新增一個具有 `bot` 角色的新使用者。另請注意，`需要變更密碼` 核取方塊必須取消勾選

![3](https://user-images.githubusercontent.com/15252187/115825174-b4d21c00-a411-11eb-8f20-cda48cea9fad.png)

4. 複製您為機器人使用者建立的使用者名稱和密碼
5. 建立一個公開或私有頻道，或一個團隊，在此範例中為 `my_channel`
6. 將您的機器人新增到此頻道 **否則將無法運作**
7. 將電子郵件和密碼儲存在 argocd-notifications-secret Secret 中

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  rocketchat-email: <email>
  rocketchat-password: <password>
```

8. 最後，使用這些憑證在 `argocd-configmap` 組態對應中設定 RocketChat 整合：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.rocketchat: |
    email: $rocketchat-email
    password: $rocketchat-password
```

9. 為您的 Rocket.Chat 整合建立一個訂閱：

*注意：頻道、團隊或使用者必須以 # 或 @ 為前綴，否則我們將會將目的地解釋為房間 ID*

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.rocketchat: #my_channel
```

## 範本

[通知範本](../templates.md)可以使用 RocketChat [附件](https://developer.rocket.chat/api/rest-api/methods/chat/postmessage#attachments-detail)進行自訂。

*注意：Rocketchat 中的附件結構與 Slack 附件[功能](https://api.slack.com/messaging/composing/layouts)相同。*

<!-- TODO: @sergeyshevch 需要新增 RocketChat 附件的螢幕截圖 -->

訊息附件可以在 `rocketchat` 欄位下的 `attachments` 字串欄位中指定：

```yaml
template.app-sync-status: |
  message: |
    應用程式 {{.app.metadata.name}} 的同步狀態為 {{.app.status.sync.status}}。
    應用程式詳細資訊：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}。
  rocketchat:
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
