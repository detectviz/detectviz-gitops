# 任何命名空間中的 ApplicationSet

> [!WARNING]
> **Beta 功能 (自 v2.8.0 起)**
>
> 此功能處於 [Beta](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#beta) 階段。
> 它通常被認為是穩定的，但可能存在未處理的邊緣案例。

> [!WARNING]
> 在啟用此功能之前，請仔細閱讀本文件。不當的組態可能會導致潛在的安全問題。

## 簡介

自 2.8 版起，Argo CD 支援在控制平面命名空間（通常是 `argocd`）以外的命名空間中管理 `ApplicationSet` 資源，但此功能必須明確啟用並適當設定。

Argo CD 管理員可以定義一組特定的命名空間，其中可以建立、更新和協調 `ApplicationSet` 資源。

由於 ApplicationSet 產生的應用程式與 ApplicationSet 本身在相同的命名空間中產生，因此這與[任何命名空間中的應用程式](../app-any-namespace.md) 結合使用。

## 先決條件

### 已設定任何命名空間中的應用程式

此功能需要啟用[任何命名空間中的應用程式](../app-any-namespace.md) 功能。命名空間清單必須相同。

### 叢集範圍的 Argo CD 安裝

只有當您的 Argo CD ApplicationSet 控制器安裝為叢集範圍的執行個體時，才能啟用和使用此功能，因此它具有在叢集範圍內列出和操作資源的權限。它**不適用於**以命名空間範圍模式安裝的 Argo CD。

### SCM 提供者密鑰注意事項

透過允許任何命名空間中的 ApplicationSet，您必須意識到可以使用 `scmProvider` 或 `pullRequest` 產生器洩漏任何密鑰。這意味著如果 ApplicationSet 控制器設定為允許命名空間 `appNs`，並且允許某些使用者在 `appNs` 命名空間中建立
ApplicationSet，則使用者可以如下所述將惡意 Pod 安裝到 `appNs` 命名空間中
並間接讀出密鑰的內容，從而洩漏密鑰值。

以下是一個範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
  namespace: appNs
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - scmProvider:
      gitea:
        # 要掃描的 Gitea 擁有者。
        owner: myorg
        # 透過此惡意設定，使用者可以將所有請求傳送到將記錄傳入請求（包括帶有權杖的標頭）的 Pod
        api: http://my-service.appNs.svc.cluster.local
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描預設分支。預設為 false。
        allBranches: true
        # 透過變更此權杖參考，使用者可以洩漏任何密鑰
        tokenRef:
          secretName: gitea-token
          key: token
  template:
```

為了防止上述情況，管理員必須透過將環境變數 `ARGOCD_APPLICATIONSET_CONTROLLER_ALLOWED_SCM_PROVIDERS` 設定為 argocd-cmd-params-cm `applicationsetcontroller.allowed.scm.providers` 來限制允許的 SCM 提供者（範例：`https://git.mydomain.com/,https://gitlab.mydomain.com/`）的 url。如果使用其他 url，它將被 applicationset 控制器拒絕。

例如：
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  applicationsetcontroller.allowed.scm.providers: https://git.mydomain.com/,https://gitlab.mydomain.com/
```

> [!NOTE]
> 請注意，`ApplicationSet` 的 `api` 欄位中使用的 url 必須與管理員宣告的 url（包括協定）相符

> [!WARNING]
> 允許清單僅適用於使用者可以為其設定自訂 `api` 的 SCM 提供者。如果 SCM 或 PR
> 產生器不接受自訂 API URL，則該提供者會被隱含允許。

如果您不打算允許使用者使用 SCM 或 PR 產生器，可以透過將環境變數 `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_SCM_PROVIDERS` 設定為 argocd-cmd-params-cm `applicationsetcontroller.enable.scm.providers` 為 `false` 來完全停用它們。

#### `tokenRef` 限制

**強烈建議**啟用 SCM 提供者密鑰限制，以避免任何密鑰洩漏。此
建議即使在停用 AppSets-in-any-namespace 時也適用，但在啟用時尤其重要，
因為非 Argo 管理員可能會嘗試從 AppSet
`tokenRef` 參考 `argocd` 命名空間中超出範圍的密鑰。

啟用此模式後，參考的密鑰必須具有標籤 `argocd.argoproj.io/secret-type`，其值為
`scm-creds`。

若要啟用此模式，請在
`argocd-application-controller` 部署中將 `ARGOCD_APPLICATIONSET_CONTROLLER_TOKENREF_STRICT_MODE` 環境變數設定為 `true`。您可以透過將以下內容新增到您的 `argocd-cmd-paramscm`
ConfigMap 中來執行此操作：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
    applicationsetcontroller.tokenref.strict.mode: "true"
```

### 總覽

為了讓 ApplicationSet 在 Argo CD 的控制平面命名空間之外進行管理和協調，必須滿足兩個先決條件：

1. 必須使用環境變數 `ARGOCD_APPLICATIONSET_CONTROLLER_NAMESPACES` 或參數 `--applicationset-namespaces` 明確設定 `argocd-applicationset-controller` 可以從中取得 `ApplicationSets` 的命名空間清單。
2. 啟用的命名空間必須完全被[任何命名空間中的應用程式](../app-any-namespace.md) 涵蓋，否則在允許的應用程式命名空間之外產生的應用程式將不會被協調。

可以透過將環境變數 `ARGOCD_APPLICATIONSET_CONTROLLER_NAMESPACES` 設定為 argocd-cmd-params-cm `applicationsetcontroller.namespaces` 來實現

不同命名空間中的 `ApplicationSets` 可以像以前在 `argocd` 命名空間中的任何其他 `ApplicationSet` 一樣建立和管理，可以透過宣告方式或透過 Argo CD API（例如使用 CLI、網頁 UI、REST API 等）。

### 重新設定 Argo CD 以允許某些命名空間

#### 變更工作負載啟動參數

為了啟用此功能，Argo CD 管理員必須重新設定 `argocd-applicationset-controller` 工作負載，以將 `--applicationset-namespaces` 參數新增到容器的啟動命令中。

### 安全地建立專案範本

由於[任何命名空間中的應用程式](../app-any-namespace.md) 是先決條件，因此可以安全地建立專案範本。

讓我們以兩個團隊和一個基礎設施專案為例：

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
  name: infra-project
  namespace: argocd
spec:
  destinations:
    - namespace: '*'
```

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
  name: team-one-project
  namespace: argocd
spec:
  sourceNamespaces:
  - team-one-cd
```

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
  name: team-two-project
  namespace: argocd
spec:
  sourceNamespaces:
  - team-two-cd
```

建立以下 `ApplicationSet` 會產生兩個應用程式 `infra-escalation` 和 `team-two-escalation`。兩者都將被拒絕，因為它們在 `argocd` 命名空間之外，因此將檢查 `sourceNamespaces`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: team-one-product-one
  namespace: team-one-cd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    list:
    - name: infra
      project: infra-project
    - name: team-two
      project: team-two-project
  template:
    metadata:
      name: '{{.name}}-escalation'
    spec:
      project: "{{.project}}"
```

### ApplicationSet 名稱

對於 CLI，applicationSets 現在以 `<namespace>/<name>` 的格式來參考和顯示。

為了向後相容，如果 ApplicationSet 的命名空間是控制平面的命名空間（即 `argocd`），則在參考 applicationSet 名稱時可以省略 `<namespace>`。例如，應用程式名稱 `argocd/someappset` 和 `someappset` 在語意上是相同的，並且在 CLI 和 UI 中參考相同的應用程式。

### Applicationsets RBAC

應用程式物件的 RBAC 語法已從 `<project>/<applicationset>` 變更為 `<project>/<namespace>/<applicationset>`，以因應根據要管理的應用程式的來源命名空間限制存取的需求。

為了向後相容，`argocd` 命名空間中的應用程式仍然可以在 RBAC 策略規則中被參考為 `<project>/<applicationset>`。

萬用字元尚未對專案和 applicationSet 命名空間做出任何區分。例如，以下 RBAC 規則將匹配屬於專案 `foo` 的任何應用程式，無論它是在哪個命名空間中建立的：

```
p, somerole, applicationsets, get, foo/*, allow
```

如果您希望將存取權限僅授予命名空間 `bar` 中專案為 `foo` 的 `ApplicationSets`，則需要將規則調整如下：

```
p, somerole, applicationsets, get, foo/bar/*, allow
```

## 在其他命名空間中管理 applicationSets

### 使用 CLI

您可以使用所有現有的 Argo CD CLI 指令來管理其他命名空間中的應用程式，就像您使用 CLI 管理控制平面命名空間中的應用程式一樣。

例如，若要擷取命名空間 `bar` 中名為 `foo` 的 `ApplicationSet`，您可以使用以下 CLI 指令：

```shell
argocd appset get foo/bar
```

同樣地，要管理此 applicationSet，請繼續將其參考為 `foo/bar`：

```bash
# 刪除應用程式
argocd appset delete foo/bar
```

建立指令沒有變更，因為它使用檔案。您只需要在 `metadata.namespace` 欄位中新增命名空間即可。

如前所述，對於 Argo CD 的控制平面命名空間中的 applicationSets，您可以從應用程式名稱中省略命名空間。

### 使用 REST API

如果您使用 REST API，則 `ApplicationSet` 的命名空間不能指定為應用程式名稱，並且需要使用選用的 `appNamespace` 查詢參數來指定資源。例如，若要使用命名空間 `bar` 中名為 `foo` 的 `ApplicationSet` 資源，請求將如下所示：

```bash
GET /api/v1/applicationsets/foo?appsetNamespace=bar
```

對於 `POST` 和 `PUT` 等其他操作，`appNamespace` 參數必須是請求負載的一部分。

對於控制平面命名空間中的 `ApplicationSet` 資源，可以省略此參數。

## 叢集密鑰注意事項

透過允許任何命名空間中的 ApplicationSet，您必須意識到可以發現和使用叢集。

範例：

以下將發現所有叢集

```yaml
spec:
  generators:
  - clusters: {} # 自動使用 Argo CD 中定義的所有叢集
```

如果您不希望允許使用者從其他命名空間使用 ApplicationSets 發現所有叢集，您可以考慮在命名空間範圍內部署 ArgoCD 或使用 OPA 規則。
