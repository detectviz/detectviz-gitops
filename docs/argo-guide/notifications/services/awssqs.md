# AWS SQS

## 參數

此通知服務能夠將簡單的訊息傳送到 AWS SQS 佇列。

* `queue` - 您要傳送訊息的佇列名稱。可以使用目標目的地註釋來覆寫。
* `region` - sqs 佇列的區域可以透過環境變數 `AWS_DEFAULT_REGION` 提供。
* `key` - 可選，aws 存取金鑰必須透過變數從密鑰中參考，或透過環境變數 `AWS_ACCESS_KEY_ID` 參考。
* `secret` - 可選，aws 存取密鑰必須透過變數從密鑰中參考，或透過環境變數 `AWS_SECRET_ACCESS_KEY` 參考。
* `account` - 可選，佇列的外部帳戶 ID。
* `endpointUrl` - 可選，對於使用 localstack 進行開發很有用。

## 範例

### 使用密鑰進行憑證擷取：

資源註釋：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  annotations:
    notifications.argoproj.io/subscribe.on-deployment-ready.awssqs: "overwrite-myqueue"
```

* ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.awssqs: |
    region: "us-east-2"
    queue: "myqueue"
    account: "1234567"
    key: "$awsaccess_key"
    secret: "$awsaccess_secret"

  template.deployment-ready: |
    message: |
      Deployment {{.obj.metadata.name}} is ready!

  trigger.on-deployment-ready: |
    - when: any(obj.status.conditions, {.type == 'Available' && .status == 'True'})
      send: [deployment-ready]
    - oncePer: obj.metadata.annotations["generation"]

```
 Secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  awsaccess_key: test
  awsaccess_secret: test
```


### 使用 AWS 環境變數的最小組態

確保透過 OIDC 或其他方法注入以下環境變數清單。並假設 SQS 是帳戶本地的。
您可以跳過對敏感資料使用密鑰，並省略其他參數。（透過 ConfigMap 設定參數優先。）

變數：

```bash
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="us-east-1"
```

資源註釋：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  annotations:
    notifications.argoproj.io/subscribe.on-deployment-ready.awssqs: ""
```

* ConfigMap
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.awssqs: |
    queue: "myqueue"

  template.deployment-ready: |
    message: |
      Deployment {{.obj.metadata.name}} is ready!

  trigger.on-deployment-ready: |
    - when: any(obj.status.conditions, {.type == 'Available' && .status == 'True'})
      send: [deployment-ready]
    - oncePer: obj.metadata.annotations["generation"]

```

## FIFO SQS 佇列

FIFO 佇列要求每則訊息都必須 همراه [MessageGroupId](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_SendMessage.html#SQS-SendMessage-request-MessageGroupId) 一起傳送，每則具有相符 MessageGroupId 的訊息都會依序逐一處理。

若要傳送到 FIFO SQS 佇列，您必須在範本中包含 `messageGroupId`，如下例所示：

```yaml
template.deployment-ready: |
  message: |
    Deployment {{.obj.metadata.name}} is ready!
  messageGroupId: {{.obj.metadata.name}}-deployment
```
