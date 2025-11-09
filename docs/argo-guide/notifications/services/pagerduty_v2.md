# PagerDuty V2

## 參數

PagerDuty 通知服務用於觸發 PagerDuty 事件，並需要指定以下設定：

* `serviceKeys` - 一個具有以下結構的字典：
  * `service-name: $pagerduty-key-service-name` 其中 `service-name` 是您要用於產生事件的服務名稱，而 `$pagerduty-key-service-name` 是對包含實際 PagerDuty 整合金鑰（Events API v2 整合）的密鑰的參考

如果您希望多個 Argo 應用程式觸發事件到其各自的 PagerDuty 服務，請在您要設定警示的每個服務中建立一個整合金鑰。

若要建立 PagerDuty 整合金鑰，請[遵循這些說明](https://support.pagerduty.com/docs/services-and-integrations#create-a-generic-events-api-integration)將 Events API v2 整合新增到您選擇的服務中。

## 組態

以下片段包含範例 PagerDuty 服務組態。它假設您要警示的服務稱為 `my-service`。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  pagerduty-key-my-service: <pd-integration-key>
```

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.pagerdutyv2: |
    serviceKeys:
      my-service: $pagerduty-key-my-service
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
    pagerdutyv2:
      summary: "Rollout {{.rollout.metadata.name}} 已中止。"
      severity: "critical"
      source: "{{.rollout.metadata.name}}"
```

範本中 PagerDuty 組態的參數通常與 Events API v2 端點的負載相符。所有參數都是字串。

* `summary` - (必要) 事件的簡短文字摘要，用於產生任何相關警示的摘要/標題。
* `severity` - (必要) 事件描述的狀態對受影響系統的感知嚴重性。允許的值：`critical`、`warning`、`error`、`info`
* `source` - (必要) 受影響系統的唯一位置，最好是主機名稱或 FQDN。
* `component` - 負責事件的來源機器的元件。
* `group` - 服務元件的邏輯分組。
* `class` - 事件的類別/類型。
* `url` - 應用於 PagerDuty 中「在 ArgoCD 中檢視」連結的 URL。

目前不支援 `timestamp` 和 `custom_details` 參數。

## 註釋

PagerDuty 通知的註釋範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-rollout-aborted.pagerdutyv2: "<PagerDuty 的 serviceID>"
```
