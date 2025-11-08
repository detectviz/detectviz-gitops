## 專案

專案提供應用程式的邏輯分組，這在 Argo CD 由多個團隊使用時非常有用。專案提供以下功能：

* 限制可部署的內容（受信任的 Git 來源儲存庫）
* 限制應用程式可部署到的位置（目標叢集和命名空間）
* 限制可部署或不可部署的物件種類（例如 RBAC、CRD、DaemonSet、NetworkPolicy 等...）
* 定義專案角色以提供應用程式 RBAC（綁定至 OIDC 群組和/或 JWT 權杖）

### 預設專案

每個應用程式都屬於單一專案。如果未指定，應用程式將屬於 `default` 專案，該專案會自動建立，並且預設允許從任何來源儲存庫部署到任何叢集，以及所有資源種類。初始建立時，其規格設定為最寬鬆的：

```yaml
spec:
  sourceRepos:
  - '*'
  destinations:
  - namespace: '*'
    server: '*'
  clusterResourceWhitelist:
  - group: '*'
    kind: '*'
```

`default` 專案可以修改，但不能刪除。此專案適用於初始測試，但建議建立具有明確來源、目標和資源權限的專用專案。

若要從 `default` 專案中移除所有權限，請將以下資訊清單套用至安裝 Argo CD 的命名空間：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: default
spec:
  sourceRepos: []
  sourceNamespaces: []
  destinations: []
  namespaceResourceBlacklist:
  - group: '*'
    kind: '*'
```

修改 `default` 專案後，任何嘗試使用它的應用程式都將被拒絕，直到您明確將該應用程式移至更寬鬆的專案為止。

### 建立專案

可以建立其他專案，以給予不同團隊對命名空間不同層級的存取權限。以下指令會建立一個新專案 `myproject`，該專案可以將應用程式部署到叢集 `https://kubernetes.default.svc` 的 `mynamespace` 命名空間。允許的 Git 來源儲存庫設定為 `https://github.com/argoproj/argocd-example-apps.git` 儲存庫。

```bash
argocd proj create myproject -d https://kubernetes.default.svc,mynamespace -s https://github.com/argoproj/argocd-example-apps.git
```

### 管理專案

允許的來源 Git 儲存庫使用以下指令進行管理：

```bash
argocd proj add-source <PROJECT> <REPO>
argocd proj remove-source <PROJECT> <REPO>
```

我們也可以對來源進行否定（即_不_使用此儲存庫）。

```bash
argocd proj add-source <PROJECT> !<REPO>
argocd proj remove-source <PROJECT> !<REPO>
```

以宣告方式，我們可以執行以下操作：

```yaml
spec:
  sourceRepos:
    # 不要在 argoproj 中使用測試儲存庫
    - '!ssh://git@GITHUB.com:argoproj/test'
    # 也不要使用 group/ 下的任何 Gitlab 儲存庫
    - '!https://gitlab.com/group/**'
    # 不過任何其他儲存庫都可以
    - '*'
```

如果符合以下條件，則來源儲存庫會被視為有效：

1. _任何_允許的來源規則（即未以 `!` 前綴的規則）允許該來源
2. 且*沒有*拒絕的來源（即以 `!` 前綴的規則）拒絕該來源

請記住，`!*` 是無效規則，因為不允許所有內容是沒有意義的。

允許的目標叢集和命名空間使用以下指令進行管理（對於叢集，請始終提供伺服器，名稱不用於匹配）：

```bash
argocd proj add-destination <PROJECT> <CLUSTER>,<NAMESPACE>
argocd proj remove-destination <PROJECT> <CLUSTER>,<NAMESPACE>
```

與來源一樣，我們也可以對目標進行否定（即安裝在任何地方_除了_）。

```bash
argocd proj add-destination <PROJECT> !<CLUSTER>,!<NAMESPACE>
argocd proj remove-destination <PROJECT> !<CLUSTER>,!<NAMESPACE>
```

以宣告方式，我們可以執行以下操作：

```yaml
spec:
  destinations:
  # 不允許在 `kube-system` 中安裝任何應用程式
  - namespace: '!kube-system'
    server: '*'
  # 或任何 URL 為 `team1-*` 的叢集
  - namespace: '*'
    server: '!https://team1-*'
    # 不過任何其他命名空間或伺服器都可以。
  - namespace: '*'
    server: '*'
```

與來源一樣，如果符合以下條件，則目標會被視為有效：

1. _任何_允許的目標規則（即未以 `!` 前綴的規則）允許該目標
2. 且*沒有*拒絕的目標（即以 `!` 前綴的規則）拒絕該目標

請記住，`!*` 是無效規則，因為不允許所有內容是沒有意義的。

允許的目標 K8s 資源種類使用以下指令進行管理。請注意，命名空間範圍的資源透過拒絕清單進行限制，而叢集範圍的資源透過允許清單進行限制。

