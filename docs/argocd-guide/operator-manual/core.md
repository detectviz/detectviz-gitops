# Argo CD Core

## 簡介

Argo CD Core 是一種不同的安裝方式，它以無頭模式 (headless mode) 執行 Argo CD。透過這種安裝方式，您將擁有一個功能齊全的 GitOps 引擎，能夠從 Git 儲存庫中獲取期望的狀態，並將其應用於 Kubernetes。

以下功能群組在此安裝中將不可用：

- Argo CD RBAC 模型
- Argo CD API
- Argo CD 通知控制器 (Notification Controller)
- 基於 OIDC 的身份驗證

以下功能將部分可用（有關更多詳細資訊，請參閱下方的 [使用](#使用) 部分）：

- Argo CD Web UI
- Argo CD CLI
- 多租戶（嚴格基於 git push 權限的 GitOps）

一些證明執行 Argo CD Core 合理性的使用案例包括：

- 作為叢集管理員，我只想依賴 Kubernetes RBAC。
- 作為 DevOps 工程師，我不想學習新的 API 或依賴另一個 CLI 來自動化我的部署。我只想依賴 Kubernetes API。
- 作為叢集管理員，我不想向開發人員提供 Argo CD UI 或 Argo CD CLI。

## 架構

由於 Argo CD 在設計時考慮了基於元件的架構，因此可以進行更精簡的安裝。在這種情況下，安裝的元件較少，但主要的 GitOps 功能仍然可以運作。

在下圖中，Core 方塊顯示了選擇 Argo CD Core 時將安裝的元件：

![Argo CD Core](../assets/argocd-core-components.png)

請注意，即使 Argo CD 控制器可以在沒有 Redis 的情況下執行，但這並不建議。Argo CD 控制器使用 Redis 作為重要的快取機制，可減少對 Kube API 和 Git 的負載。因此，Redis 也包含在此安裝方法中。

## 安裝

可以透過應用一個包含所有必要資源的單一清單檔案來安裝 Argo CD Core。

範例：

```
export ARGOCD_VERSION=<desired argo cd release version (e.g. v2.7.0)>
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/core-install.yaml
```

## 使用

安裝 Argo CD Core 後，使用者將能夠透過依賴 GitOps 與其互動。可用的 Kubernetes 資源將是 `Application` 和 `ApplicationSet` CRD。透過使用這些資源，使用者將能夠在 Kubernetes 中部署和管理應用程式。

即使在執行 Argo CD Core 時，仍然可以使用 Argo CD CLI。在這種情況下，CLI 將產生一個本地 API 伺服器進程，用於處理 CLI 指令。指令結束後，本地 API 伺服器進程也將終止。這對使用者來說是透明的，不需要額外的指令。請注意，Argo CD Core 將僅依賴 Kubernetes RBAC，叫用 CLI 的使用者（或進程）需要有權存取 Argo CD 命名空間，並在 `Application` 和 `ApplicationSet` 資源中具有執行給定指令的適當權限。

要在核心模式下使用 [Argo CD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation)，需要在 `login` 子指令中傳遞 `--core` 旗標。`--core` 旗標負責產生一個本地 Argo CD API 伺服器進程，用於處理 CLI 和 Web UI 請求。

範例：

```bash
kubectl config set-context --current --namespace=argocd # 將目前的 kube 上下文變更為 argocd 命名空間
argocd login --core
```

同樣，如果使用者喜歡使用此方法與 Argo CD 互動，他們也可以在本地執行 Web UI。可以透過執行以下指令在本地啟動 Web UI：

```
argocd admin dashboard -n argocd
```

Argo CD Web UI 將在 `http://localhost:8080` 上可用。
