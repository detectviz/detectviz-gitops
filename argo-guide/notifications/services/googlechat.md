# Google Chat

## 參數

Google Chat 通知服務會將訊息通知傳送到 Google Chat webhook。此服務使用以下設定：

* `webhooks` - 格式為 `webhookName: webhookUrl` 的對應

## 組態

1. 開啟 `Google chat` 並前往您要傳送訊息的聊天室
2. 從頁面頂端的選單中，選取**設定 Webhooks**
3. 在**傳入 Webhooks** 下，按一下**新增 Webhook**
4. 為 webhook 命名，可選擇新增圖片，然後按一下**儲存**
5. 複製 webhook 旁的 URL
6. 將 URL 儲存在 `argocd-notification-secret` 中，並在 `argocd-notifications-cm` 中宣告

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.googlechat: |
    webhooks:
      spaceName: $space-webhook-url
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  space-webhook-url: https://chat.googleapis.com/v1/spaces/<space_id>/messages?key=<key>&token=<token>
```

6. 為您的聊天室建立訂閱

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argocroj.io/subscribe.on-sync-succeeded.googlechat: spaceName
```

## 範本

您可以將[純文字](https://developers.google.com/chat/reference/message-formats/basic)或[卡片訊息](https://developers.google.com/chat/reference/message-formats/cards)傳送到 Google Chat 聊天室。純文字訊息範本可以定義如下：

```yaml
template.app-sync-succeeded: |
  message: 應用程式 {{ .app.metadata.name }} 已成功同步！
```

卡片訊息可以定義如下：

```yaml
template.app-sync-succeeded: |
  googlechat:
    cardsV2: |
      - header:
          title: ArgoCD Bot 通知
        sections:
          - widgets:
              - decoratedText:
                  text: 應用程式 {{ .app.metadata.name }} 已成功同步！
          - widgets:
              - decoratedText:
                  topLabel: 儲存庫
                  text: {{ call .repo.RepoURLToHTTPS .app.spec.source.repoURL }}
              - decoratedText:
                  topLabel: 修訂版本
                  text: {{ .app.spec.source.targetRevision }}
              - decoratedText:
                  topLabel: 作者
                  text: {{ (call .repo.GetCommitMetadata .app.status.sync.revision).Author }}
```
所有 [Card 欄位](https://developers.google.com/chat/api/reference/rest/v1/cards#Card_1)都受支援，可用於
通知。也可以使用先前的（現已棄用）`cards` 鍵來使用舊版的卡片欄位，
但這不建議，因為 Google 已棄用此欄位，並建議使用較新的 `cardsV2`。

卡片訊息也可以用 JSON 撰寫。

## 聊天串

可以透過指定聊天串的唯一金鑰，在聊天串中同時傳送純文字和卡片訊息。聊天串金鑰可以定義如下：

```yaml
template.app-sync-succeeded: |
  message: 應用程式 {{ .app.metadata.name }} 已成功同步！
  googlechat:
    threadKey: {{ .app.metadata.name }}
```