```bash
argocd proj allow-cluster-resource <PROJECT> <GROUP> <KIND>
argocd proj allow-namespace-resource <PROJECT> <GROUP> <KIND>
argocd proj deny-cluster-resource <PROJECT> <GROUP> <KIND>
argocd proj deny-namespace-resource <PROJECT> <GROUP> <KIND>
```

### 將應用程式指派給專案

可以使用 `app set` 指令變更應用程式專案。若要變更應用程式的專案，使用者必須具有存取新專案的權限。

```
argocd app set guestbook-default --project myproject
```

## 專案角色

專案包含一個名為角色的功能，可用於確定誰以及可以對與專案相關聯的應用程式執行哪些操作。例如，它可以給予 CI 管線一組受限制的權限，允許對單一應用程式進行同步操作（但不能變更其來源或目標）。

專案可以有多個角色，這些角色可以被授予不同的存取權限。這些權限稱為策略，遵循與 Argo CD 組態中使用的相同 [RBAC 模式](../operator-manual/rbac.md)。它們以策略字串清單的形式儲存在角色中。角色的策略只能授予該角色的存取權限。使用者會根據群組清單與角色相關聯。請考慮以下假設的 AppProject 定義：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: sample-test-project
spec:
  ...
  roles:
  - name: custom-project-role
    description: "custom-project-role" 將套用至 `some-user` 群組。
    groups:
    - some-user
    policies:
    - p, proj:sample-test-project:custom-project-role, applications, *, *, allow
  ...
```

Argo CD 將在授權使用者操作時使用 AppProject 角色中定義的策略。為了確定給定使用者與哪個角色相關聯，它將在執行時期根據角色名稱動態建立群組。上述專案定義將產生以下 Casbin RBAC 規則：

```
    p, proj:sample-test-project:custom-project-role, applications, *, *, allow
    g, some-user, proj:sample-test-project:custom-project-role
```

_註 1_：策略角色的格式必須為 `proj:<project-name>:<role-name>`，否則在 Argo CD 授權過程中將無效，這一點非常重要。

_註 2_：上述範例使用 `applications` 作為策略定義的資源。但是，也可以使用其他類型的資源：`applicationsets`、`repositories`、`clusters`、`logs` 和 `exec`。有關這些資源的更多詳細資訊，請參閱 [RBAC 文件](../operator-manual/rbac.md)。

為了在專案中建立角色並向角色新增策略，使用者需要更新專案的權限。可以使用以下指令來管理角色。

```bash
argocd proj role list
argocd proj role get
argocd proj role create
argocd proj role delete
argocd proj role add-policy
argocd proj role remove-policy
```

專案角色本身在沒有產生與該角色關聯的權杖的情況下是沒有用的。Argo CD 支援 JWT 權杖作為向角色進行身份驗證的方式。由於 JWT 權杖與角色的策略相關聯，因此對角色策略的任何變更都將立即對該 JWT 權杖生效。

以下指令用於管理 JWT 權杖。

```bash
argocd proj role create-token PROJECT ROLE-NAME
argocd proj role delete-token PROJECT ROLE-NAME ISSUED-AT
```

由於 JWT 權杖未儲存在 Argo CD 中，因此只能在建立時擷取。使用者可以在 cli 中利用它們，方法是使用 `--auth-token` 旗標傳遞它們，或設定 ARGOCD_AUTH_TOKEN 環境變數。JWT 權杖可以使用，直到它們過期或被撤銷。JWT 權杖可以在有或沒有到期日的情況下建立。預設情況下，cli 建立的權杖沒有到期日。即使權杖尚未過期，如果權杖已被撤銷，也無法使用。

以下是利用 JWT 權杖存取 guestbook 應用程式的範例。它假設使用者已經有一個名為 myproject 的專案和一個名為 guestbook-default 的應用程式。

```bash
PROJ=myproject
APP=guestbook-default
ROLE=get-role
argocd proj role create $PROJ $ROLE
argocd proj role create-token $PROJ $ROLE -e 10m
JWT=<value from command above>
argocd proj role list $PROJ
argocd proj role get $PROJ $ROLE

# 此指令將會失敗，因為與專案角色關聯的 JWT 權杖沒有允許存取應用程式的策略
argocd app get $APP --auth-token $JWT
# 新增策略以授予新角色對應用程式的存取權限
argocd proj role add-policy $PROJ $ROLE --action get --permission allow --object $APP
argocd app get $APP --auth-token $JWT

# 移除我們新增的策略並新增一個帶有萬用字元的策略。
argocd proj role remove-policy $PROJ $ROLE -a get -o $APP
argocd proj role add-policy $PROJ $ROLE -a get --permission allow -o '*'
# 萬用字元允許我們由於萬用字元而存取應用程式。
argocd app get $APP --auth-token $JWT
argocd proj role get $PROJ $ROLE


