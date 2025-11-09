# 通知概觀

Argo CD 通知會持續監控 Argo CD 應用程式，並提供一種靈活的方式來通知
使用者有關應用程式狀態的重要變更。使用靈活的
[觸發器](triggers.md) 和 [範本](templates.md) 機制，您可以設定何時應傳送通知
以及通知的內容。Argo CD 通知包含一個實用的觸發器和範本 [目錄](catalog.md)。
因此，您可以直接使用它們，而無需重新發明新的。

## 入門指南

* 從目錄安裝觸發器和範本

    ```bash
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
    ```

* 將電子郵件使用者名稱和密碼權杖新增至 `argocd-notifications-secret` 密碼

    ```bash
    EMAIL_USER=<your-username>
    PASSWORD=<your-password>

    kubectl apply -n argocd -f - << EOF
    apiVersion: v1
    kind: Secret
    metadata:
      name: argocd-notifications-secret
    stringData:
      email-username: $EMAIL_USER
      email-password: $PASSWORD
    type: Opaque
    EOF
    ```

* 註冊電子郵件通知服務

    ```bash
    kubectl patch cm argocd-notifications-cm -n argocd --type merge -p '{"data": {"service.email.gmail": "{ username: $email-username, password: $email-password, host: smtp.gmail.com, port: 465, from: $email-username }" }}'
    ```

* 透過將 `notifications.argoproj.io/subscribe.on-sync-succeeded.slack` 註釋新增至 Argo CD 應用程式或專案來訂閱通知：

    ```bash
    kubectl patch app <my-app> -n argocd -p '{"metadata": {"annotations": {"notifications.argoproj.io/subscribe.on-sync-succeeded.slack":"<my-channel>"}}}' --type merge
    ```

嘗試同步一個應用程式，以便在同步完成時收到通知。

## 基於命名空間的設定

Argo CD 通知的常見安裝方法是將其安裝在專用命名空間中以管理整個叢集。在這種情況下，管理員是唯一
可以在該命名空間中一般性地設定通知的人。但是，在某些情況下，需要允許終端使用者為其 Argo CD 應用程式設定通知
。例如，終端使用者可以在他們有權存取且其 Argo CD 應用程式正在執行的命名空間中為其 Argo CD 應用程式設定通知
。

此功能基於任何命名空間中的應用程式。有關更多資訊，請參閱 [任何命名空間中的應用程式](../app-any-namespace.md) 頁面。

為了啟用此功能，Argo CD 管理員必須重新設定 argocd-notification-controller 工作負載，以將 `--application-namespaces` 和 `--self-service-notification-enabled` 參數新增至容器的啟動命令。
`--application-namespaces` 控制 Argo CD 應用程式所在的命名空間清單。`--self-service-notification-enabled` 開啟此功能。

這兩個的啟動參數也可以透過在 argocd-cmd-params-cm ConfigMap 中指定
`application.namespaces` 和 `notificationscontroller.selfservice.enabled` 來方便地設定並保持同步，而不是變更相應工作負載的資訊清單。例如：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  application.namespaces: app-team-one, app-team-two
  notificationscontroller.selfservice.enabled: "true"
```

要使用此功能，您可以在 Argo CD 應用程式所在的命名空間中部署名為 `argocd-notifications-cm` 的 configmap 和可能名為 `argocd-notifications-secret` 的密碼。

當以這種方式設定時，控制器將使用控制器級別的設定（位於與控制器相同的命名空間中的 configmap）以及
位於與 Argo CD 應用程式相同的命名空間中的設定來傳送通知。

範例：應用程式團隊希望在使用 PagerDutyV2 時收到通知，而控制器級別的設定僅支援 Slack。

以下兩個資源部署在 Argo CD 應用程式所在的命名空間中。
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.pagerdutyv2: |
    serviceKeys:
      my-service: $pagerduty-key-my-service
...
```
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
type: Opaque
data:
  pagerduty-key-my-service: <pd-integration-key>
```

當 Argo CD 應用程式具有以下訂閱時，使用者會從 PagerDuty 收到應用程式同步失敗訊息。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.pagerdutyv2: "<serviceID for Pagerduty>"
```

> [!NOTE]
> 當在控制器級別設定和應用程式級別設定中定義了相同的通知服務和觸發器時，
> 將根據其各自的設定傳送兩個通知。

當 `--self-service-notification-enable` 旗標開啟時，[在通知範本中定義和使用密碼](templates.md#defining-and-using-secrets-within-notification-templates) 功能不可用。
