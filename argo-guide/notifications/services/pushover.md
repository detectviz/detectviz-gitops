# Pushover

1. 在 [pushover.net](https://pushover.net/apps/build) 建立一個應用程式。
2. 將 API 金鑰儲存在 `<secret-name>` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中定義 secret 名稱：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.pushover: |
    token: $pushover-token
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  pushover-token: avtc41pn13asmra6zaiyf7dh6cgx97
```

3. 將您的使用者金鑰新增到您的應用程式資源中：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-sync-succeeded.pushover: uumy8u4owy7bgkapp6mc5mvhfsvpcd
```
