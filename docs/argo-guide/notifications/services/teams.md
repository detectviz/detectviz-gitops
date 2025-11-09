# Teams

## 參數

Teams 通知服務使用 Teams 機器人傳送訊息通知，並需要指定以下設定：

* `recipientUrls` - webhook 網址對應，例如 `channelName: https://example.com`

## 組態

1. 開啟 `Teams` 並前往 `Apps`
2. 尋找 `Incoming Webhook` 微軟應用程式並按一下
3. 按下 `Add to a team` -> 選取團隊和頻道 -> 按下 `Set up a connector`
4. 輸入 webhook 名稱並上傳圖片（可選）
5. 按下 `Create`，然後複製 webhook 網址並將其儲存在 `argocd-notifications-secret` 中，並在 `argocd-notifications-cm` 中定義

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.teams: |
    recipientUrls:
      channelName: $channel-teams-url
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  channel-teams-url: https://example.com
```

6. 為您的 Teams 整合建立訂閱：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.teams: channelName
```

## 範本

![](https://user-images.githubusercontent.com/18019529/114271500-9d2b8880-9a4c-11eb-85c1-f6935f0431d5.png)

[通知範本](../templates.md)可以自訂以利用 teams 訊息區段、事實、主題色彩、摘要和潛在動作[功能](https://docs.microsoft.com/en-us/microsoftteams/platform/webhooks-and-connectors/how-to/connectors-using)。

```yaml
template.app-sync-succeeded: |
  teams:
    themeColor: "#000080"
    sections: |
      [{
        "facts": [
          {
            "name": "同步狀態",
            "value": "{{.app.status.sync.status}}"
          },
          {
            "name": "儲存庫",
            "value": "{{.app.spec.source.repoURL}}"
          }
        ]
      }]
    potentialAction: |-
      [{
        "@type":"OpenUri",
        "name":"作業詳細資料",
        "targets":[{
          "os":"default",
          "uri":"{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
        }]
      }]
    title: 應用程式 {{.app.metadata.name}} 已成功同步
    text: 應用程式 {{.app.metadata.name}} 已於 {{.app.status.operationState.finishedAt}} 成功同步。
    summary: "{{.app.metadata.name}} 同步成功"
```

### 事實欄位

您可以使用 `facts` 欄位來取代 `sections` 欄位。

```yaml
template.app-sync-succeeded: |
  teams:
    facts: |
      [{
        "name": "同步狀態",
        "value": "{{.app.status.sync.status}}"
      },
      {
        "name": "儲存庫",
        "value": "{{.app.spec.source.repoURL}}"
      }]
```

### 主題色彩欄位

您可以為訊息設定十六進位字串的主題色彩。

![](https://user-images.githubusercontent.com/1164159/114864810-0718a900-9e24-11eb-8127-8d95da9544c1.png)

```yaml
template.app-sync-succeeded: |
  teams:
    themeColor: "#000080"
```

### 摘要欄位

您可以設定將顯示在「通知與活動摘要」中的訊息摘要

![](https://user-images.githubusercontent.com/6957724/116587921-84c4d480-a94d-11eb-9da4-f365151a12e7.jpg)

![](https://user-images.githubusercontent.com/6957724/116588002-99a16800-a94d-11eb-807f-8626eb53b980.jpg)

```yaml
template.app-sync-succeeded: |
  teams:
    summary: "同步成功"
```
