# 任何命名空間中的應用程式

> [!WARNING]
> 在啟用此功能之前，請仔細閱讀本文件。不當的設定可能會導致潛在的安全性問題。

## 簡介

自 2.5 版起，Argo CD 支援在控制平面命名空間（通常是 `argocd`）以外的命名空間中管理 `Application` 資源，但此功能必須明確啟用並適當設定。

Argo CD 管理員可以定義一組特定的命名空間，其中可以建立、更新和協調 `Application` 資源。然而，這些額外命名空間中的應用程式將只被允許使用某些 `AppProjects`，如 Argo CD 管理員所設定。這使得普通的 Argo CD 使用者（例如應用程式團隊）能夠使用諸如 `Application` 資源的宣告式管理、實作 app-of-apps 等模式，而不會因使用超出授予應用程式團隊權限的其他 `AppProjects` 而導致權限提升的風險。

Argo CD 管理員需要執行一些手動步驟才能啟用此功能。

採用任何命名空間中的應用程式的另一個優點是，允許終端使用者在執行 Argo CD 應用程式的命名空間中為其 Argo CD 應用程式設定通知。有關更多資訊，請參閱通知[基於命名空間的設定](notifications/index.md#namespace-based-configuration)頁面。

## 先決條件

### 叢集範圍的 Argo CD 安裝

此功能只能在您的 Argo CD 安裝為叢集範圍的實例時啟用和使用，因此它具有在叢集範圍內列出和操作資源的權限。它不適用於以命名空間範圍模式安裝的 Argo CD。

### 切換資源追蹤方法

此外，雖然技術上並非必要，但強烈建議您將應用程式追蹤方法從預設的 `label` 設定切換為 `annotation` 或 `annotation+label`。其理由是，應用程式名稱將是命名空間名稱和 `Application` 名稱的組合，這很容易超過標籤值 63 個字元的長度限制。註解的長度限制要大得多。

要啟用基於註解的資源追蹤，請參閱有關[資源追蹤方法](../../user-guide/resource_tracking/)的文件。

## 實作細節

### 概覽

為了讓應用程式能夠在 Argo CD 的控制平面命名空間之外進行管理和協調，必須滿足兩個先決條件：

1.  必須使用 `argocd-application-controller` 和 `argocd-server` 工作負載的 `--application-namespaces` 參數明確啟用 `Application` 的命名空間。此參數控制 Argo CD 將被允許從中取得 `Application` 資源的命名空間列表。任何未在此處設定的命名空間都不能從任何 `AppProject` 中使用。
2.  `Application` 的 `.spec.project` 欄位引用的 `AppProject` 必須在其 `.spec.sourceNamespaces` 欄位中列出該命名空間。此設定將決定 `Application` 是否可以使用某個 `AppProject`。如果 `Application` 指定了一個不被允許的 `AppProject`，Argo CD 將拒絕處理此 `Application`。如上所述，`.spec.sourceNamespaces` 欄位中設定的任何命名空間也必須在全域啟用。

不同命名空間中的 `Applications` 可以像以前在 `argocd` 命名空間中的任何其他 `Application` 一樣被建立和管理，可以宣告式地，也可以透過 Argo CD API（例如，使用 CLI、Web UI、REST API 等）。

### 重新設定 Argo CD 以允許某些命名空間

#### 變更工作負載啟動參數

為了啟用此功能，Argo CD 管理員必須重新設定 `argocd-server` 和 `argocd-application-controller` 工作負載，以將 `--application-namespaces` 參數新增到容器的啟動命令中。

`--application-namespaces` 參數接受一個以逗號分隔的命名空間列表，其中將允許 `Applications`。列表中的每個項目都支援：

-   shell 風格的萬用字元，例如 `*`，因此例如 `app-team-*` 條目將匹配 `app-team-one` 和 `app-team-two`。要在執行 Argo CD 的叢集上啟用所有命名空間，您可以只指定 `*`，即 `--application-namespaces=*`。
-   正規表示式，需要將字串包在 ```/``` 中，例如允許所有命名空間，除了某個特定的命名空間：```/^((?!not-allowed).)*$/```。

`argocd-server` 和 `argocd-application-controller` 的啟動參數也可以透過在 `argocd-cmd-params-cm` ConfigMap 中指定 `application.namespaces` 設定來方便地設定和保持同步，而*不是*變更相應工作負載的清單。例如：

```yaml
data:
  application.namespaces: app-team-one, app-team-two
```

將允許 `app-team-one` 和 `app-team-two` 命名空間用於管理 `Application` 資源。在變更 `argocd-cmd-params-cm` 命名空間後，需要重新啟動適當的工作負載：

```bash
kubectl rollout restart -n argocd deployment argocd-server
kubectl rollout restart -n argocd statefulset argocd-application-controller
```

#### 調整 Kubernetes RBAC

我們決定暫時不預設擴展 `argocd-server` 工作負載的 Kubernetes RBAC。如果您希望由 Argo CD API（即 CLI 和 UI）管理其他命名空間中的 `Applications`，您需要擴展 `argocd-server` ServiceAccount 的 Kubernetes 權限。

我們在 `examples/k8s-rbac/argocd-server-applications` 目錄中提供了適用於此目的的 `ClusterRole` 和 `ClusterRoleBinding`。對於預設的 Argo CD 安裝（即安裝到 `argocd` 命名空間），您可以直接應用它們：

```shell
kubectl apply -k examples/k8s-rbac/argocd-server-applications/
```

`argocd-notifications-controller-rbac-clusterrole.yaml` 和 `argocd-notifications-controller-rbac-clusterrolebinding.yaml` 用於支援通知控制器通知所有命名空間中的應用程式。

> [!NOTE]
> 在未來的某個時候，我們可能會將此叢集角色作為預設安裝清單的一部分。

### 在 AppProject 中允許額外的命名空間

任何對 Argo CD 控制平面命名空間 (`argocd`) 具有 Kubernetes 存取權限的使用者，特別是那些有權以宣告式方式建立或更新 `Applications` 的使用者，都被視為 Argo CD 管理員。

這在過去阻止了非特權的 Argo CD 使用者以宣告式方式建立或管理 `Applications`。這些使用者被限制為改用 API，並受 Argo CD RBAC 的約束，以確保只建立允許的 `AppProjects` 中的 `Applications`。

要在 `argocd` 命名空間之外建立 `Application`，`Application` 的 `.spec.project` 欄位中引用的 `AppProject` 必須在其 `.spec.sourceNamespaces` 欄位中包含 `Application` 的命名空間。

例如，請考慮以下兩個（不完整的）`AppProject` 規格：

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
  name: project-one
  namespace: argocd
spec:
  sourceNamespaces:
  - namespace-one
```

和

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
  name: project-two
  namespace: argocd
spec:
  sourceNamespaces:
  - namespace-two
```

為了讓 Application 將 `.spec.project` 設定為 `project-one`，它必須在 `namespace-one` 或 `argocd` 命名空間中建立。同樣，為了讓 Application 將 `.spec.project` 設定為 `project-two`，它必須在 `namespace-two` 或 `argocd` 命名空間中建立。

如果 `namespace-two` 中的 Application 將其 `.spec.project` 設定為 `project-one`，或者 `namespace-one` 中的 Application 將其 `.spec.project` 設定為 `project-two`，Argo CD 會將此視為權限違規並拒絕協調該 Application。

此外，無論 Argo CD RBAC 權限如何，Argo CD API 都會強制執行這些約束。

`AppProject` 的 `.spec.sourceNamespaces` 欄位是一個列表，可以包含任意數量的命名空間，並且每個條目都支援 shell 風格的萬用字元，因此您可以允許像 `team-one-*` 這樣的模式的命名空間。

> [!WARNING]
> 不要在任何特權 AppProject（如 `default` 專案）的 `.spec.sourceNamespaces` 欄位中新增使用者控制的命名空間。請始終確保 AppProject 遵循授予最少所需權限的原則。切勿在 AppProject 中授予對 `argocd` 命名空間的存取權限。

> [!NOTE]
> 為了向後相容，Argo CD 控制平面命名空間 (`argocd`) 中的 Applications 被允許將其 `.spec.project` 欄位設定為引用任何 AppProject，無論 AppProject 的 `.spec.sourceNamespaces` 欄位施加了何種限制。

> [!NOTE]
> 目前無法在一個命名空間中擁有 applicationset，並在另一個命名空間中產生應用程式。
> 有關更多資訊，請參閱 [#11104](https://github.com/argoproj/argo-cd/issues/11104)。

### 應用程式名稱

對於 CLI 和 UI，應用程式現在以 `<namespace>/<name>` 的格式被引用和顯示。

為了向後相容，如果 Application 的命名空間是控制平面的命名空間（即 `argocd`），則在引用應用程式名稱時可以省略 `<namespace>`。例如，應用程式名稱 `argocd/someapp` 和 `someapp` 在 CLI 和 UI 中語義上是相同的，並且指的是同一個應用程式。

### 應用程式 RBAC

Application 物件的 RBAC 語法已從 `<project>/<application>` 更改為 `<project>/<namespace>/<application>`，以適應根據要管理的 Application 的來源命名空間限制存取的需求。

為了向後相容，`argocd` 命名空間中的 Applications 仍然可以在 RBAC 策略規則中被引用為 `<project>/<application>`。

萬用字元尚不區分專案和應用程式命名空間。例如，以下 RBAC 規則將匹配屬於專案 `foo` 的任何應用程式，無論它是在哪個命名空間中建立的：

```
p, somerole, applications, get, foo/*, allow
```

如果您想將存取權限限制為僅授予命名空間 `bar` 內專案 `foo` 中的 `Applications`，則需要將規則調整如下：

```
p, somerole, applications, get, foo/bar/*, allow
```

## 在其他命名空間中管理應用程式

### 宣告式地

對於 Applications 的宣告式管理，只需在所需的命名空間中從 YAML 或 JSON 清單建立 Application 即可。請確保 `.spec.project` 欄位引用了允許此命名空間的 AppProject。例如，以下（不完整的）Application 清單在 `some-namespace` 命名空間中建立了一個 Application：

```yaml
kind: Application
apiVersion: argoproj.io/v1alpha1
metadata:
  name: some-app
  namespace: some-namespace
spec:
  project: some-project
  # ...
```

然後，專案 `some-project` 將需要在允許的來源命名空間列表中指定 `some-namespace`，例如：

```yaml
kind: AppProject
apiVersion: argoproj.io/v1alpha1
metadata:
    name: some-project
    namespace: argocd
spec:
    sourceNamespaces:
    - some-namespace
```

### 使用 CLI

您可以使用所有現有的 Argo CD CLI 命令來管理其他命名空間中的應用程式，就像您使用 CLI 來管理控制平面命名空間中的應用程式一樣。

例如，要檢索 `bar` 命名空間中名為 `foo` 的 `Application`，您可以使用以下 CLI 命令：

```shell
argocd app get foo/bar
```

同樣，要管理此應用程式，請繼續將其稱為 `foo/bar`：

```bash
# 建立一個應用程式
argocd app create foo/bar ...
# 同步應用程式
argocd app sync foo/bar
# 刪除應用程式
argocd app delete foo/bar
# 檢索應用程式的清單
argocd app manifests foo/bar
```

如前所述，對於 Argo CD 控制平面命名空間中的應用程式，您可以從應用程式名稱中省略命名空間。

### 使用 UI

與 CLI 類似，您可以在 UI 中將應用程式稱為 `foo/bar`。

例如，要在 Web UI 的 `foo` 命名空間中建立一個名為 `bar` 的應用程式，請在建立對話方塊的 _應用程式名稱_ 欄位中將應用程式名稱設定為 `foo/bar`。如果省略了命名空間，將使用控制平面的命名空間。

### 使用 REST API

如果您正在使用 REST API，則無法將 `Application` 的命名空間指定為應用程式名稱，並且需要使用可選的 `appNamespace` 查詢參數來指定資源。例如，要處理 `bar` 命名空間中名為 `foo` 的 `Application` 資源，請求將如下所示：

```bash
GET /api/v1/applications/foo?appNamespace=bar
```

對於其他操作，例如 `POST` 和 `PUT`，`appNamespace` 參數必須是請求負載的一部分。

對於控制平面命名空間中的 `Application` 資源，可以省略此參數。