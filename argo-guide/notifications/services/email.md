# 電子郵件

## 參數

電子郵件通知服務使用 SMTP 協定傳送電子郵件通知，並需要指定以下設定：

* `host` - SMTP 伺服器主機名稱
* `port` - SMTP 伺服器連接埠
* `username` - 使用者名稱
* `password` - 密碼
* `from` - 寄件者電子郵件地址
* `html` - 可選布林值，true 或 false
* `insecure_skip_verify` - 可選布林值，true 或 false

## 範例

以下片段包含範例 Gmail 服務組態：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.email.gmail: |
    username: $email-username
    password: $email-password
    host: smtp.gmail.com
    port: 465
    from: $email-username
```

無驗證：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.email.example: |
    host: smtp.example.com
    port: 587
    from: $email-username
```

## 範本

[通知範本](../templates.md)支援為電子郵件通知指定主旨：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.app-sync-succeeded: |
    email:
      subject: 應用程式 {{.app.metadata.name}} 已成功同步。
    message: |
      {{if eq .serviceType "slack"}}:white_check_mark:{{end}} 應用程式 {{.app.metadata.name}} 已於 {{.app.status.operationState.finishedAt}} 成功同步。
      同步作業詳細資料可在以下網址取得：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true 。
```
