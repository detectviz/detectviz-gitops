# OneLogin

> [!NOTE]
> **您正在使用這個 IdP 嗎？請貢獻！**
>
> 如果您正在使用這個 IdP，請考慮為本文件[貢獻](../../developer-guide/docs-site.md)。

<!-- markdownlint-disable MD033 -->
<div style="text-align:center"><img src="../../../assets/argo.png" /></div>
<!-- markdownlint-enable MD033 -->

# 整合 OneLogin 和 ArgoCD

這些說明將引導您完成讓 ArgoCD 應用程式使用 OneLogin 進行驗證的整個過程。您將在 OneLogin 中建立一個自訂 OIDC 應用程式，並設定 ArgoCD 使用 OneLogin 進行驗證，並使用 OneLogin 中設定的使用者角色來決定 Argo 中的權限。

## 建立和設定 OneLogin 應用程式

為了讓您的 ArgoCD 應用程式與 OneLogin 通訊，您首先需要在 OneLogin 端建立和設定 OIDC 應用程式。

### 建立 OIDC 應用程式

要建立應用程式，請執行以下操作：

1. 導覽至您的 OneLogin 入口網站，然後是「管理」>「應用程式」。
2. 按一下「新增應用程式」。
3. 在搜尋欄位中搜尋「OpenID Connect」。
4. 選取要建立的「OpenId Connect (OIDC)」應用程式。
5. 更新「顯示名稱」欄位（可以是「ArgoCD (生產)」之類的名稱）。
6. 按一下「儲存」。

### 設定 OIDC 應用程式設定

現在應用程式已建立，您可以設定應用程式的設定。

#### 設定索引標籤

如下所示更新「設定」設定：

1. 選取左側的「設定」索引標籤。
2. 將「登入網址」欄位設定為 https://argocd.myproject.com/auth/login，並將主機名稱替換為您自己的。
3. 將「重新導向網址」欄位設定為 https://argocd.myproject.com/auth/callback，並將主機名稱替換為您自己的。
4. 按一下「儲存」。

> [!NOTE]
> 在設定上述欄位之前，OneLogin 可能不允許您儲存任何其他欄位。

#### 資訊索引標籤

您可以在此處更新顯示在 OneLogin 入口網站中的「顯示名稱」、「說明」、「備註」或顯示圖片。

#### 參數索引標籤

此索引標籤控制傳送至 Argo 權杖中的資訊。預設情況下，它將包含一個 Groups 欄位，且「憑證為」設定為「由管理員設定」。將「憑證為」保留為預設值。

Groups 欄位的值如何設定將根據您的需求而有所不同，但若要使用 OneLogin 使用者角色來取得 ArgoCD 權限，請如下設定 Groups 欄位的值：

1. 按一下「群組」。此時會出現一個強制回應視窗。
2. 將「如果未選取值則預設為」欄位設定為「使用者角色」。
3. 將其下方的轉換欄位設定為「分號分隔輸入」。
4. 按一下「儲存」。

當使用者嘗試使用 OneLogin 登入 Argo 時，OneLogin 中的使用者角色（例如，Manager、ProductTeam 和 TestEngineering）將包含在權杖的 Groups 欄位中。這些是 Argo 指派權限所需的值。

權杖中的 groups 欄位將類似於以下內容：

```
"groups": [
    "Manager",
    "ProductTeam",
    "TestEngineering",
  ],
```

#### 規則索引標籤

要開始使用，您無需在此處對任何設定進行修改。

#### SSO 索引標籤

此索引標籤包含許多需要放入您的 ArgoCD 設定檔中的資訊（API 端點、用戶端 ID、用戶端密鑰）。

確認「應用程式類型」設定為「Web」。

確認「權杖端點」設定為「基本」。

#### 存取索引標籤

此索引標籤控制誰可以在 OneLogin 入口網站中看到此應用程式。

選取您希望有權存取此應用程式的角色，然後按一下「儲存」。

#### 使用者索引標籤

此索引標籤顯示有權存取此應用程式的個別使用者（通常是那些在「存取」索引標籤中指定了角色的使用者）。

要開始使用，您無需在此處對任何設定進行修改。

#### 權限索引標籤

此索引標籤顯示哪些 OneLogin 使用者可以設定此應用程式。

要開始使用，您無需在此處對任何設定進行修改。

## 在 ArgoCD 中更新 OIDC 設定

現在已在 OneLogin 中設定 OIDC 應用程式，您可以更新 Argo 設定以與 OneLogin 通訊，並控制透過 OneLogin 進行驗證的使用者的權限。

### 告訴 Argo OneLogin 在哪裡

Argo 需要更新其設定對應 (argocd-cm) 才能與 OneLogin 通訊。請參考以下 yaml：

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  url: https://<argocd.myproject.com>
  oidc.config: |
    name: OneLogin
    issuer: https://<subdomain>.onelogin.com/oidc/2
    clientID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaaaaaaaa
    clientSecret: abcdef123456

    # Optional set of OIDC scopes to request. If omitted, defaults to: ["openid", "profile", "email", "groups"]
    # 請求 OIDC 範圍的可選集合。如果省略，預設為：["openid", "profile", "email", "groups"]
    requestedScopes: ["openid", "profile", "email", "groups"]
```

「url」鍵的值應為您的 Argo 專案的主機名稱。

「clientID」取自 OneLogin 應用程式的 SSO 索引標籤。

「issuer」取自 OneLogin 應用程式的 SSO 索引標籤。它是 issuer API 端點之一。

「clientSecret」值是位於 OneLogin 應用程式 SSO 索引標籤中的用戶端密鑰。

> [!NOTE]
> **如果您在嘗試使用 OneLogin 進行驗證時遇到 `invalid_client` 錯誤，則您的用戶端密鑰可能不正確。請記住，在先前版本中，`clientSecret` 值必須經過 base64 加密，但現在不再需要。**

### 為經 OneLogin 驗證的使用者設定權限

ArgoCD 中的權限可以使用權杖中 Groups 欄位傳遞的 OneLogin 角色名稱進行設定。請參考 argocd-rbac-cm.yaml 中的以下 yaml：

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    p, role:org-admin, applications, *, */*, allow
    p, role:org-admin, clusters, get, *, allow
    p, role:org-admin, repositories, get, *, allow
    p, role:org-admin, repositories, create, *, allow
    p, role:org-admin, repositories, update, *, allow
    p, role:org-admin, repositories, delete, *, allow

    g, TestEngineering, role:org-admin
```

在 OneLogin 中，具有「TestEngineering」使用者角色的使用者在透過 OneLogin 登入 Argo 時將獲得 ArgoCD 管理員權限。所有其他使用者將獲得唯讀角色。這裡的重點是，「TestEngineering」是透過權杖中的 Group 欄位傳遞的（這是在 OneLogin 的「參數」索引標籤中指定的）。
