# Google

有三種不同的方法可以將 Argo CD 登入與您的 Google Workspace 使用者整合。一般來說，OpenID Connect (_oidc_) 方法是執行此整合的建議方法（也更容易...），但根據您的需求，您可能會選擇不同的選項。

- [使用 Dex 的 OpenID Connect](#openid-connect-using-dex)
  如果您不需要使用者所屬群組的資訊，這是建議的登入方法。Google 不會透過 _oidc_ 公開 `groups` 聲明，因此您將無法使用 Google 群組成員資格資訊進行 RBAC。
- [使用 Dex 的 SAML 應用程式驗證](#saml-app-auth-using-dex)
  Dex [建議避免使用此方法](https://dexidp.io/docs/connectors/saml/#warning)。此外，您也無法透過此方法取得 Google 群組成員資格資訊。
- [使用 Dex 的 OpenID Connect 加上 Google 群組](#openid-connect-plus-google-groups-using-dex)
  如果您需要在 RBAC 設定中使用 Google 群組成員資格，這是建議的方法。

設定上述其中一種整合後，請務必編輯 `argo-rbac-cm` 以設定權限（如下方範例所示）。有關更詳細的情境，請參閱 [RBAC 設定](../rbac.md)。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
```

## 使用 Dex 的 OpenID Connect

### 設定您的 OAuth 同意畫面

如果您從未設定過此項目，當您嘗試建立 OAuth 用戶端 ID 時，將會直接重新導向至此處。

1. 前往您的 [OAuth 同意](https://console.cloud.google.com/apis/credentials/consent) 設定。如果您尚未建立，請選取 `內部` 或 `外部` 並按一下 `建立`。
2. 前往並 [編輯您的 OAuth 同意畫面](https://console.cloud.google.com/apis/credentials/consent/edit)。確認您位於正確的專案中！
3. 為您的登入應用程式設定名稱和使用者支援電子郵件地址。
4. 應用程式標誌和填寫資訊連結並非強制性，但這對登入頁面來說是不錯的點綴。
5. 在「已授權的網域」中，新增允許登入 ArgoCD 的網域（例如，如果您新增 `example.com`，所有具有 `@example.com` 地址的 Google Workspace 使用者都能夠登入）。
6. 儲存以繼續至「範圍」區段。
7. 按一下「新增或移除範圍」，然後新增 `.../auth/userinfo.profile` 和 `openid` 範圍。
8. 儲存、檢閱您的變更摘要並完成。

### 設定新的 OAuth 用戶端 ID

1. 前往您的 [Google API 憑證](https://console.cloud.google.com/apis/credentials) 主控台，並確認您位於正確的專案中。
2. 按一下「+建立憑證」/「OAuth 用戶端 ID」。
3. 在「應用程式類型」下拉式選單中選取「網頁應用程式」，並為您的應用程式輸入一個識別名稱（例如 `Argo CD`）。
4. 在「已授權的 JavaScript 來源」中填入您的 Argo CD URL，例如 `https://argocd.example.com`。
5. 在「已授權的重新導向 URI」中填入您的 Argo CD URL 加上 `/api/dex/callback`，例如 `https://argocd.example.com/api/dex/callback`。

   ![](../../assets/google-admin-oidc-uris.png)

6. 按一下「建立」，並儲存您的「用戶端 ID」和「用戶端密鑰」以供後用。

### 設定 Argo 以使用 OpenID Connect

編輯 `argocd-cm` 並將下列 `dex.config` 新增至 data 區段，將 `clientID` 和 `clientSecret` 替換為您先前儲存的值：

```yaml
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
    - config:
        issuer: https://accounts.google.com
        clientID: XXXXXXXXXXXXX.apps.googleusercontent.com
        clientSecret: XXXXXXXXXXXXX
      type: oidc
      id: google
      name: Google
```

### 參考資料

- [Dex oidc 連接器文件](https://dexidp.io/docs/connectors/oidc/)

## 使用 Dex 的 SAML 應用程式驗證

### 設定新的 SAML 應用程式

---

> [!WARNING]
> **棄用警告**
>
> 請注意，根據 [Dex 文件](https://dexidp.io/docs/connectors/saml/#warning)，SAML 被認為不安全，他們正計劃棄用該模組。

---

1. 在 [Google 管理主控台](https://admin.google.com) 中，開啟左側選單並選取 `應用程式` > `SAML 應用程式`。

   ![Google 管理應用程式選單](../../assets/google-admin-saml-apps-menu.png '已選取應用程式 / SAML 應用程式路徑的 Google 管理選單')

2. 在 `新增應用程式` 下，選取 `新增自訂 SAML 應用程式`。

   ![Google 管理新增自訂 SAML 應用程式](../../assets/google-admin-saml-add-app-menu.png '已反白顯示新增自訂 SAML 應用程式的新增應用程式選單')

3. 輸入應用程式的 `名稱`（例如 `Argo CD`），然後選擇 `繼續`。

   ![Google 管理應用程式選單](../../assets/google-admin-saml-app-details.png '已反白顯示新增自訂 SAML 應用程式的新增應用程式選單')

4. 從身分提供者詳細資料中下載中繼資料或複製 `SSO URL`、`憑證` 和可選的 `實體 ID`，以供下一節使用。選擇 `繼續`。

   - 將憑證檔案的內容進行 Base64 編碼，例如：
   - `$ cat ArgoCD.cer | base64`
   - _保留一份編碼後輸出的副本，以供下一節使用。_
   - _在進行 Base64 編碼之前，請確保憑證為 PEM 格式。_

   ![Google 管理 IdP 中繼資料](../../assets/google-admin-idp-metadata.png 'Google IdP 中繼資料的螢幕截圖')

5. 對於 `ACS URL` 和 `實體 ID`，請使用您的 Argo Dex 回呼 URL，例如：`https://argocd.example.com/api/dex/callback`。

   ![Google 管理服務提供者詳細資料](../../assets/google-admin-service-provider-details.png 'Google 服務提供者詳細資料的螢幕截圖')

6. 新增 SAML 屬性對應，將 `主要電子郵件` 對應至 `name`，並將 `主要電子郵件` 對應至 `email`。然後按一下 `新增對應` 按鈕。

   ![Google 管理 SAML 屬性對應詳細資料](../../assets/google-admin-saml-attribute-mapping-details.png 'Google 管理 SAML 屬性對應詳細資料的螢幕截圖')

7. 完成建立應用程式。

### 設定 Argo 以使用新的 Google SAML 應用程式

編輯 `argocd-cm` 並將下列 `dex.config` 新增至 data 區段，將 `caData`、`argocd.example.com`、`sso-url` 和可選的 `google-entity-id` 替換為您從 Google SAML 應用程式取得的值：

```yaml
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
    - type: saml
      id: saml
      name: saml
      config:
        ssoURL: https://sso-url (e.g. https://accounts.google.com/o/saml2/idp?idpid=Abcde0)
        entityIssuer: https://argocd.example.com/api/dex/callback
        caData: |
          BASE64-ENCODED-CERTIFICATE-DATA
        redirectURI: https://argocd.example.com/api/dex/callback
        usernameAttr: name
        emailAttr: email
        # optional
        ssoIssuer: https://google-entity-id (e.g. https://accounts.google.com/o/saml2?idpid=Abcde0)
```

### 參考資料

- [Dex SAML 連接器文件](https://dexidp.io/docs/connectors/saml/)
- [Google 的 SAML 錯誤訊息](https://support.google.com/a/answer/6301076?hl=en)

## 使用 Dex 的 OpenID Connect 加上 Google 群組

我們將使用 Dex 的 `google` 連接器來從您的使用者取得額外的 Google 群組資訊，讓您可以在 RBAC 中使用群組成員資格，例如，將 `admin` 角色授予整個 `sysadmins@yourcompany.com` 群組。

此連接器使用兩種不同的憑證：

- 一個 oidc 用戶端 ID 和密鑰
  與您設定 [OpenID 連線](#openid-connect-using-dex) 時相同，這會驗證您的使用者。
- 一個 Google 服務帳戶
  這用於連接至 Google Directory API 並提取有關您使用者群組成員資格的資訊。

此外，您還需要此網域中管理員使用者的電子郵件地址。Dex 將模擬該使用者身分以從 API 擷取使用者資訊。

### 設定 OpenID Connect

執行與 [使用 Dex 的 OpenID Connect](#openid-connect-using-dex) 中相同的步驟，但設定 `argocd-cm` 除外。我們稍後會進行此操作。

### 設定 Directory API 存取權

1. 遵循 [Google 的指示，建立具有全網域委派的服務帳戶](https://developers.google.com/admin-sdk/directory/v1/guides/delegation)。
   - 將 API 範圍指派給服務帳戶時，範圍必須**嚴格包含** `https://www.googleapis.com/auth/admin.directory.group.readonly`。如果您只指派 [更廣泛的範圍] (https://www.googleapis.com/auth/admin.directory.group)，您將無法從 API 擷取資料。
   - 以 JSON 格式建立憑證並將其儲存在安全的地方，我們稍後會需要它們。
2. 啟用 [Admin SDK](https://console.developers.google.com/apis/library/admin.googleapis.com/)。

### 設定 Dex

1. **設定驗證憑證**

   **選項 1：使用服務帳戶檔案（傳統方法）**

   使用先前 json 檔案的內容（以 base64 編碼）建立一個密鑰，如下所示：

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: argocd-google-groups-json
     namespace: argocd
   data:
     googleAuth.json: JSON_FILE_BASE64_ENCODED
   ```

   然後編輯您的 `argocd-dex-server` 部署，將該密鑰掛載為檔案：

   - 在 `/spec/template/spec/containers/0/volumeMounts/` 中新增一個磁碟區掛載，如下所示。請注意編輯執行中的容器，而非初始容器！

     ```yaml
     volumeMounts:
       - mountPath: /shared
         name: static-files
       - mountPath: /tmp
         name: dexconfig
       - mountPath: /tmp/oidc
         name: google-json
         readOnly: true
     ```

   - 在 `/spec/template/spec/volumes/` 中新增一個磁碟區，如下所示：

     ```yaml
     volumes:
       - emptyDir: {}
         name: static-files
       - emptyDir: {}
         name: dexconfig
       - name: google-json
         secret:
           defaultMode: 420
           secretName: argocd-google-groups-json
     ```

   **選項 2：使用工作負載身分（Dex > v2.34.0）**

   為您的 `argocd-dex-server` 服務帳戶設定工作負載身分。使用工作負載身分時，不需要密鑰檔案。

2. 編輯 `argocd-cm` 並將下列 `url` 和 `dex.config` 新增至 data 區段，將 `clientID` 和 `clientSecret` 替換為您先前儲存的值，將 `adminEmail` 替換為您要模擬的管理員使用者的地址，並使用您的 Argo CD 網域編輯 `redirectURI`（請注意，`type` 現在是 `google` 而非 `oidc`）：

   **選項 1：使用服務帳戶檔案**

   ```yaml
   data:
     url: https://argocd.example.com
     dex.config: |
       connectors:
       - config:
           redirectURI: https://argocd.example.com/api/dex/callback
           clientID: XXXXXXXXXXXXX.apps.googleusercontent.com
           clientSecret: XXXXXXXXXXXXX
           serviceAccountFilePath: /tmp/oidc/googleAuth.json
           adminEmail: admin-email@example.com
           # Optional: Enable transitive group membership (Dex > v2.31.0)
           # 選擇性：啟用遞移群組成員資格 (Dex > v2.31.0)
           # fetchTransitiveGroupMembership: True
         type: google
         id: google
         name: Google
   ```

   **選項 2：使用工作負載身分（Dex > v2.34.0）**

   ```yaml
   data:
     url: https://argocd.example.com
     dex.config: |
       connectors:
       - config:
           redirectURI: https://argocd.example.com/api/dex/callback
           clientID: XXXXXXXXXXXXX.apps.googleusercontent.com
           clientSecret: XXXXXXXXXXXXX
           adminEmail: admin-email@example.com
           fetchTransitiveGroupMembership: True
         type: google
         id: google
         name: Google
   ```

3. 重新啟動您的 `argocd-dex-server` 部署，以確保其使用最新的設定。
4. 登入 Argo CD 並前往「使用者資訊」區段，您應該會看到您所屬的群組。
   ![使用者資訊](../../assets/google-groups-membership.png)
5. 現在您可以使用群組電子郵件地址來授予 RBAC 權限。

### 參考資料

- [Dex Google 連接器文件](https://dexidp.io/docs/connectors/google/)
