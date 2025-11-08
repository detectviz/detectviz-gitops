# OpenUnison

## 整合 OpenUnison 與 ArgoCD

這些說明將引導您完成整合 OpenUnison 與 ArgoCD 的步驟，以支援單一登入並在您的 OpenUnison 入口網站中新增「徽章」，為 Kubernetes 和 ArgoCD 建立單一存取點。這些說明假設您將同時使用 ArgoCD 的網頁介面和命令列介面。這些說明假設您正在執行 [OpenUnison 1.0.20+](https://www.tremolosecurity.com/products/orchestra-for-kubernetes)。

![帶有 ArgoCD 的 OpenUnison 入口網站](../../assets/openunison-portal.png)

## 建立 OpenUnison 信任

更新下方的 `Trust` 物件，並將其新增至 `openunison` 命名空間。您唯一需要做的變更是將 `argocd.apps.domain.com` 替換為您的 ArgoCD URL 的主機名稱。需要 localhost URL 才能讓 cli 正常運作。ArgoCD 不使用用戶端密鑰，因為 cli 無法與之搭配使用。

```
apiVersion: openunison.tremolo.io/v1
kind: Trust
metadata:
  name: argocd
  namespace: openunison
spec:
  accessTokenSkewMillis: 120000
  accessTokenTimeToLive: 1200000
  authChainName: login-service
  clientId: argocd
  codeLastMileKeyName: lastmile-oidc
  codeTokenSkewMilis: 60000
  publicEndpoint: true
  redirectURI:
  - https://argocd.apps.domain.com/auth/callback
  - http://localhost:8085/auth/callback
  signedUserInfo: true
  verifyRedirect: true
```

## 在 OpenUnison 中建立「徽章」

下載 [`PortalUrl` 物件的 yaml](../../assets/openunison-argocd-url.yaml)，並更新 `url` 以指向您的 ArgoCD 執行個體。將更新後的 `PortalUrl` 新增至您叢集的 `openunison` 命名空間。

## 在 ArgoCD 中設定 SSO

接下來，更新 `argocd` 命名空間中的 `argocd-cm` ConfigMap。如下所示新增 `url` 和 `oidc.config` 區段。使用 OpenUnison 的主機更新 `issuer`。

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  url: https://argocd.apps.domain.com
  oidc.config: |-
    name: OpenUnison
    issuer: https://k8sou.apps.192-168-2-144.nip.io/auth/idp/k8sIdp
    clientID: argocd
    requestedScopes: ["openid", "profile", "email", "groups"]
```

如果一切順利，請登入您的 OpenUnison 執行個體，應該會有一個 ArgoCD 的徽章。按一下該徽章會在一個新視窗中開啟 ArgoCD，並且已經登入！此外，啟動 argocd cli 工具將會啟動瀏覽器以登入 OpenUnison。

## 設定 ArgoCD 策略

OpenUnison 將群組放在 `groups` 宣告中。當您按一下 ArgoCD 入口網站的使用者資訊區段時，這些宣告將會顯示。如果您使用的是 LDAP、Active Directory 或 Active Directory Federation Services，群組將以完整的辨別名稱 (DN) 提供給 ArgoCD。由於 DN 包含逗號 (`,`)，您需要在您的策略中引用群組名稱。例如，若要將 `CN=k8s_login_cluster_admins,CN=Users,DC=ent2k12,DC=domain,DC=com` 指派為管理員，其設定如下：

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, "CN=k8s_login_cluster_admins,CN=Users,DC=ent2k12,DC=domain,DC=com", role:admin
```
