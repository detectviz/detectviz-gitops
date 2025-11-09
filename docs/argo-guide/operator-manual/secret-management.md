# 密碼管理

在使用 GitOps 填充密碼時，通常有兩種方法：在目標叢集上，或在 Argo CD 產生清單期間。我們強烈建議採用前者，因為它更安全且提供更好的使用者體驗。

有關進一步的討論，請參閱 [#1364](https://github.com/argoproj/argo-cd/issues/1364)。

## 目標叢集密碼管理

在此方法中，密碼會在目標叢集上填充，Argo CD 無需直接管理它們。
[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)、[External Secrets Operator](https://github.com/external-secrets/external-secrets)
和 [Kubernetes Secrets Store CSI Driver](https://github.com/kubernetes-sigs/secrets-store-csi-driver) 是此種密碼管理風格的範例。

此方法有兩個主要優點：

1) 安全性：Argo CD 無需存取密碼，這降低了洩漏密碼的風險。
2) 使用者體驗：密碼更新與應用程式同步操作脫鉤，這降低了在不相關的版本發布期間無意中套用密碼更新的風險。

我們強烈建議採用此種密碼管理風格。

此種密碼管理風格的其他範例包括：
* [aws-secret-operator](https://github.com/mumoshu/aws-secret-operator)
* [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)

## 基於 Argo CD 清單產生的密碼管理

在此方法中，Argo CD 的清單產生步驟用於注入密碼。這可以使用
[組態管理外掛程式](config-management-plugins.md)（如 [argocd-vault-plugin](https://github.com/argoproj-labs/argocd-vault-plugin)）來完成。

**我們強烈警告不要使用此種密碼管理風格**，因為它有幾個缺點：

1) 安全性：Argo CD 需要存取密碼，這增加了洩漏密碼的風險。Argo CD 將產生的清單以純文字形式儲存在其 Redis 快取中，因此將密碼注入清單會增加風險。
2) 使用者體驗：密碼更新與應用程式同步操作耦合，這增加了在不相關的版本發布期間無意中套用密碼更新的風險。
3) 呈現的清單模式：此方法與「呈現的清單」模式不相容，後者正日益成為 GitOps 的最佳實務。

許多使用者已經採用了基於產生的解決方案，我們理解遷移到基於操作員的解決方案可能是一項重大的工作。Argo CD 將繼續支援基於產生的密碼管理，但我們不會優先考慮僅支援此種密碼管理風格的新功能或改進。

### 緩解密碼注入外掛程式的風險

Argo CD 會將外掛程式產生的清單以及注入的密碼快取在其 Redis 執行個體中。這些清單也可透過 repo-server API（gRPC 服務）取得。這意味著有權存取 Redis 執行個體或 repo-server 的任何人都可以存取這些密碼。

請考慮以下步驟來緩解密碼注入外掛程式的風險：

1. 設定網路策略以防止直接存取 Argo CD 元件（Redis 和 repo-server）。請確保您的叢集支援這些網路策略並能實際執行它們。
2. 考慮在自己的叢集上執行 Argo CD，且該叢集上沒有執行其他應用程式。
