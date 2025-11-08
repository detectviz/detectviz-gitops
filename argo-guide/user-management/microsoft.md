# Microsoft

> [!NOTE]
> Entra ID 以前稱為 Azure AD。

* [使用 OIDC 的 Entra ID 應用程式註冊驗證](#entra-id-app-registration-auth-using-oidc)
* [使用 Dex 的 Entra ID SAML 企業應用程式驗證](#entra-id-saml-enterprise-app-auth-using-dex)
* [使用 Dex 的 Entra ID 應用程式註冊驗證](#entra-id-app-registration-auth-using-dex)

## 使用 OIDC 的 Entra ID 應用程式註冊驗證
### 設定新的 Entra ID 應用程式註冊
#### 新增 Entra ID 應用程式註冊

1. 從 `Microsoft Entra ID` > `應用程式註冊` 選單中，選擇 `+ 新增註冊`
2. 輸入應用程式的 `名稱` (例如 `Argo CD`)。
3. 指定可以使用應用程式的人員 (例如 `僅限此組織目錄中的帳戶`)。
4. 輸入重新導向 URI (選用)，如下所示 (將 `my-argo-cd-url` 替換為您的 Argo URL)，然後選擇 `新增`。
      - **平台：** `Web`
      - **重新導向 URI：** https://`<my-argo-cd-url>`/auth/callback
5. 註冊完成後，Azure 入口網站會顯示應用程式註冊的「概觀」窗格。您會看到「應用程式 (用戶端) 識別碼」。
      ![Azure 應用程式註冊概觀](../../assets/azure-app-registration-overview.png "Azure 應用程式註冊概觀")

#### 為 ArgoCD CLI 設定其他平台設定

1. 在 Azure 入口網站的「應用程式註冊」中，選取您的應用程式。
2. 在「管理」下，選取「驗證」。
3. 在「平台設定」下，選取「新增平台」。
4. 在「設定平台」下，選取「行動和桌面應用程式」圖磚。請使用以下值，您不應變更它。
      - **重新導向 URI：** `http://localhost:8085/auth/callback`
      ![Azure 應用程式註冊驗證](../../assets/azure-app-registration-authentication.png "Azure 應用程式註冊驗證")

#### 新增 Entra ID 應用程式註冊的憑證
##### 使用工作負載識別聯合 (建議)
1.  **為 Pod 加上標籤：** 將 `azure.workload.identity/use: "true"` 標籤新增至 `argocd-server` pod。
2. **為服務帳戶新增註解：** 使用上一步驟中建立的應用程式詳細資料，將 `azure.workload.identity/client-id: "$CLIENT_ID"` 註解新增至 `argocd-server` 服務帳戶。
3. 從 `憑證和秘密` 選單中，瀏覽至 `聯合憑證`，然後選擇 `+ 新增憑證`
4. 選擇 `聯合憑證情境` 為 `Kubernetes 存取 Azure 資源`
   - 輸入叢集簽發者 URL，請參閱 [擷取 OIDC 簽發者 URL](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster#retrieve-the-oidc-issuer-url) 文件
   - 輸入 argocd 部署所在的命名空間
   - 輸入服務帳戶名稱為 `argocd-server`
   - 輸入唯一的名稱
   - 按一下「新增」。

##### 使用用戶端密碼
1. 從 `憑證和秘密` 選單中，選擇 `+ 新增用戶端密碼`
2. 輸入秘密的 `名稱` (例如 `ArgoCD-SSO`)。
      - 請務必複製並儲存產生的值。這是 `client_secret` 的值。
      ![Azure 應用程式註冊秘密](../../assets/azure-app-registration-secret.png "Azure 應用程式註冊秘密")

#### 設定 Entra ID 應用程式的權限

1. 從 `API 權限` 選單中，選擇 `+ 新增權限`
2. 尋找 `User.Read` 權限 (在 `Microsoft Graph` 下) 並將其授予建立的應用程式：
   ![Entra ID API 權限](../../assets/azure-api-permissions.png "Entra ID API 權限")
3. 從 `權杖設定` 選單中，選擇 `+ 新增群組宣告`
   ![Entra ID 權杖設定](../../assets/azure-token-configuration.png "Entra ID 權杖設定")

### 將 Entra ID 群組與您的 Entra ID 應用程式註冊建立關聯

1. 從 `Microsoft Entra ID` > `企業應用程式` 選單中，搜尋您建立的應用程式 (例如 `Argo CD`)。
      - 當您新增 Entra ID 應用程式註冊時，會建立一個與 Entra ID 應用程式註冊同名的企業應用程式。
2. 從應用程式的 `使用者和群組` 選單中，新增需要存取服務的任何使用者或群組。
   ![Azure 企業 SAML 使用者](../../assets/azure-enterprise-users.png "Azure 企業 SAML 使用者")

### 設定 Argo 以使用新的 Entra ID 應用程式註冊

1. 編輯 `argocd-cm` 並設定 `data.oidc.config` 和 `data.url` 區段：

            ConfigMap -> argocd-cm

            data:
               url: https://argocd.example.com/ # 請替換為您的 Argo CD 外部基礎 URL
               oidc.config: |
                     name: Azure
                     issuer: https://login.microsoftonline.com/{directory_tenant_id}/v2.0
                     clientID: {azure_ad_application_client_id}
                     clientSecret: $oidc.azure.clientSecret // 如果使用用戶端密碼進行驗證
                     azure:
                       useWorkloadIdentity: true // 如果使用 azure workload identity 進行驗證
                     requestedIDTokenClaims:
                        groups:
                           essential: true
                           value: "ApplicationGroup"
                     requestedScopes:
                        - openid
                        - profile
                        - email

2. 如果使用 azure workload identity，請略過此步驟。編輯 `argocd-secret` 並設定 `data.oidc.azure.clientSecret` 區段：

            Secret -> argocd-secret

            data:
               oidc.azure.clientSecret: {client_secret | base64_encoded}

3. 編輯 `argocd-rbac-cm` 以設定權限。使用 Azure 的群組 ID 來指派角色
      [RBAC 設定](../rbac.md)

            ConfigMap -> argocd-rbac-cm

            policy.default: role:readonly
            policy.csv: |
               p, role:org-admin, applications, *, */*, allow
               p, role:org-admin, clusters, get, *, allow
               p, role:org-admin, repositories, get, *, allow
               p, role:org-admin, repositories, create, *, allow
               p, role:org-admin, repositories, update, *, allow
               p, role:org-admin, repositories, delete, *, allow
               g, "84ce98d1-e359-4f3b-85af-985b458de3c6", role:org-admin

4. 將 jwt 權杖中的角色對應至 argo。
   如果您想將 jwt 權杖中的角色對應至預設角色 (readonly 和 admin)，則必須變更 rbac-configmap 中的 scope 變數。

            policy.default: role:readonly
            policy.csv: |
               p, role:org-admin, applications, *, */*, allow
               p, role:org-admin, clusters, get, *, allow
               p, role:org-admin, repositories, get, *, allow
               p, role:org-admin, repositories, create, *, allow
               p, role:org-admin, repositories, update, *, allow
               p, role:org-admin, repositories, delete, *, allow
               g, "84ce98d1-e359-4f3b-85af-985b458de3c6", role:org-admin
            scopes: '[groups, email]'

   請參閱 [operator-manual/argocd-rbac-cm.yaml](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-rbac-cm.yaml) 以取得所有可用的變數。

## 使用 Dex 的 Entra ID SAML 企業應用程式驗證
### 設定新的 Entra ID 企業應用程式

1. 從 `Microsoft Entra ID` > `企業應用程式` 選單中，選擇 `+ 新增應用程式`
2. 選取 `非資源庫應用程式`
3. 輸入應用程式的 `名稱` (例如 `Argo CD`)，然後選擇 `新增`
4. 建立應用程式後，從 `企業應用程式` 選單中開啟它。
5. 從應用程式的 `使用者和群組` 選單中，新增需要存取服務的任何使用者或群組。
   ![Azure 企業 SAML 使用者](../../assets/azure-enterprise-users.png "Azure 企業 SAML 使用者")
6. 從 `單一登入` 選單中，如下編輯 `基本 SAML 設定` 區段 (將 `my-argo-cd-url` 替換為您的 Argo URL)：
      - **識別碼 (實體 ID)：** https://`<my-argo-cd-url>`/api/dex/callback
      - **回覆 URL (判斷提示取用者服務 URL)：** https://`<my-argo-cd-url>`/api/dex/callback
      - **登入 URL：** https://`<my-argo-cd-url>`/auth/login
      - **轉送狀態：** `<empty>`
      - **登出 URL：** `<empty>`
      ![Azure 企業 SAML URL](../../assets/azure-enterprise-saml-urls.png "Azure 企業 SAML URL")
7. 從 `單一登入` 選單中，編輯 `使用者屬性和宣告` 區段以建立以下宣告：
      - `+ 新增宣告` | **名稱：** email | **來源：** 屬性 | **來源屬性：** user.mail
      - `+ 新增群組宣告` | **哪些群組：** 所有群組 | **來源屬性：** 群組 ID | **自訂：** 是 | **名稱：** Group | **命名空間：** `<empty>` | **將群組發行為角色宣告：** 否
      - *注意：`唯一使用者識別碼` 必要宣告可以保留為預設的 `user.userprincipalname`*
      ![Azure 企業 SAML 宣告](../../assets/azure-enterprise-claims.png "Azure 企業 SAML 宣告")
8. 從 `單一登入` 選單中，下載 SAML 簽署憑證 (Base64)
      - 將下載的憑證檔案內容進行 Base64 編碼，例如：
      - `$ cat ArgoCD.cer | base64`
      - *保留一份編碼後輸出的副本，以供下一節使用。*
9. 從 `單一登入` 選單中，複製 `登入 URL` 參數，以供下一節使用。

### 設定 Argo 以使用新的 Entra ID 企業應用程式

1. 編輯 `argocd-cm` 並將以下 `dex.config` 新增至 data 區段，將 `caData`、`my-argo-cd-url` 和 `my-login-url` 替換為您從 Entra ID 應用程式取得的值：

            data:
              url: https://my-argo-cd-url
              dex.config: |
                logger:
                  level: debug
                  format: json
                connectors:
                - type: saml
                  id: saml
                  name: saml
                  config:
                    entityIssuer: https://my-argo-cd-url/api/dex/callback
                    ssoURL: https://my-login-url (e.g. https://login.microsoftonline.com/xxxxx/a/saml2)
                    caData: |
                       MY-BASE64-ENCODED-CERTIFICATE-DATA
                    redirectURI: https://my-argo-cd-url/api/dex/callback
                    usernameAttr: email
                    emailAttr: email
                    groupsAttr: Group

2. 編輯 `argocd-rbac-cm` 以設定權限，類似於以下範例。
      - 使用 Entra ID `群組 ID` 來指派角色。
      - 有關更詳細的情境，請參閱 [RBAC 設定](../rbac.md)。

            # 範例策略
            policy.default: role:readonly
            policy.csv: |
               p, role:org-admin, applications, *, */*, allow
               p, role:org-admin, clusters, get, *, allow
               p, role:org-admin, repositories, get, *, allow
               p, role:org-admin, repositories, create, *, allow
               p, role:org-admin, repositories, update, *, allow
               p, role:org-admin, repositories, delete, *, allow
               g, "84ce98d1-e359-4f3b-85af-985b458de3c6", role:org-admin # (指派給角色的 azure 群組)

## 使用 Dex 的 Entra ID 應用程式註冊驗證

如上所述，設定新的 AD 應用程式註冊。
然後，將 `dex.config` 新增至 `argocd-cm`：
```yaml
ConfigMap -> argocd-cm

data:
    dex.config: |
      connectors:
      - type: microsoft
        id: microsoft
        name: Your Company GmbH
        config:
          clientID: $MICROSOFT_APPLICATION_ID
          clientSecret: $MICROSOFT_CLIENT_SECRET
          redirectURI: http://localhost:8080/api/dex/callback
          tenant: ffffffff-ffff-ffff-ffff-ffffffffffff
          groups:
            - DevOps
```

## 驗證
### 使用 SSO 登入 ArgoCD UI

1. 開啟新的瀏覽器分頁並輸入您的 ArgoCD URI：https://`<my-argo-cd-url>`
   ![Azure SSO Web 登入](../../assets/azure-sso-web-log-in-via-azure.png "Azure SSO Web 登入")
3. 按一下 `LOGIN VIA AZURE` 按鈕以使用您的 Microsoft Entra ID 帳戶登入。您將會看到 ArgoCD 應用程式畫面。
   ![Azure SSO Web 應用程式](../../assets/azure-sso-web-application.png "Azure SSO Web 應用程式")
4. 導覽至「使用者資訊」並驗證群組 ID。群組將會有您在 `設定 Entra ID 應用程式的權限` 步驟中新增的群組物件 ID。
   ![Azure SSO Web 使用者資訊](../../assets/azure-sso-web-user-info.png "Azure SSO Web 使用者資訊")

### 使用 CLI 登入 ArgoCD

1. 開啟終端機，執行以下指令。

            argocd login <my-argo-cd-url> --grpc-web-root-path / --sso

2. 從瀏覽器輸入您的憑證後，您將會看到以下訊息。
   ![Azure SSO CLI 登入](../../assets/azure-sso-cli-log-in-success.png "Azure SSO CLI 登入")
3. 您的終端機輸出將類似於以下內容。

            WARNING: server certificate had error: x509: certificate is valid for ingress.local, not my-argo-cd-url. Proceed insecurely (y/n)? y
            Opening browser for authentication
            INFO[0003] RequestedClaims: map[groups:essential:true ]
            Performing authorization_code flow login: https://login.microsoftonline.com/XXXXXXXXXXXXX/oauth2/v2.0/authorize?access_type=offline&claims=%7B%22id_token%22%3A%7B%22groups%22%3A%7B%22essential%22%3Atrue%7D%7D%7D&client_id=XXXXXXXXXXXXX&code_challenge=XXXXXXXXXXXXX&code_challenge_method=S256&redirect_uri=http%3A%2F%2Flocalhost%3A8085%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+offline_access&state=XXXXXXXX
            Authentication successful
            'yourid@example.com' logged in successfully
            Context 'my-argo-cd-url' updated

   如果您未使用正確簽署的憑證，可能會收到警告。請參閱 [為何我在使用 CLI 時收到 x509：憑證由未知授權單位簽署？](https://argo-cd.readthedocs.io/en/stable/faq/#why-am-i-getting-x509-certificate-signed-by-unknown-authority-when-using-the-cli)。
