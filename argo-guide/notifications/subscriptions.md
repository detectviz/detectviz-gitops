Argo CD 應用程式事件的訂閱可以使用 `notifications.argojproj.io/subscribe.<trigger>.<service>: <recipient>` 註解來定義。
例如，以下註解將兩個 Slack 頻道訂閱至 Argo CD 應用程式每次成功同步的通知：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: my-channel1;my-channel2
```

註解鍵由以下部分組成：

* `on-sync-succeeded` - 觸發器名稱
* `slack` - 通知服務名稱
* `my-channel1;my-channel2` - 以分號分隔的收件人清單

您可以透過將相同的註解新增至 AppProject 資源來為 Argo CD 專案的所有應用程式建立訂閱：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: my-channel1;my-channel2
```

## 預設訂閱

訂閱可以在 `argocd-notifications-cm` ConfigMap 中使用 `subscriptions` 欄位進行全域設定。預設訂閱
會套用至所有應用程式。觸發器和應用程式可以使用
`triggers` 和 `selector` 欄位進行設定：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  # 包含集中管理的全域應用程式訂閱
  subscriptions: |
    # on-sync-status-unknown 觸發器通知的訂閱
    - recipients:
      - slack:test2
      - email:test@gmail.com
      triggers:
      - on-sync-status-unknown
    # 僅限於具有相符標籤的應用程式的訂閱
    - recipients:
      - slack:test3
      selector: test=true
      triggers:
      - on-sync-status-unknown
```

如果您想在訂閱中使用 webhook，您需要將自訂 webhook 名稱儲存在訂閱的 `recipients` 欄位中。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.webhook.<webhook-name>: |
    (snip)
  subscriptions: |
    - recipients:
      - <webhook-name>
      triggers:
      - on-sync-status-unknown
```
