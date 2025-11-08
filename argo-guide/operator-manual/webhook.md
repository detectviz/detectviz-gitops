# Git Webhook 組態

## 總覽

Argo CD 每三分鐘輪詢一次 Git 儲存庫以偵測清單的變更。為消除輪詢造成的延遲，可以將 API 伺服器設定為接收 webhook 事件。Argo CD 支援來自 GitHub、GitLab、Bitbucket、Bitbucket Server、Azure DevOps 和 Gogs 的 Git webhook 通知。以下說明如何為 GitHub 設定 Git webhook，但相同的流程應適用於其他提供商。

> [!NOTE]
> webhook 處理程式不區分分支事件和標籤事件，只要分支和標籤名稱相同。推送到分支 `x` 的 hook 事件將觸發指向具有 `targetRevision: refs/tags/x` 的相同儲存庫的應用程式的重新整理。

## 1. 在 Git 提供商中建立 WebHook

在您的 Git 提供商中，導覽至可以設定 webhook 的設定頁面。在 Git 提供商中設定的負載 URL 應使用您的 Argo CD 執行個體的 `/api/webhook` 端點（例如 `https://argocd.example.com/api/webhook`）。如果您希望使用共用密鑰，請在密鑰中輸入任意值。此值將在下一步設定 webhook 時使用。

為防止未經身份驗證的 webhook 事件的 DDoS 攻擊（`/api/webhook` 端點目前缺乏速率限制保護），建議限制負載大小。您可以透過在 `argocd-cm` ConfigMap 中設定 `webhook.maxPayloadSizeMB` 屬性來實現此目的。預設值為 50MB。

### Github

![新增 Webhook](../assets/webhook-config.png "新增 Webhook")

> [!NOTE]
> 在 GitHub 中建立 webhook 時，「內容類型」需要設定為「application/json」。用於處理 hook 的函式庫不支援預設值「application/x-www-form-urlencoded」。

### Azure DevOps

![新增 Webhook](../assets/azure-devops-webhook-config.png "新增 Webhook")

Azure DevOps 可選支援使用基本身份驗證來保護 webhook。若要使用它，請在 webhook 組態中指定使用者名稱和密碼，並在 `argocd-secret` Kubernetes secret 的 `webhook.azuredevops.username` 和 `webhook.azuredevops.password` 金鑰中設定相同的使用者名稱/密碼。

## 2. 使用 WebHook 密鑰設定 Argo CD（可選）

設定 webhook 共用密鑰是可選的，因為 Argo CD 仍會重新整理與 Git 儲存庫相關的應用程式，即使是未經身份驗證的 webhook 事件。這樣做是安全的，因為 webhook 負載的內容被視為不受信任，只會導致應用程式的重新整理（一個已經以三分鐘為間隔發生的過程）。如果 Argo CD 是公開存取的，則建議設定 webhook 密鑰以防止 DDoS 攻擊。

在 `argocd-secret` Kubernetes secret 中，使用步驟 1 中設定的 Git 提供商的 webhook 密鑰設定以下其中一個金鑰。

| 提供商 | K8s Secret 金鑰 |
|---|---|
| GitHub | `webhook.github.secret` |
| GitLab | `webhook.gitlab.secret` |
| BitBucket | `webhook.bitbucket.uuid` |
| BitBucketServer | `webhook.bitbucketserver.secret` |
| Gogs | `webhook.gogs.secret` |
| Azure DevOps | `webhook.azuredevops.username` |
| | `webhook.azuredevops.password` |

編輯 Argo CD Kubernetes secret：

```bash
kubectl edit secret argocd-secret -n argocd
```

提示：為方便輸入密鑰，Kubernetes 支援在 `stringData` 欄位中輸入密鑰，這可以省去您對值進行 base64 編碼並將其複製到 `data` 欄位的麻煩。只需將步驟 1 中建立的共用 webhook 密鑰複製到 `stringData` 欄位下對應的 GitHub/GitLab/BitBucket 金鑰即可：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
type: Opaque
data:
...

stringData:
  # github webhook secret
  webhook.github.secret: shhhh! it's a GitHub secret

  # gitlab webhook secret
  webhook.gitlab.secret: shhhh! it's a GitLab secret

  # bitbucket webhook secret
  webhook.bitbucket.uuid: your-bitbucket-uuid

  # bitbucket server webhook secret
  webhook.bitbucketserver.secret: shhhh! it's a Bitbucket server secret

  # gogs server webhook secret
  webhook.gogs.secret: shhhh! it's a gogs server secret

  # azuredevops username and password
  webhook.azuredevops.username: admin
  webhook.azuredevops.password: secret-password
```

儲存後，變更應會自動生效。

### 替代方案

如果您想將 webhook 資料儲存在**另一個** Kubernetes `Secret` 中，而不是 `argocd-secret`。ArgoCD 知道檢查您的 Kubernetes `Secret` 中 `data` 下的金鑰是否以 `$` 開頭，然後是您的 Kubernetes `Secret` 名稱和 `:`（冒號）。

語法：`$<k8s_secret_name>:<a_key_in_that_k8s_secret>`

> 注意：Secret 必須具有標籤 `app.kubernetes.io/part-of: argocd`

更多資訊請參考[使用者管理文件](user-management/index.md#alternative)中的相應部分。

## BitBucket Cloud 的特殊處理
BitBucket 不在 webhook 請求主體中包含已變更檔案的清單。
這會導致[清單路徑註解](high_availability.md#manifest-paths-annotation)功能無法與託管在 BitBucket Cloud 上的儲存庫一起使用。
BitBucket 提供了 `diffstat` API 來確定兩個提交之間的已變更檔案清單。
為了解決 webhook 中遺失的已變更檔案清單問題，Argo CD webhook 處理程式會對來源伺服器進行 API 回呼。
為防止伺服器端請求偽造 (SSRF) 攻擊，Argo CD 伺服器僅支援加密 webhook 請求的回呼機制。
傳入的 webhook 必須包含 `X-Hook-UUID` 請求標頭。必須在 `argocd-secret` 中提供對應的 UUID 作為 `webhook.bitbucket.uuid` 以供驗證。
回呼機制支援 BitBucket Cloud 上的公開和私有儲存庫。
對於公開儲存庫，Argo CD webhook 處理程式使用無身份驗證的用戶端進行 API 回呼。
對於私有儲存庫，Argo CD webhook 處理程式會搜尋 HTTP/HTTPS URL 的有效儲存庫 OAuth 權杖。
webhook 處理程式使用此 OAuth 權杖對來源伺服器進行 API 請求。
如果 Argo CD webhook 處理程式找不到相符的儲存庫憑證，則已變更檔案的清單將保持空白。
如果在回呼期間發生錯誤，已變更檔案的清單將為空。
