# 使用模擬進行應用程式同步

> [!WARNING]
> **Alpha 功能 (自 2.13.0 起)**
>
> 這是一項實驗性的、[alpha 品質](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#alpha)
> 的功能，允許您控制用於同步操作的服務帳戶。與控制平面操作所需的高度特權存取相比，
> 設定的服務帳戶可能具有建立資源所需的較低權限。

> [!WARNING]
> 在啟用此功能之前，請仔細閱讀本文件。不當的設定可能會導致潛在的安全性問題。

## 簡介

Argo CD 支援使用與其控制平面操作相同的服務帳戶來同步 `Application` 資源。此功能讓使用者能夠將用於應用程式同步的服務帳戶與用於控制平面操作的服務帳戶分離。

預設情況下，Argo CD 中的應用程式同步具有與 Argo CD 控制平面相同的權限。因此，在多租戶設定中，Argo CD 控制平面的權限需要與需要最高權限的租戶相匹配。例如，如果一個 Argo CD 實例有 10 個應用程式，而其中只有一個需要管理員權限，那麼 Argo CD 控制平面必須具有管理員權限才能同步那一個應用程式。這為惡意租戶提供了獲得管理員級別存取權限的機會。Argo CD 提供了一個多租戶模型，使用 `AppProjects` 來限制每個 `Application` 的授權操作，但這不夠安全，如果 Argo CD 遭到入侵，攻擊者將很容易獲得對叢集的 `cluster-admin` 存取權限。

Argo CD 管理員需要執行一些手動步驟才能啟用此功能，因為它預設是停用的。

> [!NOTE]
> 此功能目前被視為 alpha。在它被提升為穩定狀態之前，某些實作細節可能會隨著時間而改變。我們樂見早期採用者使用此功能並向我們提供錯誤報告和回饋。

### 什麼是模擬

模擬是 Kubernetes 中的一項功能，並在 `kubectl` CLI 客戶端中啟用，使用者可以透過模擬標頭來扮演另一個使用者。例如，管理員可以使用此功能來偵錯授權策略，方法是暫時模擬另一個使用者，看看請求是否被拒絕。

模擬請求首先以請求使用者的身份進行身份驗證，然後切換到被模擬的使用者資訊。

### 功能範圍

模擬目前僅支援由應用程式直接管理的物件的生命週期，其中包括同步操作（資源的建立、更新和刪除）以及作為應用程式 finalizer 邏輯一部分的刪除。這*不包括*透過 ArgoCD UI 觸發的操作，這些操作仍將使用 Argo CD 的控制平面服務帳戶執行。

## 先決條件

在多團隊/多租戶環境中，團隊/租戶通常被授予對目標命名空間的存取權限，以宣告式方式自我管理其 kubernetes 資源。
典型的租戶上線流程如下：
1. 平台管理員建立一個租戶命名空間，並在同一個租戶命名空間中建立用於建立資源的服務帳戶。
2. 平台管理員建立一個或多個角色 (Role) 來管理租戶命名空間中的 kubernetes 資源。
3. 平台管理員建立一個或多個角色綁定 (RoleBinding) 來將服務帳戶對應到前幾步中建立的角色。
4. 平台管理員可以選擇使用[任何命名空間中的應用程式](./app-any-namespace.md)功能，或為租戶提供在 ArgoCD 控制平面命名空間中建立應用程式的存取權限。
5. 如果平台管理員選擇任何命名空間中的應用程式功能，租戶可以在其各自的租戶命名空間中自行服務其 Argo 應用程式，而無需為控制平面命名空間提供額外的存取權限。

## 實作細節

### 概覽

為了讓應用程式為應用程式同步操作使用不同的服務帳戶，需要執行以下步驟：

1. 應啟用模擬功能旗標。請參閱[啟用應用程式同步與模擬功能](#enable-application-sync-with-impersonation-feature)中提供的步驟。

2. `Application` 的 `.spec.project` 欄位引用的 `AppProject` 必須具有 `DestinationServiceAccounts`，將目的地伺服器和命名空間對應到要用於同步操作的服務帳戶。請參閱[設定目的地服務帳戶](#configuring-destination-service-accounts)中提供的步驟。


### 啟用應用程式同步與模擬功能

為了啟用此功能，Argo CD 管理員必須如下所示重新設定 `argocd-cm` ConfigMap 中的 `application.sync.impersonation.enabled` 設定：

```yaml
data:
  application.sync.impersonation.enabled: "true"
```

### 停用應用程式同步與模擬功能

為了停用此功能，Argo CD 管理員必須如下所示重新設定 `argocd-cm` ConfigMap 中的 `application.sync.impersonation.enabled` 設定：

```yaml
data:
  application.sync.impersonation.enabled: "false"
```

> [!NOTE]
> 此功能預設是停用的。

> [!NOTE]
> 此功能只能在系統層級啟用/停用，一旦啟用/停用，它將適用於由 ArgoCD 管理的所有應用程式。

## 設定目的地服務帳戶

目的地服務帳戶可以新增到 `AppProject` 的 `.spec.destinationServiceAccounts` 下。指定目標目的地 `server` 和 `namespace`，並使用 `defaultServiceAccount` 欄位提供要用於同步操作的服務帳戶。引用此 `AppProject` 的應用程式將使用為其目的地設定的相應服務帳戶。

在應用程式同步操作期間，控制器會迴圈遍歷對應 `AppProject` 中可用的 `destinationServiceAccounts`，並嘗試找到一個匹配的候選者。如果目的地伺服器和命名空間組合有多個匹配項，則將考慮第一個有效的匹配項。如果沒有匹配項，則在同步操作期間會報告錯誤。為了避免此類同步錯誤，強烈建議將一個有效的服務帳戶設定為適用於所有目標目的地的包羅萬象的設定，並將其置於最低優先級。

可以指定服務帳戶及其命名空間。例如：`tenant1-ns:guestbook-deployer`。如果未為服務帳戶提供命名空間，則將使用應用程式的 `spec.destination.namespace`。如果未為服務帳戶提供命名空間，並且 `Application` 中也未提供可選的 `spec.destination.namespace` 欄位，則將使用應用程式的命名空間。

與 `AppProject` 關聯的 `DestinationServiceAccounts` 可以宣告式地或透過 Argo CD API（例如，使用 CLI、Web UI、REST API 等）來建立和管理。

### 使用宣告式 yaml

要宣告式地設定目的地服務帳戶，請如下所示為 `AppProject` 建立一個 yaml 檔案，並使用 `kubectl apply` 命令應用變更。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: my-project
  namespace: argocd
spec:
  description: Example Project
  # Allow manifests to deploy from any Git repos
  sourceRepos:
    - '*'
  destinations:
    - '*'
  destinationServiceAccounts:
    - server: https://kubernetes.default.svc
      namespace: guestbook
      defaultServiceAccount: guestbook-deployer
    - server: https://kubernetes.default.svc
      namespace: guestbook-dev
      defaultServiceAccount: guestbook-dev-deployer
    - server: https://kubernetes.default.svc
      namespace: guestbook-stage
      defaultServiceAccount: guestbook-stage-deployer
    - server: https://kubernetes.default.svc # catch-all configuration
      namespace: '*'
      defaultServiceAccount: default
```

### 使用 CLI

可以使用 ArgoCD CLI 將目的地服務帳戶新增到 `AppProject`。

例如，要為 `in-cluster` 和 `guestbook` 命名空間新增目的地服務帳戶，您可以使用以下 CLI 命令：

```shell
argocd proj add-destination-service-account my-project https://kubernetes.default.svc guestbook guestbook-sa
```

同樣，要從 `AppProject` 中移除目的地服務帳戶，您可以使用以下 CLI 命令：

```shell
argocd proj remove-destination-service-account my-project https://kubernetes.default.svc guestbook
```

### 使用 UI

與 CLI 類似，您可以在從 UI 建立或更新 `AppProject` 時新增目的地服務帳戶。