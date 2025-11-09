# Auth0

## 使用者定義

在 Auth0 中定義使用者已超出本指南的範圍。請直接在 Auth0 資料庫中新增使用者、使用企業註冊表或「社交登入」。
*注意*：除非您透過設定限制存取，否則所有使用者都可以存取所有 Auth0 定義的應用程式 - 如果 argo 公開在網際網路上，請記住這一點，否則任何人都可以登入。

## 向 Auth0 註冊應用程式

請遵循 [註冊應用程式](https://auth0.com/docs/dashboard/guides/applications/register-app-spa) 的說明，在 Auth0 中建立 argocd 應用程式。在應用程式定義中：

*   記下 _clientId_ 和 _clientSecret_ 的值。
*   將登入 URL 註冊為 https://your.argoingress.address/login
*   將允許的回呼 URL 設定為 https://your.argoingress.address/auth/callback
*   在連線下，選取您要與 argo 搭配使用的使用者註冊表。

任何其他設定對於驗證的運作並非必要。

## 向 Auth0 新增授權規則

請遵循 Auth0 [授權指南](https://auth0.com/docs/authorization) 來設定授權。
這裡要注意的重點是，群組成員資格是一個非標準的宣告，因此需要放在 FQDN 宣告名稱下，例如 `http://your.domain/groups`。

## 設定 argo

### 為 ArgoCD 設定 OIDC

`kubectl edit configmap argocd-cm`

```
...
data:
  application.instanceLabelKey: argocd.argoproj.io/instance
  url: https://your.argoingress.address
  oidc.config: |
    name: Auth0
    issuer: https://<yourtenant>.<eu|us>.auth0.com/
    clientID: <theClientId>
    clientSecret: <theClientSecret>
    domain_hint: <theDomainHint>
    requestedScopes:
    - openid
    - profile
    - email
    # not strictly necessary - but good practice:
    # 並非絕對必要 - 但建議這麼做：
    - 'http://your.domain/groups'
...
```

### 為 ArgoCD 設定 RBAC

`kubectl edit configmap argocd-rbac-cm` (或使用 helm 值)。
```
...
data:
  policy.csv: |
    # let members with group someProjectGroup handle apps in someProject
    # 讓群組 someProjectGroup 的成員處理 someProject 中的應用程式
    # this can also be defined in the UI in the group-definition to avoid doing it there in the configmap
    # 這也可以在 UI 的群組定義中定義，以避免在 configmap 中進行設定
    p, someProjectGroup, applications, *, someProject/*, allow
    # let the group membership argocd-admins from OIDC become role:admin - needs to go into the configmap
    # 讓來自 OIDC 的群組成員 argocd-admins 成為 role:admin - 需要放入 configmap 中
    g, argocd-global-admins, role:admin
  policy.default: role:readonly
  # essential to get argo to use groups for RBAC:
  # 讓 argo 使用群組進行 RBAC 的必要設定：
  scopes: '[http://your.domain/groups, email]'
...
```

<br>

> [!NOTE]
> **儲存客戶端密鑰**
>
> 有關安全且正確地儲存您的 clientSecret 的詳細資訊，可以在 [使用者管理總覽頁面](index.md#sensitive-data-and-sso-client-secrets) 上找到。
