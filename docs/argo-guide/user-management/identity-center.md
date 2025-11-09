# Identity Center (AWS SSO)

> [!NOTE]
> **您正在使用這個嗎？請貢獻！**
>
> 如果您正在使用此 IdP，請考慮為本文件[貢獻](../../developer-guide/docs-site.md)。

已透過以下方法成功實現使用 Identity Center (AWS SSO) 的單一登入設定：

* [SAML (搭配 Dex)](#saml-with-dex)

## SAML (搭配 Dex)

1. 在 Identity Center 中建立一個新的 SAML 應用程式並下載憑證。

![Identity Center SAML App 1](../../assets/identity-center-1.png)

![Identity Center SAML App 2](../../assets/identity-center-2.png)

2. 在 Identity Center 中建立應用程式後，按一下 `指派使用者`，然後選取您希望授予此應用程式存取權的使用者或使用者群組。

![Identity Center SAML App 3](../../assets/identity-center-3.png)

3. 將 Argo CD URL 複製到 `argocd-cm` ConfigMap 中的 `data.url` 欄位。

        data:
          url: https://argocd.example.com

4. 設定屬性對應。

    !!! note "群組屬性對應並非官方支援！"
        AWS 文件中並未正式支援群組屬性對應，但此解決方法目前有效。

![Identity Center SAML App 4](../../assets/identity-center-4.png)

![Identity Center SAML App 5](../../assets/identity-center-5.png)

<!-- markdownlint-enable MD046 -->

5. 下載 CA 憑證以在 `argocd-cm` 設定中使用。

    * 如果使用 `caData` 欄位，您需要對整個憑證進行 base64 編碼，包括 `-----BEGIN CERTIFICATE-----` 和 `-----END CERTIFICATE-----` 段落 (例如，`base64 my_cert.pem`)。

    * 如果使用 `ca` 欄位並將 CA 憑證單獨儲存為密鑰，您需要將該密鑰掛載到 `argocd-dex-server` Deployment 中的 `dex` 容器上。

![Identity Center SAML App 6](../../assets/identity-center-6.png)

6. 編輯 `argocd-cm` 並設定 `data.dex.config` 區段：

<!-- markdownlint-disable MD046 -->
```yaml
dex.config: |
  logger:
    level: debug
    format: json
  connectors:
  - type: saml
    id: aws
    name: "AWS IAM Identity Center"
    config:
      # 您需要 Identity Center APP SAML 的值 (IAM Identity Center 登入 URL)
      ssoURL: https://portal.sso.yourregion.amazonaws.com/saml/assertion/id
      # 您需要 `caData` _或_ `ca`，但不能兩者都用。
      caData: <經過 base64 編碼的 CA 憑證 (IAM Identity Center APP SAML 的 Identity Center 憑證)>
      # 將密鑰掛載到 dex 容器的路徑
      entityIssuer: https://external.path.to.argocd.io/api/dex/callback
      redirectURI: https://external.path.to.argocd.io/api/dex/callback
      usernameAttr: email
      emailAttr: email
      groupsAttr: groups
```
<!-- markdownlint-enable MD046 -->

### 將 Identity Center 群組連接到 Argo CD 角色

Argo CD 會辨識符合 **群組屬性陳述式** regex 的 Identity Center 群組中的使用者成員資格。

 在上面的範例中，使用了 regex `argocd-*`，讓 Argo CD 知道一個名為 `argocd-admins` 的群組。

修改 `argocd-rbac-cm` ConfigMap，將 `ArgoCD-administrators` Identity Center 群組連接到內建的 Argo CD `admin` 角色。
<!-- markdownlint-disable MD046 -->
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
data:
  policy.csv: |
    g, <Identity Center Group ID>, role:admin
  scopes: '[groups, email]'
```
<!-- markdownlint-enable MD046 -->
