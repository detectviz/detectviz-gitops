# 高可用性

Argo CD 基本上是無狀態的。所有資料都以 Kubernetes 物件的形式持久化，而這些物件又儲存在 Kubernetes 的 etcd 中。Redis 僅用作可拋棄式快取，可以遺失。當遺失時，它會被重建而不會造成服務中斷。

提供了一組 [HA 清單](https://github.com/argoproj/argo-cd/tree/stable/manifests/ha) 供希望以高可用性方式執行 Argo CD 的使用者使用。這會執行更多容器，並以 HA 模式執行 Redis。

> [!NOTE]
> 由於規格中的 pod 反親和性規則，HA 安裝將需要至少三個不同的節點。此外，不支援僅 IPv6 的叢集。

## 擴展

### argocd-repo-server

**設定：**

`argocd-repo-server` 負責複製 Git 儲存庫、保持其最新狀態並使用適當的工具產生清單。

* `argocd-repo-server` 會 fork/exec 組態管理工具以產生清單。由於記憶體不足或作業系統執行緒數量限制，fork 可能會失敗。`--parallelismlimit` 旗標控制同時執行的清單產生數量，有助於避免 OOM kills。

* `argocd-repo-server` 確保在使用 Kustomize、Helm 或自訂外掛程式等組態管理工具產生清單期間，儲存庫處於乾淨狀態。因此，具有多個應用程式的 Git 儲存庫可能會影響儲存庫伺服器的效能。更多資訊請閱讀[單一儲存庫擴展考量](#monorepo-scaling-considerations)。

* `argocd-repo-server` 將儲存庫複製到 `/tmp`（或 `TMPDIR` 環境變數中指定的路徑）。如果 Pod 有太多儲存庫或儲存庫有很多檔案，可能會耗盡磁碟空間。為避免此問題，請掛載一個持久性磁碟區。

* `argocd-repo-server` 使用 `git ls-remote` 來解析模棱兩可的修訂版本，例如 `HEAD`、分支或標籤名稱。此操作頻繁發生且可能失敗。為避免同步失敗，請使用 `ARGOCD_GIT_ATTEMPTS_COUNT` 環境變數來重試失敗的請求。

* `argocd-repo-server` 預設每 3 分鐘檢查一次應用程式清單的變更。Argo CD 預設假設清單僅在儲存庫變更時才會變更，因此它會快取產生的清單（預設為 24 小時）。對於 Kustomize 遠端基礎，或者如果 Helm 圖表在不增加版本號的情況下被變更，即使儲存庫沒有變更，預期的清單也可能發生變化。透過縮短快取時間，您可以在不等候 24 小時的情況下取得變更。請使用 `--repo-cache-expiration duration`，我們建議在低流量環境中嘗試 `1h`。請記住，如果設定得太低，這將抵銷快取的好處。

* `argocd-repo-server` 執行 `helm` 或 `kustomize` 等組態管理工具，並強制執行 90 秒的逾時。可以使用 `ARGOCD_EXEC_TIMEOUT` 環境變數來變更此逾時。該值應為 Go 時間持續時間字串格式，例如 `2m30s`。

* `argocd-repo-server` 將向已超過 `ARGOCD_EXEC_TIMEOUT` 的指令發出 `SIGTERM` 訊號。在大多數情況下，行為良好的指令在收到訊號時會立即結束。但是，如果沒有發生這種情況，`argocd-repo-server` 將再等候一個 `ARGOCD_EXEC_FATAL_TIMEOUT` 的逾時，然後使用 `SIGKILL` 強制結束指令以防止停滯。請注意，無法以 `SIGTERM` 結束通常是違規指令或 `argocd-repo-server` 呼叫它的方式中的錯誤，應向問題追蹤器報告以進行進一步調查。

* 在組態管理外掛程式 (CMP) 中使用 `discovery` 選項時，`argocd-repo-server` 會將儲存庫（或僅由 `argocd.argoproj.io/manifest-generate-paths` 註解指定的檔案）複製到每個外掛程式的單獨目錄中。這會對 **argocd-repo-server** 的磁碟資源造成沉重負擔，特別是如果儲存庫包含大檔案。為緩解此問題，請考慮停用 `discovery` 或使用[外掛程式 tar 串流排除](./config-management-plugins.md#plugin-tar-stream-exclusions)。

**指標：**

* `argocd_git_request_total` - Git 請求數。此指標提供兩個標籤：
    - `repo` - Git 儲存庫 URL
    - `request_type` - `ls-remote` 或 `fetch`。

* `ARGOCD_ENABLE_GRPC_TIME_HISTOGRAM` - 是一個環境變數，可啟用收集 RPC 效能指標。如果您需要解決效能問題，請啟用它。注意：此指標的查詢和儲存成本都很高！

### argocd-application-controller

**設定：**

`argocd-application-controller` 使用 `argocd-repo-server` 取得產生的清單，並使用 Kubernetes API 伺服器取得實際的叢集狀態。

* 每個控制器副本使用兩個獨立的佇列來處理應用程式協調（毫秒）和應用程式同步（秒）。每個佇列的佇列處理器數量由 `--status-processors`（預設為 20）和 `--operation-processors`（預設為 10）旗標控制。如果您的 Argo CD 執行個體管理太多應用程式，請增加處理器數量。對於 1000 個應用程式，我們使用 50 個 `--status-processors` 和 25 個 `--operation-processors`。

* 清單產生通常在協調期間花費最多時間。清單產生的持續時間受到限制，以確保控制器重新整理佇列不會溢位。如果清單產生花費太多時間，應用程式協調會失敗並出現 `Context deadline exceeded` 錯誤。作為因應措施，請增加 `--repo-server-timeout-seconds` 的值，並考慮擴展 `argocd-repo-server` 部署。

* 控制器使用 Kubernetes watch API 來維護一個輕量級的 Kubernetes 叢集快取。這可以避免在應用程式協調期間查詢 Kubernetes，並顯著提高效能。出於效能原因，控制器僅監控和快取資源的偏好版本。在協調期間，控制器可能需要將快取的資源從偏好版本轉換為 Git 中儲存的資源版本。如果 `kubectl convert` 因不支援轉換而失敗，則控制器會退回到 Kubernetes API 查詢，這會減慢協調速度。在這種情況下，我們建議在 Git 中使用偏好的資源版本。

* 控制器預設每 3 分鐘輪詢一次 Git。您可以使用 `argocd-cm` ConfigMap 中的 `timeout.reconciliation` 和 `timeout.reconciliation.jitter` 設定來變更此持續時間。欄位的值是[持續時間字串](https://pkg.go.dev/time#ParseDuration)，例如 `60s`、`1m` 或 `1h`。

* 如果控制器管理太多叢集且使用太多記憶體，您可以將叢集分片到多個控制器副本。若要啟用分片，請增加 `argocd-application-controller` `StatefulSet` 中的副本數，並在 `ARGOCD_CONTROLLER_REPLICAS` 環境變數中重複該副本數。下面的策略性合併修補程式展示了設定兩個控制器副本所需的變更。

* 預設情況下，控制器將每 10 秒更新一次叢集資訊。如果您的叢集網路環境存在問題導致更新時間過長，您可以嘗試修改環境變數 `ARGO_CD_UPDATE_CLUSTER_INFO_TIMEOUT` 來增加逾時（單位為秒）。

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: argocd-application-controller
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: argocd-application-controller
        env:
        - name: ARGOCD_CONTROLLER_REPLICAS
          value: "2"
```

* 為了手動設定叢集的分片號碼，請在建立叢集時指定選用的 `shard` 屬性。如果未指定，將由應用程式控制器即時計算。
* `argocd-application-controller` 的分片分佈演算法可以使用 `--sharding-method` 參數來設定。支援的分片方法有：
    - `legacy` 模式使用基於 `uid` 的分佈（非均勻）。
    - `round-robin` 在所有分片上使用均勻分佈。
    - `consistent-hashing` 使用具有有界負載的一致性雜湊演算法，該演算法傾向於均勻分佈，並且在新增或移除分片或叢集時也會減少叢集或應用程式的重新洗牌。

`--sharding-method` 參數也可以透過在 `argocd-cmd-params-cm` `configMap` 中設定 `controller.sharding.algorithm` 金鑰（首選）或設定 `ARGOCD_CONTROLLER_SHARDING_ALGORITHM` 環境變數並指定相同的可能值來覆寫。

> [!WARNING]
> **Alpha 功能**
>
> `round-robin` 分片分佈演算法是一個實驗性功能。已知在某些叢集移除的情況下會發生重新洗牌。如果移除 rank-0 的叢集，將會發生所有叢集在分片間的重新洗牌，並可能暫時產生負面的效能影響。
> `consistent-hashing` 分片分佈演算法是一個實驗性功能。在 [CNOE 部落格](https://cnoe.io/blog/argo-cd-application-scalability)上已記錄了廣泛的基準測試，結果令人鼓舞。在將此功能轉為生產就緒狀態之前，非常感謝社群的回饋。

* 可以透過修補叢集 secret 中的 `shard` 欄位以包含分片號碼來手動指派和強制叢集到一個 `shard`，例如
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mycluster-secret
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  shard: 1
  name: mycluster.example.com
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

* `ARGOCD_ENABLE_GRPC_TIME_HISTOGRAM` - 啟用收集 RPC 效能指標的環境變數。如果您需要解決效能問題，請啟用它。注意：此指標的查詢和儲存成本都很高！

* `ARGOCD_CLUSTER_CACHE_LIST_PAGE_BUFFER_SIZE` - 控制器在同步叢集快取時對 K8s api 伺服器執行列表操作時在記憶體中緩衝的頁數的環境變數。當叢集包含大量資源且叢集同步時間超過預設的 etcd 壓縮間隔逾時時，這很有用。在這種情況下，當嘗試同步叢集快取時，應用程式控制器可能會擲回一個錯誤，指出 `continue parameter is too old to display a consistent list result`。為此環境變數設定較高的值會為控制器設定較大的緩衝區，用於儲存預先擷取的頁面，這些頁面會非同步處理，從而增加在 etcd 壓縮間隔逾時到期之前已提取所有頁面的可能性。在最極端的情況下，操作員可以設定此值，使得 `ARGOCD_CLUSTER_CACHE_LIST_PAGE_SIZE * ARGOCD_CLUSTER_CACHE_LIST_PAGE_BUFFER_SIZE` 超過最大的資源計數（按 k8s api 版本分組，這是列表操作的平行處理粒度）。在這種情況下，所有資源都將被緩衝在記憶體中——任何 api 伺服器請求都不會被處理阻塞。

* `ARGOCD_CLUSTER_CACHE_BATCH_EVENTS_PROCESSING` - 啟用控制器收集 Kubernetes 資源事件並批次處理它們的環境變數。當叢集包含大量資源且控制器被事件數量淹沒時，這很有用。預設值為 `true`。`false` 表示控制器將逐一處理事件。

* `ARGOCD_CLUSTER_CACHE_EVENTS_PROCESSING_INTERVAL` - 控制批次處理事件間隔的環境變數。有效值為 Go 時間持續時間字串格式，例如 `1ms`、`1s`、`1m`、`1h`。預設值為 `100ms`。該變數僅在 `ARGOCD_CLUSTER_CACHE_BATCH_EVENTS_PROCESSING` 設定為 `true` 時使用。

* `ARGOCD_APPLICATION_TREE_SHARD_SIZE` - 控制儲存在一個 Redis 金鑰中的最大資源數的環境變數。將應用程式樹分割成多個金鑰有助於減少控制器和 Redis 之間的流量。預設值為 0，表示應用程式樹儲存在單一 Redis 金鑰中。合理的值為 100。

**指標**

* `argocd_app_reconcile` - 以秒為單位報告應用程式協調持續時間。可用於建立協調持續時間熱圖，以取得高階的協調效能概觀。
* `argocd_app_k8s_request_total` - 每個應用程式的 k8s 請求數。備援 Kubernetes API 查詢的數量 - 有助於識別哪個應用程式具有非偏好版本的資源並導致效能問題。

### argocd-server

`argocd-server` 是無狀態的，可能最不可能引起問題。為確保升級期間沒有停機時間，請考慮將副本數增加到 `3` 或更多，並在 `ARGOCD_API_SERVER_REPLICAS` 環境變數中重複該數字。下面的策略性合併修補程式展示了這一點。

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: argocd-server
        env:
        - name: ARGOCD_API_SERVER_REPLICAS
          value: "3"
```

**設定：**

* `ARGOCD_API_SERVER_REPLICAS` 環境變數用於將[同時登入請求的限制（`ARGOCD_MAX_CONCURRENT_LOGIN_REQUESTS_COUNT`）](./user-management/index.md#failed-logins-rate-limiting)在每個副本之間進行劃分。
* `ARGOCD_GRPC_MAX_SIZE_MB` 環境變數允許以 MB 為單位指定伺服器回應訊息的最大大小。預設值為 200。對於管理 3000 個以上應用程式的 Argo CD 執行個體，您可能需要增加此值。

### argocd-dex-server, argocd-redis

`argocd-dex-server` 使用記憶體資料庫，兩個或更多個執行個體會有不一致的資料。`argocd-redis` 已預先設定為僅理解總共三個 redis 伺服器/哨兵。

## 單一儲存庫擴展考量

Argo CD 儲存庫伺服器在本機維護一個儲存庫複本，並將其用於應用程式清單產生。如果清單產生需要變更本機儲存庫複本中的檔案，則每個伺服器執行個體只允許一個同時的清單產生。如果您有一個包含多個應用程式（50 個以上）的單一儲存庫，此限制可能會顯著減慢 Argo CD 的速度。

### 啟用並行處理

Argo CD 根據組態管理工具和應用程式設定來判斷清單產生是否可能變更本機儲存庫複本中的本機檔案。
如果清單產生沒有副作用，則請求會平行處理而不會有效能損失。以下是可能導致緩慢的已知情況及其因應措施：

  * **多個基於 Helm 的應用程式指向同一個 Git 儲存庫中的相同目錄：** 由於歷史原因，Argo CD 過去是循序產生 Helm 清單。從 v3.0 開始，Argo CD 預設平行產生 Helm 清單。

  * **多個基於自訂外掛程式的應用程式：** 避免在清單產生期間建立暫存檔案，並在應用程式目錄中建立 `.argocd-allow-concurrency` 檔案，或使用 sidecar 外掛程式選項，該選項使用儲存庫的暫存複本處理每個應用程式。

  * **同一個儲存庫中具有[參數覆寫](../user-guide/parameters.md)的多個 Kustomize 應用程式：** 抱歉，目前沒有因應措施。


### 清單路徑註解

Argo CD 會積極地快取產生的清單，並使用儲存庫的提交 SHA 作為快取金鑰。對 Git 儲存庫的新提交會使儲存庫中設定的所有應用程式的快取失效。
這可能會對具有多個應用程式的儲存庫產生負面影響。您可以使用 `argocd.argoproj.io/manifest-generate-paths` Application CRD 註解來解決此問題並提高效能。

注意：`argocd.argoproj.io/manifest-generate-paths` 註解可用於 webhook。自 Argo CD v2.11 起，此註解也可以在**未設定任何 webhook** 的情況下使用。Webhook 不是此功能的先決條件。您可以單獨依賴此註解來最佳化所有應用程式的清單產生。

`argocd.argoproj.io/manifest-generate-paths` 註解包含一個以分號分隔的 Git 儲存庫內路徑清單，這些路徑在清單產生期間使用。它將使用註解中指定的路徑來比較上次快取的修訂版本與最新的提交。如果沒有修改過的檔案與 `argocd.argoproj.io/manifest-generate-paths` 中指定的路徑相符，則不會觸發應用程式協調，並且現有的快取將被視為對新提交有效。

為每個應用程式使用不同儲存庫的安裝**不受**此行為的影響，並且可能無法從使用這些註解中獲益。

同樣地，當外部來源發生不相關的變更時，引用外部 Helm values 檔案的應用程式將無法從此功能中獲益。

對於 webhook，比較是使用 webhook 事件負載中指定的檔案來完成的。

> [!NOTE]
> 應用程式清單路徑註解對 webhook 的支援取決於應用程式使用的 git 提供者。目前僅支援基於 GitHub、GitLab 和 Gogs 的儲存庫。

* **相對路徑** 註解可能包含相對路徑。在這種情況下，該路徑被視為相對於應用程式來源中指定路徑的相對路徑：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  annotations:
    # 解析為 'guestbook' 目錄
    argocd.argoproj.io/manifest-generate-paths: .
spec:
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
# ...
```

* **絕對路徑** 註解值可能是以 '/' 開頭的絕對路徑。在這種情況下，路徑被視為 Git 儲存庫內的絕對路徑：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  annotations:
    argocd.argoproj.io/manifest-generate-paths: /guestbook
spec:
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
# ...
```

* **多個路徑** 可以在註解中放入多個路徑。路徑必須用分號（`;`）分隔：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  annotations:
    # 解析為 'my-application' 和 'shared'
    argocd.argoproj.io/manifest-generate-paths: .;../shared
spec:
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: my-application
# ...
```

* **Glob 路徑** 註解可能包含一個 glob 模式路徑，它可以是 [Go filepath Match 函式](https://pkg.go.dev/path/filepath#Match)支援的任何模式：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  annotations:
    # 解析為頂層 shared 資料夾中符合 *-secret.yaml 模式的任何檔案
    argocd.argoproj.io/manifest-generate-paths: "/shared/*-secret.yaml"
spec:
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
# ...
```

> [!NOTE]
> 如果啟用了使用 `argocd.argoproj.io/manifest-generate-paths` 註解功能的應用程式清單產生，則只有此註解指定的資源才會被傳送到 CMP 伺服器進行清單產生，而不是整個儲存庫。為了確定適當的資源，會根據註解中提供的路徑計算一個共同的根路徑。應用程式路徑作為可被選為根的最深路徑。

### 應用程式同步逾時和抖動

Argo CD 對應用程式同步有逾時設定。當逾時到期時，它會定期觸發每個應用程式的重新整理。
對於大量的應用程式，這會導致重新整理佇列的尖峰，並可能導致 repo-server 元件的尖峰。為避免這種情況，您可以為同步逾時設定一個抖動，這將分散重新整理，讓 repo-server 有時間跟上。

抖動是可以新增到同步逾時的最大持續時間，因此如果同步逾時為 5 分鐘，抖動為 1 分鐘，那麼實際的逾時將在 5 到 6 分鐘之間。

您可以設定以下環境變數來設定抖動：

* `ARGOCD_RECONCILIATION_JITTER` - 應用於同步逾時的抖動。當值為 0 時停用。預設為 60。

## 限制應用程式協調速率

為了防止由於行為不當的應用程式或其他特定於環境的因素導致的高控制器資源使用或同步迴圈，
我們可以對應用程式控制器使用的工作佇列設定速率限制。可以設定兩種速率限制：

  * 全域速率限制
  * 每項速率限制

最終的速率限制器使用兩者的組合，並將最終的退避計算為 `max(globalBackoff, perItemBackoff)`。

### 全域速率限制

  預設情況下停用，它是一個簡單的基於桶的速率限制器，限制每秒可以排隊的項目數。
這對於防止大量應用程式同時排隊很有用。

您可以設定以下環境變數來設定桶限制器：

  * `WORKQUEUE_BUCKET_SIZE` - 單次突發中可以排隊的項目數。預設為 500。
  * `WORKQUEUE_BUCKET_QPS` - 每秒可以排隊的項目數。預設為 MaxFloat64，這會停用限制器。

### 每項速率限制

  預設情況下返回固定的基礎延遲/退避值，但可以設定為返回指數值。
每項速率限制器限制特定項目可以排隊的次數。這是基於指數退避，其中如果項目在短時間內多次排隊，則該項目的退避時間會指數級增加，但如果自上次排隊以來已過了一個設定的 `冷卻` 期，則退避會自動重置。

您可以設定以下環境變數來設定每項限制器：

  * `WORKQUEUE_FAILURE_COOLDOWN_NS`：冷卻期（奈秒），一旦項目的冷卻期過去，退避就會重置。如果設定為 0（預設值），則停用指數退避，例如，值：10 * 10^9 (=10s)
  * `WORKQUEUE_BASE_DELAY_NS`：基礎延遲（奈秒），這是指數退避公式中使用的初始退避。預設為 1000 (=1μs)
  * `WORKQUEUE_MAX_DELAY_NS`：最大延遲（奈秒），這是最大退避限制。預設為 3 * 10^9 (=3s)
  * `WORKQUEUE_BACKOFF_FACTOR`：退避因子，這是每次重試時退避增加的因子。預設為 1.5

用於計算項目退避時間的公式，其中 `numRequeue` 是項目已排隊的次數
，`lastRequeueTime` 是項目上次排隊的時間：

- 當 `WORKQUEUE_FAILURE_COOLDOWN_NS` != 0 時：

```
backoff = time.Since(lastRequeueTime) >= WORKQUEUE_FAILURE_COOLDOWN_NS ?
          WORKQUEUE_BASE_DELAY_NS :
          min(
              WORKQUEUE_MAX_DELAY_NS,
              WORKQUEUE_BASE_DELAY_NS * WORKQUEUE_BACKOFF_FACTOR ^ (numRequeue)
              )
```

- 當 `WORKQUEUE_FAILURE_COOLDOWN_NS` = 0 時：

```
backoff = WORKQUEUE_BASE_DELAY_NS
```

## HTTP 請求重試策略

在網路不穩定或發生暫時性伺服器錯誤的情況下，重試策略透過自動重新傳送失敗的請求來確保 HTTP 通訊的穩健性。它結合使用最大重試次數和退避間隔來防止伺服器過載或網路抖動。

### 設定重試

可以使用以下環境變數對重試邏輯進行微調：

* `ARGOCD_K8SCLIENT_RETRY_MAX` - 每個請求的最大重試次數。達到此計數後，請求將被丟棄。預設為 0（不重試）。
* `ARGOCD_K8SCLIENT_RETRY_BASE_BACKOFF` - 第一次重試嘗試的初始退避延遲（毫秒）。後續重試將使此退避時間加倍，直到達到最大閾值。預設為 100 毫秒。

### 退避策略

採用的退避策略是沒有抖動的簡單指數退避。退避時間隨著每次重試嘗試指數級增加，直到達到最大退避持續時間。

計算退避時間的公式是：

```
backoff = min(retryWaitMax, baseRetryBackoff * (2 ^ retryAttempt))
```
其中 `retryAttempt` 從 0 開始，每次後續重試加 1。

### 最大等待時間

對退避時間有上限，以防止重試之間等待時間過長。此上限由以下定義：

* `retryWaitMax` - 重試前等待的最大持續時間。這確保重試在合理的時間範圍內發生。預設為 10 秒。

### 不可重試的條件

並非所有 HTTP 回應都有資格重試。以下條件不會觸發重試：

* 狀態碼表示用戶端錯誤 (4xx) 的回應，除了 429 Too Many Requests。
* 狀態碼為 501 Not Implemented 的回應。


## CPU/記憶體分析

Argo CD 可選擇性地公開一個分析端點，可用於分析 Argo CD 元件的 CPU 和記憶體使用情況。
分析端點在每個元件的指標埠上可用。有關埠的更多資訊，請參閱[指標](./metrics.md)。
出於安全原因，分析端點預設為停用。可以透過將 [argocd-cmd-params-cm](argocd-cmd-params-cm.yaml) ConfigMap 的 `server.profile.enabled`
或 `controller.profile.enabled` 金鑰設定為 `true` 來啟用該端點。
啟用端點後，您可以使用 go profile 工具來收集 CPU 和記憶體設定檔。範例：

```bash
$ kubectl port-forward svc/argocd-metrics 8082:8082
$ go tool pprof http://localhost:8082/debug/pprof/heap
```
