# Zitadel
另請參閱 [Zitadel 文件](https://zitadel.com/docs)。
## 整合 Zitadel 和 ArgoCD
這些說明將引導您完成讓 ArgoCD 應用程式使用 Zitadel 進行驗證和授權的整個過程。您將在 Zitadel 中建立一個應用程式，並設定 ArgoCD 使用 Zitadel 進行驗證，並使用 Zitadel 中設定的角色來決定 ArgoCD 中的權限。

整合 ArgoCD 與 Zitadel 需要執行以下步驟：
1. 在 Zitadel 中建立新專案和新應用程式
2. 在 Zitadel 中設定應用程式
3. 在 Zitadel 中設定角色
4. 在 Zitadel 中設定動作
5. 設定 ArgoCD configmaps
6. 測試設定

本範例將使用以下值：
- Zitadel FQDN：`auth.example.com`
- Zitadel 專案：`argocd-project`
- Zitadel 應用程式：`argocd-application`
- Zitadel 動作：`groupsClaim`
- ArgoCD FQDN：`argocd.example.com`
- ArgoCD 管理員角色：`argocd_administrators`
- ArgoCD 使用者角色：`argocd_users`

您可以在您的設定中選擇不同的值；這些值用於保持本指南的一致性。

## 在 Zitadel 中設定您的專案和應用程式
首先，我們將在 Zitadel 中建立一個新專案。前往 **專案** 並選取 **建立新專案**。
您現在應該會看到以下畫面。

![Zitadel 專案](../../assets/zitadel-project.png "Zitadel 專案")

勾選以下選項：
- 驗證時判斷角色
- 驗證時檢查授權

![Zitadel 專案設定](../../assets/zitadel-project-settings.png "Zitadel 專案設定")

### 角色

前往 **角色** 並按一下 **新增**。建立以下兩個角色。對 **金鑰** 和 **群組** 這兩個欄位都使用下面指定的值。
- `argocd_administrators`
- `argocd_users`

您的角色現在應如下所示：

![Zitadel 專案角色](../../assets/zitadel-project-roles.png "Zitadel 專案角色")

### 授權

接下來，前往 **授權** 並將您的使用者指派給 `argocd_administrators` 角色。
按一下 **新增**，輸入您的使用者名稱，然後按一下 **繼續**。選取 `argocd_administrators` 角色，然後按一下 **儲存**。

您的授權現在應如下所示：

![Zitadel 專案授權](../../assets/zitadel-project-authorizations.png "Zitadel 專案授權")

### 建立應用程式

前往 **一般** 並建立新應用程式。將應用程式命名為 `argocd-application`。

對於應用程式類型，選取 **WEB** 並按一下繼續。

![Zitadel 應用程式設定步驟 1](../../assets/zitadel-application-1.png "Zitadel 應用程式設定步驟 1")

選取 **CODE** 並繼續。

![Zitadel 應用程式設定步驟 2](../../assets/zitadel-application-2.png "Zitadel 應用程式設定步驟 2")

接下來，我們將設定重新導向和登出後 URI。設定以下值：
- 重新導向 URI：`https://argocd.example.com/auth/callback`
- 登出後 URI：`https://argocd.example.com`

登出後 URI 是選用的。在範例設定中，使用者登出後將返回 ArgoCD 登入頁面。

![Zitadel 應用程式設定步驟 3](../../assets/zitadel-application-3.png "Zitadel 應用程式設定步驟 3")

在下一個畫面中驗證您的設定，然後按一下 **建立** 以建立應用程式。

![Zitadel 應用程式設定步驟 4](../../assets/zitadel-application-4.png "Zitadel 應用程式設定步驟 4")

按一下 **建立** 後，您將會看到應用程式的 `ClientId` 和 `ClientSecret`。請務必複製 ClientSecret，因為關閉此視窗後您將無法再擷取它。
在我們的範例中，使用以下值：
- ClientId：`227060711795262483@argocd-project`
- ClientSecret：`UGvTjXVFAQ8EkMv2x4GbPcrEwrJGWZ0sR2KbwHRNfYxeLsDurCiVEpa5bkgW0pl0`

![Zitadel 應用程式密鑰](../../assets/zitadel-application-secrets.png "Zitadel 應用程式密鑰")

將 ClientSecret 儲存在安全的地方後，按一下 **關閉** 以完成建立應用程式。

前往 **權杖設定** 並啟用以下選項：
- ID 權杖內的使用者角色
- ID 權杖內的使用者資訊

![Zitadel 應用程式設定](../../assets/zitadel-application-settings.png "Zitadel 應用程式設定")

## 在 Zitadel 中設定動作

為了在 Zitadel 核發的權杖中包含使用者的角色，我們需要設定一個 Zitadel 動作。ArgoCD 中的授權將由驗證權杖中包含的角色決定。
前往 **動作**，按一下 **新增** 並選擇 `groupsClaim` 作為您動作的名稱。

將以下程式碼貼到動作中：

```javascript
/**
 * sets the roles an additional claim in the token with roles as value an project as key
 *
 * The role claims of the token look like the following:
 *
 * // added by the code below
 * "groups": ["{roleName}", "{roleName}", ...],
 *
 * Flow: Complement token, Triggers: Pre Userinfo creation, Pre access token creation
 *
 * @param ctx
 * @param api
 */
function groupsClaim(ctx, api) {
  if (ctx.v1.user.grants === undefined || ctx.v1.user.grants.count == 0) {
    return;
  }

  let grants = [];
  ctx.v1.user.grants.grants.forEach((claim) => {
    claim.roles.forEach((role) => {
      grants.push(role);
    });
  });

  api.v1.claims.setClaim("groups", grants);
}
```

勾選 **允許失敗** 並按一下 **新增** 以新增您的動作。

*注意：如果未勾選 **允許失敗** 且使用者未指派角色，則使用者可能無法再登入 Zitadel，因為當動作失敗時登入流程會失敗。*

接下來，將您的動作新增至 **補充權杖** 流程。從下拉式選單中選取 **補充權杖** 流程，然後按一下 **新增觸發器**。
將您的動作新增至 **建立使用者資訊前** 和 **建立存取權杖前** 這兩個觸發器。

您的「動作」頁面現在應如下列螢幕截圖所示：

![Zitadel 動作](../../assets/zitadel-actions.png "Zitadel 動作")


## 設定 ArgoCD configmaps

接下來，我們將設定兩個 ArgoCD configmaps：
- [argocd-cm.yaml](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-cm.yaml)
- [argocd-rbac-cm.yaml](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-rbac-cm.yaml)

如下所示設定您的 configmaps，並務必將相關值（例如 `url`、`issuer`、`clientID`、`clientSecret` 和 `logoutURL`）替換為符合您設定的值。

### argocd-cm.yaml
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  admin.enabled: "false"
  url: https://argocd.example.com
  oidc.config: |
    name: Zitadel
    issuer: https://auth.example.com
    clientID: 227060711795262483@argocd-project
    clientSecret: UGvTjXVFAQ8EkMv2x4GbPcrEwrJGWZ0sR2KbwHRNfYxeLsDurCiVEpa5bkgW0pl0
    requestedScopes:
      - openid
      - profile
      - email
      - groups
    logoutURL: https://auth.example.com/oidc/v1/end_session
```

### argocd-rbac-cm.yaml
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  scopes: '[groups]'
  policy.csv: |
    g, argocd_administrators, role:admin
    g, argocd_users, role:readonly
  policy.default: ''
```

`policy.csv` 下指定的角色必須與 Zitadel 中設定的角色相符。
Zitadel 角色 `argocd_administrators` 將被指派 ArgoCD 角色 `admin`，授予對 ArgoCD 的管理員存取權限。
Zitadel 角色 `argocd_users` 將被指派 ArgoCD 角色 `readonly`，授予對 ArgoCD 的唯讀存取權限。

部署您的 ArgoCD configmaps。ArgoCD 和 Zitadel 現在應該已正確設定，允許使用者使用 Zitadel 登入 ArgoCD。

## 測試設定

前往您的 ArgoCD 執行個體。您現在應該會在通常的使用者名稱/密碼登入上方看到 **使用 ZITADEL 登入** 按鈕。

![Zitadel ArgoCD 登入](../../assets/zitadel-argocd-login.png "Zitadel ArgoCD 登入")

使用您的 Zitadel 使用者登入後，前往 **使用者資訊**。如果一切設定正確，您現在應該會看到 `argocd_administrators` 群組，如下所示。

![Zitadel ArgoCD 使用者資訊](../../assets/zitadel-argocd-user-info.png "Zitadel ArgoCD 使用者資訊")
