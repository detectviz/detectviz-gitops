# Telegram

1. 使用 [@Botfather](https://t.me/Botfather) 取得 API 權杖。
2. 將權杖儲存在 `<secret-name>` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中設定 telegram 整合：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.telegram: |
    token: $telegram-token
```

3. 建立新的 Telegram [頻道](https://telegram.org/blog/channels)。
4. 將您的機器人新增為管理員。
5. 在您的 Telegram 整合的訂閱中使用此頻道的 `username`（公開頻道）或 `chatID`（私有頻道）：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.telegram: username
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.telegram: -1000000000000
```

如果您的私人聊天包含討論串，您可以選擇性地使用 `|` 分隔來指定討論串 ID：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.telegram: -1000000000000|2
```
