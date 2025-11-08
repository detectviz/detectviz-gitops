# Opsgenie

若要能夠使用 argocd-notifications 傳送通知，您必須在您的 [Opsgenie 團隊](https://docs.opsgenie.com/docs/teams)中建立一個 [API 整合](https://docs.opsgenie.com/docs/integrations-overview)。

1. 在 https://app.opsgenie.com 或 https://app.eu.opsgenie.com（如果您在歐盟有帳戶）登入 Opsgenie。
2. 請確保您已經有一個團隊；如果沒有，請遵循此指南：https://docs.opsgenie.com/docs/teams。
3. 按一下左側選單中的「團隊」。
4. 選取您要通知的團隊。
5. 在團隊的組態選單中，選取「整合」。
6. 按一下右上角的「新增整合」。
7. 選取「API」整合。
8. 為您的整合命名，複製「API 金鑰」，並將其儲存以備後用。
9. 在整合設定中按一下「編輯」。
10. 請確保選取「建立和更新存取權」核取方塊；停用其他核取方塊以移除不必要的權限。
11. 按一下底部的「儲存」。
12. 按一下右上角的「開啟整合」。
13. 檢查您的瀏覽器以取得正確的伺服器 apiURL。如果是「app.opsgenie.com」，則使用美國/國際 API URL `api.opsgenie.com`；否則，請使用 `api.eu.opsgenie.com`（歐洲 API）。
14. 您已完成設定 Opsgenie。現在您需要設定 argocd-notifications。使用 apiUrl、團隊名稱和 apiKey 在 `argocd-notifications-secret` secret 中設定 Opsgenie 整合。
15. 您可以在下方找到範例 `argocd-notifications-cm` 組態。

| **選項** | **必要** | **類型** | **說明** | **範例** |
| ------------- | ------------ | -------- | -------------------------------------------------------------------------------------------------------- | -------------------------------- |
| `description` | True | `string` | 警示的描述欄位，通常用於提供有關警示的詳細資訊。 | `來自 Argo CD 的問候！` |
| `priority` | False | `string` | 警示的優先順序。可能的值為 P1、P2、P3、P4 和 P5。預設值為 P3。 | `P1` |
| `alias` | False | `string` | 警示的用戶端定義識別碼，也是警示重複資料刪除的關鍵元素。 | `人生苦短，別名不能少` |
| `note` | False | `string` | 建立警示時將新增的額外註解。 | `來自 Argo CD 的錯誤！` |
| `actions` | False | `[]string` | 警示可用的自訂動作。 | `["解決", "升級"]` |
| `tags` | False | `[]string` | 警示的標籤。 | `["critical", "deployment"]` |
| `visibleTo` | False | `[]alert.Responder` | 警示將對其可見的團隊和使用者，而無需傳送任何通知。每個項目的 `type` 欄位是必要的，其中可能的值為 `team` 和 `user`。除了 `type` 欄位之外，還應為團隊提供 `id` 或 `name`，並為使用者提供 `id` 或 `username`。請注意，警示預設將對 `responders` 欄位中指定的團隊可見，因此無需在 `visibleTo` 欄位中重新指定它們。 | `[{Type: "team", Id: "team_id"}, {Type: "user", Id: "user_id"}]` |
| `details` | False | `map[string]string` | 用作警示自訂屬性的鍵值對對應。 | `{"environment": "production", "service": "web"}` |
| `entity` | False | `string` | 警示的實體欄位，通常用於指定警示與哪個網域相關。 | `web-server` |
| `user` | False | `string` | 請求擁有者的顯示名稱。 | `admin_user` |

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.opsgenie: |
    apiUrl: <api-url>
    apiKeys:
      <your-team>: <integration-api-key>
  template.opsgenie: |
    message: |
      [Argo CD] 應用程式 {{.app.metadata.name}} 有問題。
    opsgenie:
      description: |
        應用程式：{{.app.metadata.name}}
        健康狀態：{{.app.status.health.status}}
        操作狀態階段：{{.app.status.operationState.phase}}
        同步狀態：{{.app.status.sync.status}}
      priority: P1
      alias: {{.app.metadata.name}}
      note: 來自 Argo CD 的錯誤！
      actions:
        - 重新啟動
        - 一個範例動作
      tags:
        - 覆寫安靜時間
        - 嚴重
      visibleTo:
        - Id: "{{.app.metadata.responderId}}"
          Type: "team"
        - Name: "rocket_team"
          Type: "team"
        - Id: "{{.app.metadata.responderUserId}}"
          Type: "user"
        - Username: "trinity@opsgenie.com"
          Type: "user"
      details:
        environment: production
        service: web
      entity: Argo CD 應用程式
      user: John Doe
  trigger.on-a-problem: |
    - description: 應用程式有問題。
      send:
      - opsgenie
      when: app.status.health.status == 'Degraded' or app.status.operationState.phase in ['Error', 'Failed'] or app.status.sync.status == 'Unknown'
```

16. 在應用程式 YAML 檔案中新增註釋，以啟用特定 Argo CD 應用程式的通知。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoj.io/subscribe.on-a-problem.opsgenie: <your-team>
```
