# PagerDuty

## 參數

PagerDuty 通知服務用於建立 PagerDuty 事件，並需要指定以下設定：

* `pagerdutyToken` - PagerDuty 驗證權杖
* `from` - 與發出請求的帳戶相關聯的有效使用者的電子郵件地址。
* `serviceID` - 資源的 ID。


## 範例

以下片段包含範例 PagerDuty 服務組態：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  pagerdutyToken: <pd-api-token>
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.pagerduty: |
    token: $pagerdutyToken
    from: <emailid>
```

## 範本

[通知範本](../templates.md)支援為 PagerDuty 通知指定主旨：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.rollout-aborted: |
    message: Rollout {{.rollout.metadata.name}} 已中止。
    pagerduty:
      title: "Rollout {{.rollout.metadata.name}}"
      urgency: "high"
      body: "Rollout {{.rollout.metadata.name}} 已中止 "
      priorityID: "<事件的 priorityID>"
```

注意：優先順序是一個標籤，代表事件的重要性和影響。這僅適用於 pagerduty 的標準和企業方案。

## 註釋

pagerduty 通知的註釋範例：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-rollout-aborted.pagerduty: "<PagerDuty 的 serviceID>"
```
