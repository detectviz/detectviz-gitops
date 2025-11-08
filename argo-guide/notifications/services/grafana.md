# Grafana

若要能夠使用 argocd-notifications 建立 Grafana 註釋，您必須在您的 [Grafana](https://grafana.com) 中建立一個 [API 金鑰](https://grafana.com/docs/grafana/latest/http_api/auth/#create-api-key)。

![範例](https://user-images.githubusercontent.com/18019529/112024976-0f106080-8b78-11eb-9658-7663305899be.png)

可用參數：

* `apiURL` - 伺服器網址，例如 https://grafana.example.com
* `apiKey` - 服務帳戶的 API 金鑰
* `insecureSkipVerify` - 可選布林值，true 或 false

1. 以 `admin` 身分登入您的 Grafana 執行個體
2. 在左側選單中，前往「組態」/「API 金鑰」
3. 按一下「新增 API 金鑰」
4. 使用名稱 `ArgoCD Notification`、角色 `Editor` 和存留時間 `10y`（例如）填寫金鑰
5. 按一下「新增」按鈕
6. 將 apiKey 儲存在 `argocd-notifications-secret` Secret 中，並複製您的 API 金鑰，然後在 `argocd-notifications-cm` ConfigMap 中定義它

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.grafana: |
    apiUrl: https://grafana.example.com/api
    apiKey: $grafana-api-key
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  grafana-api-key: api-key
```

7. 在 `argo-notifications-cm` Configmap 中建立一個範本
這將用於將註釋的（必要）文字傳遞給 Grafana（或重複使用現有的）
由於沒有針對 Grafana 的特定範本，您必須使用通用的 `message`：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  templates:
    template.app-deployed: |
      messsage: 應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
```

8. 為您的 Grafana 整合建立訂閱

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.<trigger-name>.grafana: tag1|tag2 # 以 | 分隔的標籤清單
```

9. 變更註釋設定
![8](https://user-images.githubusercontent.com/18019529/112022083-47fb0600-8b75-11eb-849b-d25d41925909.png)
