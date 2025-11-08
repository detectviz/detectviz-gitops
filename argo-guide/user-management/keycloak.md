# Keycloak
Keycloak 和 ArgoCD 的整合可以透過用戶端驗證和 PKCE 兩種方式進行設定。

如果您需要使用 __argo-cd 命令列__ 進行驗證，則必須選擇 PKCE 方式。

* [使用用戶端驗證的 Keycloak 和 ArgoCD](#keycloak-and-argocd-with-client-authentication)
* [使用 PKCE 的 Keycloak 和 ArgoCD](#keycloak-and-argocd-with-pkce)

## 使用用戶端驗證的 Keycloak 和 ArgoCD

這些說明將引導您完成讓 ArgoCD 應用程式使用 Keycloak 進行驗證的整個過程。

您將在 Keycloak 中建立一個用戶端，並設定 ArgoCD 使用 Keycloak 進行驗證，並使用 Keycloak 中設定的群組
來決定 Argo 中的權限。

### 在 Keycloak 中建立新用戶端

首先，我們需要設定一個新的用戶端。

首先登入您的 Keycloak 伺服器，選擇您要使用的領域（預設為 `master`）
然後前往 __用戶端__ 並點擊頂部的 __建立用戶端__ 按鈕。

![Keycloak 新增用戶端](../../assets/keycloak-add-client.png "Keycloak 新增用戶端")

啟用 __用戶端驗證__。

![Keycloak 新增用戶端步驟 2](../../assets/keycloak-add-client_2.png "Keycloak 新增用戶端步驟 2")

透過將 __根 URL__、__Web 來源__、__管理員 URL__ 設定為主機名稱 (https://{hostname}) 來設定用戶端。

您也可以將 __首頁 URL__ 設定為 _/applications_ 路徑，並將 __有效的登出後重新導向 URI__ 設定為 "https://{hostname}/applications"。

有效的重新導向 URI 應設定為 https://{hostname}/auth/callback（您也可以為了測試/開發目的設定較不安全的 https://{hostname}/*，
但不建議在生產環境中使用）。

![Keycloak 設定用戶端](../../assets/keycloak-configure-client.png "Keycloak 設定用戶端")

請務必點擊 __儲存__。

應該會有一個名為 __憑證__ 的標籤。您可以複製我們將在 ArgoCD 設定中使用的用戶端密鑰。

![Keycloak 用戶端密鑰](../../assets/keycloak-client-secret.png "Keycloak 用戶端密鑰")

### 設定 ArgoCD OIDC

讓我們開始將您先前產生的用戶端密鑰儲存在 argocd secret _argocd-secret_ 中。

您可以使用先前複製的值來修補它：
```bash
kubectl -n argo-cd patch secret argocd-secret --patch='{"stringData": { "oidc.keycloak.clientSecret": "<請替換為您的用戶端密鑰>" }}'
```

現在我們可以設定 config map 並新增 oidc 設定以啟用我們的 keycloak 驗證。
您可以使用 `$ kubectl edit configmap argocd-cm`。

您的 ConfigMap 應如下所示：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  url: https://argocd.example.com
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.example.com/realms/master
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

請確保：

- __issuer__ 以正確的領域結尾（在此範例中為 _master_）
- 在 17 版之前的 Keycloak 版本中，__issuer__ 的 URL 必須包含 /auth（在此範例中為 /auth/realms/master）
- __clientID__ 設定為您在 Keycloak 中設定的用戶端 ID
- __clientSecret__ 指向您在 _argocd-secret_ Secret 中建立的正確金鑰
- 如果未將 _groups_ 宣告新增至預設範圍，則 __requestedScopes__ 需包含該宣告

## 使用 PKCE 的 Keycloak 和 ArgoCD

這些說明將引導您完成讓 ArgoCD 應用程式使用 Keycloak 進行驗證的整個過程。

您將在 Keycloak 中建立一個用戶端，並設定 ArgoCD 使用 Keycloak 進行驗證，並使用 Keycloak 中設定的群組
來決定 Argo 中的權限。

您還將能夠使用 argo-cd 命令列進行驗證。

### 在 Keycloak 中建立新用戶端

首先，我們需要設定一個新的用戶端。

首先登入您的 Keycloak 伺服器，選擇您要使用的領域（預設為 `master`）
然後前往 __用戶端__ 並點擊頂部的 __建立用戶端__ 按鈕。

![Keycloak 新增用戶端](../../assets/keycloak-add-client.png "Keycloak 新增用戶端")

保留預設值。

![Keycloak 新增用戶端步驟 2](../../assets/keycloak-add-client-pkce_2.png "Keycloak 新增用戶端步驟 2")

透過將 __根 URL__、__Web 來源__、__管理員 URL__ 設定為主機名稱 (https://{hostname}) 來設定用戶端。

您也可以將 __首頁 URL__ 設定為 _/applications_ 路徑，並將 __有效的登出後重新導向 URI__ 設定為 "https://{hostname}/applications"。

有效的重新導向 URI 應設定為：
- http://localhost:8085/auth/callback（argo-cd cli 需要，取決于 [--sso-port](../../user-guide/commands/argocd_login.md) 的值）
- https://{hostname}/auth/callback

![Keycloak 設定用戶端](../../assets/keycloak-configure-client-pkce.png "Keycloak 設定用戶端")

請務必點擊 __儲存__。

現在前往名為 __進階__ 的標籤，找到名為 __代碼交換的證明金鑰代碼挑戰方法__ 的參數，並將其設定為 __S256__

![Keycloak 設定用戶端步驟 2](../../assets/keycloak-configure-client-pkce_2.png "Keycloak 設定用戶端步驟 2")
請務必點擊 __儲存__。

### 設定 ArgoCD OIDC
現在我們可以設定 config map 並新增 oidc 設定以啟用我們的 keycloak 驗證。
您可以使用 `$ kubectl edit configmap argocd-cm`。

您的 ConfigMap 應如下所示：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  url: https://argocd.example.com
  oidc.config: |
    name: Keycloak
    issuer: https://keycloak.example.com/realms/master
    clientID: argocd
    enablePKCEAuthentication: true
    requestedScopes: ["openid", "profile", "email", "groups"]
```

請確保：

- __issuer__ 以正確的領域結尾（在此範例中為 _master_）
- 在 17 版之前的 Keycloak 版本中，__issuer__ 的 URL 必須包含 /auth（在此範例中為 /auth/realms/master）
- __clientID__ 設定為您在 Keycloak 中設定的用戶端 ID
- __enablePKCEAuthentication__ 必須設定為 true 才能啟用 ArgoCD 與 PKCE 的正確行為
- 如果未將 _groups_ 宣告新增至預設範圍，則 __requestedScopes__ 需包含該宣告

## 設定群組宣告

為了讓 ArgoCD 提供使用者所在的群組，我們需要設定一個可以包含在驗證權杖中的群組宣告。

為此，我們將首先建立一個名為 _groups_ 的新 __用戶端範圍__。

![Keycloak 新增範圍](../../assets/keycloak-add-scope.png "Keycloak 新增範圍")

建立用戶端範圍後，您現在可以新增一個權杖對應器，當用戶端請求群組範圍時，該對應器會將群組宣告新增至權杖中。

在「對應器」標籤中，點擊「設定新對應器」並選擇 __群組成員資格__。

請務必將 __名稱__ 和 __權杖宣告名稱__ 都設定為 _groups_。同時停用「完整群組路徑」。

![Keycloak 群組對應器](../../assets/keycloak-groups-mapper.png "Keycloak 群組對應器")

我們現在可以設定用戶端以提供 _groups_ 範圍。

返回我們之前建立的用戶端，然後前往「用戶端範圍」標籤。

點擊「新增用戶端範圍」，選擇 _groups_ 範圍，並將其新增至 __預設__ 或 __可選__ 用戶端範圍。

如果將其放在可選類別中，您需要確保 ArgoCD 在其 OIDC 設定中請求該範圍。
由於我們總是需要群組資訊，我建議
使用預設類別。

![Keycloak 用戶端範圍](../../assets/keycloak-client-scope.png "Keycloak 用戶端範圍")

建立一個名為 _ArgoCDAdmins_ 的群組，並讓您目前的使用者加入該群組。

![Keycloak 使用者群組](../../assets/keycloak-user-group.png "Keycloak 使用者群組")

## 設定 ArgoCD 策略

現在我們有了提供群組的驗證，我們希望對這些群組套用策略。
我們可以使用 `$ kubectl edit configmap argocd-rbac-cm` 來修改 _argocd-rbac-cm_ ConfigMap。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
data:
  policy.csv: |
    g, ArgoCDAdmins, role:admin
```

在此範例中，我們將 _role:admin_ 角色授予 _ArgoCDAdmins_ 群組中的所有使用者。

## 登入

您現在可以使用我們新的 Keycloak OIDC 驗證登入：

![Keycloak ArgoCD 登入](../../assets/keycloak-login.png "Keycloak ArgoCD 登入")

如果您使用了 PKCE 方法，您也可以使用命令列進行驗證：
```bash
argocd login argocd.example.com --sso --grpc-web
```

argocd cli 將開始在 localhost:8085 上監聽，並開啟您的網頁瀏覽器以允許您使用 Keycloak 進行驗證。

完成後，您應該會看到

![驗證成功！](../../assets/keycloak-authentication-successful.png "驗證成功！")

## 疑難排解
如果 ArgoCD 驗證返回 401 或登入嘗試導致循環，請重新啟動 argocd-server pod。
```
kubectl rollout restart deployment argocd-server -n argocd
```

如果您從用戶端驗證遷移到 PKCE，您可能會遇到以下錯誤 `invalid_request: Missing parameter: code_challenge_method`。

這可能是重新導向問題，請嘗試在私密瀏覽中或清除瀏覽器 cookie。
