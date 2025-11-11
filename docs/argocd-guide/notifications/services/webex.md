# Webex Teams

## 參數

Webex Teams 通知服務組態包含以下設定：

* `token` - 應用程式權杖

## 組態

1. 建立一個 Webex [機器人](https://developer.webex.com/docs/bots)
1. 複製機器人存取[權杖](https://developer.webex.com/my-apps)並將其儲存在 `argocd-notifications-secret` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中設定 Webex Teams 整合

    ``` yaml
    apiVersion: v1
    kind: Secret
    metadata:
    name: <secret-name>
    stringData:
    webex-token: <bot access token>
    ```

    ``` yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
    name: argocd-notifications-cm
    data:
    service.webex: |
        token: $webex-token
    ```

1. 為您的 Webex Teams 整合建立訂閱

    ``` yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
    annotations:
        notifications.argoj.io/subscribe.<trigger-name>.webex: <個人電子郵件或房間 ID>
    ```