argocd proj role get $PROJ $ROLE
# 撤銷 JWT 權杖
argocd proj role delete-token $PROJ $ROLE <id field from the last command>
# 這將會失敗，因為 JWT 權杖已從專案角色中刪除。
argocd app get $APP --auth-token $JWT
```

## 使用專案設定 RBAC

專案角色允許設定範圍限定於專案的 RBAC 規則。以下範例專案提供對 `my-oidc-group` 群組的任何成員的專案應用程式的唯讀權限。

*AppProject 範例：*

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
  namespace: argocd
spec:
  roles:
  # 提供對專案中所有應用程式的唯讀存取權限的角色
  - name: read-only
    description: 對 my-project 的唯讀權限
    policies:
    - p, proj:my-project:read-only, applications, get, my-project/*, allow
    groups:
    - my-oidc-group
```

您可以使用 `argocd proj role` CLI 指令或使用者介面中的專案詳細資料頁面來設定策略。
請注意，每個專案角色策略規則都必須僅限定於該專案。如果您想設定跨專案 RBAC 規則，請使用 [RBAC](../operator-manual/rbac.md) 文件中描述的 `argocd-rbac-cm` ConfigMap。

## 設定全域專案 (v1.8)

可以設定全域專案，以提供其他專案可以繼承的組態。

與 `argocd-cm` ConfigMap 中指定的 `matchExpressions` 相符的專案，會從全域專案繼承以下欄位：

* namespaceResourceBlacklist
* namespaceResourceWhitelist
* clusterResourceBlacklist
* clusterResourceWhitelist
* SyncWindows
* SourceRepos
* Destinations

在 `argocd-cm` ConfigMap 中設定全域專案：
```yaml
data:
  globalProjects: |-
    - labelSelector:
        matchExpressions:
          - key: opt
            operator: In
            values:
              - prod
      projectName: proj-global-test
kind: ConfigMap
```

您可以使用的有效運算子為：In、NotIn、Exists、DoesNotExist、Gt 和 Lt。

projectName: `proj-global-test` 應替換為您自己的全域專案名稱。

## 專案範圍的儲存庫和叢集

通常，Argo CD 管理員會建立一個專案，並預先決定它定義了哪些叢集和 Git 儲存庫。然而，這在開發人員希望在專案初次建立後新增儲存庫或叢集的情況下會產生問題。這會迫使開發人員再次聯繫其 Argo CD 管理員以更新專案定義。

可以為開發人員提供一個自助服務流程，以便他們可以在專案初次建立後自行在專案中新增儲存庫和/或叢集。

為此，Argo CD 支援專案範圍的儲存庫和叢集。

若要開始此流程，Argo CD 管理員必須設定 RBAC 安全性以允許此自助服務行為。
例如，若要允許使用者新增專案範圍的儲存庫，管理員必須新增以下 RBAC 規則：

```
p, proj:my-project:admin, repositories, create, my-project/*, allow
p, proj:my-project:admin, repositories, delete, my-project/*, allow
p, proj:my-project:admin, repositories, update, my-project/*, allow
```

這提供了額外的靈活性，以便管理員可以擁有更嚴格的規則。例如：

```
p, proj:my-project:admin, repositories, update, my-project/https://github.example.com/*, allow
```

一旦設定了適當的 RBAC 規則，開發人員就可以建立自己的 Git 儲存庫，並（假設他們有正確的憑證）可以從 UI 或 CLI 將它們新增到現有專案中。
使用者介面和 CLI 都可以選擇性地指定專案。如果指定了專案，則相應的叢集/儲存庫會被視為專案範圍：

```argocd repo add --name stable https://charts.helm.sh/stable --type helm --project my-project```

對於宣告式設定，儲存庫和叢集都儲存為 Kubernetes Secrets，因此會使用一個新欄位來表示此資源是專案範圍的：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-example-apps
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  project: my-project1                                     # 專案範圍
  name: argocd-example-apps
  url: https://github.com/argoproj/argocd-example-apps.git
  username: ****
  password: ****
```

> [!WARNING]
> 請記住，在使用專案範圍的儲存庫時，只有具有相符專案名稱的應用程式或應用程式集才能使用它。當使用具有也使用範本 `project` 的 Git 產生器的應用程式集（即它包含 `{{ ... }}`）時，只有非範圍儲存庫才能與應用程式集一起使用（即未設定 `project` 的儲存庫）。

以上所有範例都與 Git 儲存庫有關，但相同的原則也適用於叢集。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mycluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: mycluster.example.com
  project: my-project1 # 專案範圍
  server: https://mycluster.example.com
  config: |
    {
      "bearerToken": "<authentication token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64 encoded certificate>"
      }
    }
```

使用專案範圍的叢集，我們還可以限制專案僅允許其目標屬於同一專案的應用程式。預設行為允許將應用程式安裝到不屬於同一專案的叢集上，如下例所示：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: "some-ns"
spec:
  destination:
    # 此目標實際上可能不是屬於 `foo-project` 的叢集
    server: https://some-k8s-server/
    namespace: "some-ns"
  project: foo-project
```

若要防止此行為，我們可以在專案上設定 `permitOnlyProjectScopedClusters` 屬性。

```yaml
spec:
  permitOnlyProjectScopedClusters: true
```

設定此屬性後，上述應用程式將不再允許同步到任何不屬於同一專案的叢集。
