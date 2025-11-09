# Okta

> [!NOTE]
> **您正在使用這個 IdP 嗎？請貢獻！**
>
> 如果您正在使用這個 IdP，請考慮為本文件[貢獻](../../developer-guide/docs-site.md)。

已透過至少兩種方法成功實現使用 Okta 的單一登入設定：

* [SAML (搭配 Dex)](#saml-with-dex)
* [OIDC (不搭配 Dex)](#oidc-without-dex)

## SAML (搭配 Dex)

> [!NOTE]
> **Okta 應用程式群組指派**
>
> Okta 應用程式的 **群組屬性陳述式** regex 稍後將用於將 Okta 群組對應至 Argo CD RBAC 角色。

1. 在 Okta UI 中建立一個新的 SAML 應用程式。
    * ![Okta SAML App 1](../../assets/saml-1.png)
        我已停用 `應用程式可見性`，因為 Dex 不支援提供者起始的登入流程。
    * ![Okta SAML App 2](../../assets/saml-2.png)
1. 在 Okta 中建立應用程式後，按一下 `檢視設定說明`。
    * ![Okta SAML App 3](../../assets/saml-3.png)
1. 將 Argo CD URL 複製到 `argocd-cm` 的 data.url 中

<!-- markdownlint-disable MD046 -->
```yaml
data:
  url: https://argocd.example.com
```
<!-- markdownlint-disable MD046 -->

1. 下載 CA 憑證以在 `argocd-cm` 設定中使用。
    * 如果您在 caData 欄位中使用此憑證，則需要對整個憑證（包括 `-----BEGIN CERTIFICATE-----` 和 `-----END CERTIFICATE-----` 段落）進行 base64 編碼，例如 `base64 my_cert.pem`。
    * 如果您使用 ca 欄位並將 CA 憑證單獨儲存為密鑰，則需要將該密鑰掛載到 `argocd-dex-server` Deployment 中的 `dex` 容器。
    * ![Okta SAML App 4](../../assets/saml-4.png)
1. 編輯 `argocd-cm` 並設定 `data.dex.config` 區段：

<!-- markdownlint-disable MD046 -->
```yaml
dex.config: |
  logger:
    level: debug
    format: json
  connectors:
  - type: saml
    id: okta
    name: Okta
    config:
      ssoURL: https://yourorganization.oktapreview.com/app/yourorganizationsandbox_appnamesaml_2/rghdr9s6hg98s9dse/sso/saml
      # 您需要 `caData` _或_ `ca`，但不能同時使用。
      caData: |
        <經過 base64 編碼的 CA 憑證>
      # 您需要 `caData` _或_ `ca`，但不能同時使用。
      # 將密鑰掛載到 dex 容器的路徑
      ca: /path/to/ca.pem
      redirectURI: https://ui.argocd.yourorganization.net/api/dex/callback
      usernameAttr: email
      emailAttr: email
      groupsAttr: group
```
<!-- markdownlint-enable MD046 -->

----

### 私有部署
可以設定 Okta SSO 與私有 Argo CD 安裝，其中 Okta 回呼 URL 是唯一公開的端點。
設定基本上相同，但在 Okta 應用程式設定和 `argocd-cm` ConfigMap 的 `data.dex.config` 區段中有一些變更。

使用此部署模型，使用者連接到私有 Argo CD UI，Okta 驗證流程會無縫地重新導向回私有 UI URL。

通常，此公開端點是透過 [Ingress 物件](../../ingress/#private-argo-cd-ui-with-multiple-ingress-objects-and-byo-certificate) 公開的。


1. 更新 Okta 應用程式一般設定中的 URL
    * ![Okta SAML App Split](../../assets/saml-split.png)
        `單一登入 URL` 欄位指向公開的端點，而所有其他 URL 欄位指向內部端點。
1. 使用外部端點參考更新 `argocd-cm` ConfigMap 的 `data.dex.config` 區段。

<!-- markdownlint-disable MD046 -->
```yaml
dex.config: |
  logger:
    level: debug
  connectors:
  - type: saml
    id: okta
    name: Okta
    config:
      ssoURL: https://yourorganization.oktapreview.com/app/yourorganizationsandbox_appnamesaml_2/rghdr9s6hg98s9dse/sso/saml
      # 您需要 `caData` _或_ `ca`，但不能同時使用。
      caData: |
        <經過 base64 編碼的 CA 憑證>
      # 您需要 `caData` _或_ `ca`，但不能同時使用。
      # 將密鑰掛載到 dex 容器的路徑
      ca: /path/to/ca.pem
      redirectURI: https://external.path.to.argocd.io/api/dex/callback
      usernameAttr: email
      emailAttr: email
      groupsAttr: group
```
<!-- markdownlint-enable MD046 -->

### 將 Okta 群組連接到 Argo CD 角色
Argo CD 會辨識符合 *群組屬性陳述式* regex 的 Okta 群組中的使用者成員資格。
上面的範例使用 `argocd-*` regex，因此 Argo CD 會知道一個名為 `argocd-admins` 的群組。

修改 `argocd-rbac-cm` ConfigMap，將 `argocd-admins` Okta 群組連接到內建的 Argo CD `admin` 角色。
<!-- markdownlint-disable MD046 -->
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
data:
  policy.csv: |
    g, argocd-admins, role:admin
  scopes: '[email,groups]'
```

## OIDC (不搭配 Dex)

> [!WARNING]
> **用於 RBAC 的 Okta 群組**
>
> 如果您希望 Okta 傳回 `groups` 範圍，您需要啟用 [使用 Okta 的 API 存取管理](https://developer.okta.com/docs/concepts/api-access-management/)。此附加元件在 Okta 開發人員版本中是免費的，並會自動啟用。然而，對於生產環境，它是一個可選的附加元件，會有額外的相關費用。
>
> 您也可以在預設的授權伺服器上新增一個「groups」範圍和宣告，然後在 Okta 應用程式設定中篩選該宣告。目前尚不清楚這是否需要授權伺服器附加元件。
>
> 如果這不是您的選項，請改用上面的 [SAML (搭配 Dex)](#saml-with-dex) 選項。

> [!NOTE]
> 這些說明和螢幕截圖是 Okta 版本 2023.05.2 E 的。您可以在 Okta 網站頁尾找到目前版本。

首先，建立 OIDC 整合：

1. 在 `Okta 管理` 頁面上，導覽至 `應用程式 > 應用程式` 的 Okta 應用程式。
1. 選擇 `建立應用程式整合`，然後在產生的對話方塊中選擇 `OIDC`，然後選擇 `網頁應用程式`。
    ![Okta OIDC 應用程式對話方塊](../../assets/okta-create-oidc-app.png)
1. 更新以下內容：
    1. `應用程式整合名稱` 和 `標誌` - 根據您的需求設定這些；它們將顯示在 Okta 目錄中。
    1. `登入重新導向 URI`：新增 `https://argocd.example.com/auth/callback`；將 `argocd.example.com` 替換為您的 ArgoCD 網頁介面 URL。
    1. `登出重新導向 URI`：新增 `https://argocd.example.com`；如上所述替換為正確的網域名稱。
    1. 指派群組，或選擇暫時跳過此步驟。
    1. 將其餘選項保留原樣，並儲存整合。
    ![Okta 應用程式設定](../../assets/okta-app.png)
1. 從新建立的應用程式中複製 `用戶端 ID` 和 `用戶端密鑰`；您稍後會需要這些。

接下來，建立一個自訂的授權伺服器：

1. 在 `Okta 管理` 頁面上，導覽至 `安全性 > API` 的 Okta API 管理。
1. 按一下 `新增授權伺服器`，並為其指派名稱和描述。`受眾` 應與您的 ArgoCD URL 相符 - `https://argocd.example.com`
1. 按一下 `範圍 > 新增範圍`：
    1. 新增一個名為 `groups` 的範圍。將其餘選項保留為預設值。
    ![群組範圍](../../assets/okta-groups-scope.png)
1. 按一下 `宣告 > 新增宣告`：
    1. 新增一個名為 `groups` 的宣告。
    1. 將 `包含在權杖類型中` 調整為 `ID 權杖`，`總是`。
    1. 將 `值類型` 調整為 `群組`。
    1. 新增一個篩選器，該篩選器將與您要傳遞給 ArgoCD 的 Okta 群組相符；例如 `Regex: argocd-.*`。
    1. 將 `包含在` 設定為 `groups`（您上面建立的範圍）。
    ![群組宣告](../../assets/okta-groups-claim.png)
1. 按一下 `存取策略` > `新增策略`。此策略將限制此授權伺服器的使用方式。
    1. 新增名稱和描述。
    1. 將策略指派給您上面建立的用戶端（應用程式整合）。當您輸入時，該欄位應會自動完成。
    1. 建立策略。
    ![驗證策略](../../assets/okta-auth-policy.png)
1. 為策略新增規則：
    1. 新增名稱；`default` 是此規則的合理名稱。
    1. 微調設定以符合您組織的安全性狀況。一些想法：
        1. 取消勾選所有授權類型，除了授權碼。
        1. 調整權杖生命週期以控制會話可以持續多長時間。
        1. 限制重新整理權杖生命週期，或完全停用它。
    ![預設規則](../../assets/okta-auth-rule.png)
1. 最後，按一下 `返回授權伺服器`，並複製 `簽發者 URI`。您稍後會需要這個。

### CLI 登入

為了使用 CLI `argocd login https://argocd.example.com --sso` 登入，Okta 需要一個單獨的專用應用程式整合：

1. 建立一個新的 `建立應用程式整合`，然後選擇 `OIDC`，然後選擇 `單頁應用程式`。
1. 更新以下內容：
    1. `應用程式整合名稱` 和 `標誌` - 根據您的需求設定這些；它們將顯示在 Okta 目錄中。
    1. `登入重新導向 URI`：新增 `http://localhost:8085/auth/callback`。
    1. `登出重新導向 URI`：新增 `http://localhost:8085`。
    1. 指派群組，或選擇暫時跳過此步驟。
    1. 將其餘選項保留原樣，並儲存整合。
    1. 從新建立的應用程式中複製 `用戶端 ID`；`cliClientID: <用戶端 ID>` 將用於您的 `argocd-cm` ConfigMap。
1. 編輯您的授權伺服器 `存取策略`：
    1. 導覽至 `安全性 > API` 的 Okta API 管理。
    1. 選擇您先前建立的現有 `授權伺服器`。
    1. 按一下 `存取策略` > `編輯策略`。
    1. 透過填寫文字方塊並按一下 `更新策略` 來指派您新建立的 `應用程式整合`。
    ![編輯策略](../../assets/okta-auth-policy-edit.png)

如果您尚未建立 Okta 群組，並將其指派給應用程式整合，您現在應該這樣做：

1. 前往 `目錄 > 群組`
1. 對於您要新增的每個群組：
    1. 按一下 `新增群組`，並選擇一個有意義的名稱。它應與您新增至自訂 `group` 宣告的 regex 或模式相符。
    1. 按一下群組（如果新群組未顯示在清單中，請重新整理頁面）。
    1. 將 Okta 使用者指派給群組。
    1. 按一下 `應用程式` 並將您建立的 OIDC 應用程式整合指派給此群組。
    1. 視需要重複。

最後，設定 ArgoCD 本身。編輯 `argocd-cm` configmap：

<!-- markdownlint-disable MD046 -->
```yaml
url: https://argocd.example.com
oidc.config: |
  name: Okta
  # 這是授權伺服器 URI
  issuer: https://example.okta.com/oauth2/aus9abcdefgABCDEFGd7
  clientID: 0oa9abcdefgh123AB5d7
  cliClientID: gfedcba0987654321GEFDCBA # 如果使用 CLI 進行 SSO，則為可選
  clientSecret: ABCDEFG1234567890abcdefg
  requestedScopes: ["openid", "profile", "email", "groups"]
  requestedIDTokenClaims: {"groups": {"essential": true}}
```

您可能希望將 `clientSecret` 儲存在 Kubernetes 密鑰中；有關更多詳細資訊，請參閱 [如何處理 SSO 密鑰](./index.md/#sensitive-data-and-sso-client-secrets )。
