# 安全性

Argo CD 經過嚴格的內部安全審查和滲透測試，以滿足 [PCI 相容性](https://www.pcisecuritystandards.org) 要求。以下是 Argo CD 的一些安全性主題和實作細節。

## 驗證

對 Argo CD API 伺服器的驗證僅使用 [JSON Web Tokens](https://jwt.io) (JWT) 執行。使用者名稱/密碼持有者權杖不用於驗證。JWT 的取得/管理方式如下：

1. 對於本機 `admin` 使用者，使用 `/api/v1/session` 端點將使用者名稱/密碼交換為 JWT。此權杖由 Argo CD API 伺服器本身簽署和發行，並在 24 小時後到期（此權杖過去不會到期，請參閱 [CVE-2021-26921](https://github.com/argoproj/argo-cd/security/advisories/GHSA-9h6w-j7w4-jr52)）。當管理員密碼更新時，所有現有的管理員 JWT 權杖都會立即被撤銷。密碼以 bcrypt 雜湊形式儲存在 [`argocd-secret`](https://github.com/argoproj/argo-cd/blob/master/manifests/base/config/argocd-secret.yaml) Secret 中。

2. 對於單一登入使用者，使用者會完成對已設定的 OIDC 身分識別提供者（透過捆綁的 Dex 提供者委派，或直接對自行管理的 OIDC 提供者）的 OAuth2 登入流程。此 JWT 由 IDP 簽署和發行，到期和撤銷由提供者處理。Dex 權杖在 24 小時後到期。

3. 自動化權杖是使用 `/api/v1/projects/{project}/roles/{role}/token` 端點為專案產生的，並由 Argo CD 簽署和發行。這些權杖在範圍和權限上受到限制，只能用於管理其所屬專案中的應用程式資源。專案 JWT 具有可設定的到期時間，可以透過從專案角色中刪除 JWT 參考 ID 來立即撤銷。

## 授權

授權是透過迭代使用者 JWT 群組宣告中的群組成員資格清單，並將每個群組與 [RBAC](./rbac.md) 策略中的角色/規則進行比較來執行的。任何符合的規則都允許存取 API 請求。

## TLS

所有網路通訊都透過 TLS 執行，包括三個元件（argocd-server、argocd-repo-server、argocd-application-controller）之間的服務對服務通訊。Argo CD API 伺服器可以使用 `--tlsminversion 1.2` 旗標強制使用 TLS 1.2。與 Redis 的通訊預設透過純 HTTP 執行。可以使用命令列參數設定 TLS。

## Git & Helm 儲存庫

Git 和 Helm 儲存庫由一個獨立的服務（稱為 repo-server）管理。repo-server 不具備任何 Kubernetes 權限，也不儲存任何服務（包括 git）的憑證。repo-server 負責複製已獲 Argo CD 操作員允許和信任的儲存庫，並在儲存庫的指定路徑產生 Kubernetes 清單。為了提高效能和頻寬效率，repo-server 會維護這些儲存庫的本機複本，以便後續對儲存庫的提交能有效地下載。

在設定 Argo CD 允許從中部署的 git 儲存庫時，存在一些安全性考量。簡而言之，未經授權取得 Argo CD 信任的 git 儲存庫的寫入權限，將會產生以下所述的嚴重安全性影響。

### 未經授權的部署

由於 Argo CD 部署了 git 中定義的 Kubernetes 資源，因此具有受信任 git 儲存庫存取權限的攻擊者將能夠影響所部署的 Kubernetes 資源。例如，攻擊者可以更新部署清單以將惡意容器映像檔部署到環境中，或刪除 git 中的資源，導致它們在即時環境中被清除。

### 工具指令叫用

除了原始 YAML 之外，Argo CD 還原生支援兩種流行的 Kubernetes 組態管理工具：helm 和 kustomize。在呈現清單時，Argo CD 會執行這些組態管理工具（即 `helm template`、`kustomize build`）以產生清單。具有受信任 git 儲存庫寫入權限的攻擊者可能會建構惡意的 helm 圖表或 kustomization，試圖讀取樹狀結構外的檔案。這包括相鄰的 git 儲存庫以及 repo-server 本身的檔案。這是否對您的組織構成風險，取決於 git 儲存庫的內容是否具有敏感性。預設情況下，repo-server 本身不包含敏感資訊，但可能已設定包含敏感資訊的組態管理外掛程式（例如解密金鑰）。如果使用此類外掛程式，必須極度小心以確保儲存庫內容始終可以信任。

可以選擇性地單獨停用內建的組態管理工具。如果您知道您的使用者不需要某個特定的組態管理工具，建議停用該工具。更多資訊請參閱[工具偵測](../user-guide/tool_detection.md)。

### 遠端基礎和 helm 圖表相依性

Argo CD 的儲存庫允許清單僅限制初始複製的儲存庫。但是，kustomize 和 helm 都包含參考和追蹤*其他*儲存庫的功能（例如 kustomize 遠端基礎、helm 圖表相依性），這些儲存庫可能不在儲存庫允許清單中。Argo CD 操作員必須了解，具有受信任 git 儲存庫寫入權限的使用者可以參考其他包含 Kubernetes 資源的遠端 git 儲存庫，這些資源在已設定的 git 儲存庫中不易搜尋或稽核。

## 敏感資訊

### 密碼

Argo CD 永遠不會從其 API 傳回敏感資料，並會在 API 負載和日誌中編輯所有敏感資料。這包括：

* 叢集憑證
* Git 憑證
* OAuth2 用戶端密碼
* Kubernetes Secret 值

### 外部叢集憑證

為了管理外部叢集，Argo CD 會將外部叢集的憑證儲存為 argocd 命名空間中的 Kubernetes Secret。此 secret 包含與在 `argocd cluster add` 期間建立的 `argocd-manager` ServiceAccount 相關聯的 K8s API 持有人權杖，以及與該 API 伺服器的連線選項（TLS 組態/憑證、AWS role-arn 等）。此資訊用於重建 Argo CD 服務使用的叢集的 REST 組態和 kubeconfig。

若要輪換 Argo CD 使用的持有人權杖，可以刪除該權杖（例如使用 kubectl），這會導致 Kubernetes 產生一個帶有新持有人權杖的新 secret。可以透過重新執行 `argocd cluster add` 將新權杖重新輸入到 Argo CD。在 *_受管理_* 叢集上執行以下指令：

```bash
# 使用外部受管理叢集的 kubeconfig 執行
kubectl delete secret argocd-manager-token-XXXXXX -n kube-system
argocd cluster add CONTEXTNAME
```

> [!NOTE]
> Kubernetes 1.24 [停止為 Service Account 自動建立權杖](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.24.md#no-really-you-must-read-this-before-you-upgrade)。
> [從 Argo CD 2.4 開始](https://github.com/argoproj/argo-cd/pull/9546)，`argocd cluster add` 在新增 1.24 叢集時會建立一個 ServiceAccount _和_ 一個不會過期的 Service Account 權杖 Secret。未來，Argo CD 將[新增對 Kubernetes TokenRequest API 的支援](https://github.com/argoproj/argo-cd/issues/9610)以避免使用長效權杖。

若要撤銷 Argo CD 對受管理叢集的存取權限，請刪除 *_受管理_* 叢集上的 RBAC 成品，並從 Argo CD 移除叢集項目：

```bash
# 使用外部受管理叢集的 kubeconfig 執行
kubectl delete sa argocd-manager -n kube-system
kubectl delete clusterrole argocd-manager-role
kubectl delete clusterrolebinding argocd-manager-role-binding
argocd cluster rm https://your-kubernetes-cluster-addr
```
<!-- markdownlint-disable MD027 -->
> 注意：對於 AWS EKS 叢集，[get-token](https://docs.aws.amazon.com/cli/latest/reference/eks/get-token.html) 指令用於驗證外部叢集，它使用 IAM 角色而不是本機儲存的權杖，因此不需要輪換權杖，並且撤銷是透過 IAM 處理的。
<!-- markdownlint-enable MD027 -->

## 叢集 RBAC

預設情況下，Argo CD 使用[叢集管理員等級的角色](https://github.com/argoproj/argo-cd/blob/master/manifests/base/application-controller-roles/argocd-application-controller-role.yaml)以便：

1. 監看和操作叢集狀態
2. 將資源部署到叢集

雖然 Argo CD 需要對受管理叢集中的資源具有叢集範圍的**_讀取_**權限才能正常運作，但它不一定需要對叢集的完整**_寫入_**權限。可以修改 argocd-server 和 argocd-application-controller 使用的 ClusterRole，以便將寫入權限限制為僅您希望 Argo CD 管理的命名空間和資源。

若要微調外部受管理叢集的權限，請編輯 `argocd-manager-role` 的 ClusterRole

```bash
# 使用外部受管理叢集的 kubeconfig 執行
kubectl edit clusterrole argocd-manager-role
```

若要微調 Argo CD 對其自身叢集（即 `https://kubernetes.default.svc`）的權限，請編輯 Argo CD 執行所在的叢集中的以下 cluster role：

```bash
# 使用 Argo CD 執行所在的叢集的 kubeconfig 執行
kubectl edit clusterrole argocd-server
kubectl edit clusterrole argocd-application-controller
```

> [!TIP]
> 如果您想拒絕 Argo CD 存取某種資源，請將其新增為[排除的資源](declarative-setup.md#resource-exclusion)。

## 稽核

作為 GitOps 部署工具，Git 提交歷史記錄提供了對應用程式組態所做變更、何時進行以及由誰進行的自然稽核日誌。但是，此稽核日誌僅適用於 Git 中發生的情況，不一定與叢集中發生的事件一一對應。例如，使用者 A 可能對應用程式清單進行了多次提交，但使用者 B 可能稍後才將這些變更同步到叢集。

為了補充 Git 修訂歷史記錄，Argo CD 會發出應用程式活動的 Kubernetes 事件，並在適用時指出負責的執行者。例如：

```bash
$ kubectl get events
LAST SEEN   FIRST SEEN   COUNT   NAME                         KIND          SUBOBJECT   TYPE      REASON               SOURCE                          MESSAGE
1m          1m           1       guestbook.157f7c5edd33aeac   Application               Normal    ResourceCreated      argocd-server                   admin created application
...
```

然後可以使用其他工具（如 [Event Exporter](https://github.com/GoogleCloudPlatform/k8s-stackdriver/tree/master/event-exporter) 或 [Event Router](https://github.com/heptiolabs/eventrouter)）將這些事件持久化更長的時間。

## WebHook 負載

來自 webhook 事件的負載被視為不受信任。Argo CD 僅檢查負載以推斷 webhook 事件涉及的應用程式（例如，哪個儲存庫被修改），然後重新整理相關的應用程式以進行協調。此重新整理與每三分鐘定期發生的重新整理相同，只是由 webhook 事件快速觸發。

## 記錄

### 安全性欄位

與安全性相關的日誌會標記 `security` 欄位，以便更容易尋找、分析和報告。

| 層級 | 友好層級 | 說明 | 範例 |
|---|---|---|---|
| 1 | 低 | 非異常、非惡意的事件 | 成功存取 |
| 2 | 中 | 可能表示惡意事件，但很有可能是使用者/系統錯誤 | 存取被拒 |
| 3 | 高 | 可能是惡意事件，但沒有副作用或被阻止 | 儲存庫中的越界符號連結 |
| 4 | 嚴重 | 任何有副作用的惡意或可利用事件 | 檔案系統上殘留的密碼 |
| 5 | 緊急 | 絕不應意外發生的明確惡意事件，並表示正在進行的攻擊 | 帳戶的暴力破解 |

在適用的情況下，還會新增一個 `CWE` 欄位，指定[通用弱點列舉](https://cwe.mitre.org/index.html)編號。

> [!WARNING]
> 請注意，並非所有安全性日誌都已全面標記，這些範例不一定已實作。

### API 日誌

Argo CD 會記錄大多數 API 請求的負載，但被視為敏感的請求除外，例如 `/cluster.ClusterService/Create`、`/session.SessionService/Create` 等。完整的方***列表可以在 [server/server.go](https://github.com/argoproj/argo-cd/blob/abba8dddce8cd897ba23320e3715690f465b4a95/server/server.go#L516) 中找到。

Argo CD 不會記錄請求 API 端點的用戶端的 IP 位址，因為 API 伺服器通常位於代理之後。相反地，建議在位於 API 伺服器前面的代理伺服器中設定 IP 位址記錄。

### 標準應用程式日誌欄位

對於與應用程式相關的日誌，Argo CD 將記錄以下標準欄位：

* *application*：應用程式名稱，不含命名空間
* *app-namespace*：應用程式的命名空間
* *project*：應用程式的專案

## ApplicationSets

Argo CD 的 ApplicationSets 功能有其自身的[安全性考量](./applicationset/Security.md)。在使用 ApplicationSets 之前，請注意這些問題。

## 限制目錄應用程式的記憶體使用量

> >2.2.10, 2.1.16, >2.3.5

目錄類型的應用程式（其來源是原始 JSON 或 YAML 檔案）可能會消耗大量的 [repo-server](architecture.md#repository-server) 記憶體，具體取決於 YAML 檔案的大小和結構。

為避免過度使用 repo-server 中的記憶體（可能導致崩潰和拒絕服務），請在 [argocd-cmd-params-cm](argocd-cmd-params-cm.yaml) 中設定 `reposerver.max.combined.directory.manifests.size` 組態選項。

此選項限制了單個應用程式中所有 JSON 或 YAML 檔案的總大小。請注意，清單的記憶體中表示形式可能是在磁碟上清單大小的 300 倍。另請注意，此限制是每個應用程式的。如果同時為多個應用程式產生清單，則記憶體使用量會更高。

**範例：**

假設您的 repo-server 有 10G 的記憶體限制，並且您有十個使用原始 JSON 或 YAML 檔案的應用程式。若要計算每個應用程式的最大安全總檔案大小，請將 10G 除以 300 * 10 個應用程式（300 是清單的最壞情況記憶體增長因子）。

```
10G / 300 * 10 = 3M
```

因此，此設定的合理安全組態是每個應用程式 3M 的限制。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
data:
  reposerver.max.combined.directory.manifests.size: '3M'
```

300 倍的比率假設了一個惡意製作的清單檔案。如果您只想防止意外的過度記憶體使用，使用較小的比率可能是安全的。

請記住，如果惡意使用者可以建立額外的應用程式，他們可以增加總記憶體使用量。請謹慎授予[應用程式建立權限](rbac.md)。
