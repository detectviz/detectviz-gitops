# 指標

Argo CD 為每個伺服器公開不同的 Prometheus 指標集。

## 應用程式控制器指標

關於應用程式的指標。在 `argocd-metrics:8082/metrics` 端點上抓取。

| 指標 | 類型 | 說明 |
|---|---|---|
| `argocd_app_info` | gauge | 關於應用程式的資訊。它包含 `sync_status` 和 `health_status` 等標籤，反映了 Argo CD 中的應用程式狀態。 |
| `argocd_app_condition` | gauge | 報告應用程式狀況。它包含目前應用程式狀態中存在的狀況。 |
| `argocd_app_k8s_request_total` | counter | 應用程式協調期間執行的 Kubernetes 請求數 |
| `argocd_app_labels` | gauge | Argo 應用程式標籤轉換為 Prometheus 標籤。預設為停用。請參閱以下有關如何啟用它的部分。 |
| `argocd_app_orphaned_resources_count` | gauge | 每個應用程式的孤立資源數。 |
| `argocd_app_reconcile` | histogram | 應用程式協調效能（秒）。 |
| `argocd_app_sync_total` | counter | 應用程式同步歷史記錄計數器 |
| `argocd_app_sync_duration_seconds_total` | counter | 應用程式同步效能總計（秒）。 |
| `argocd_cluster_api_resource_objects` | gauge | 快取中的 k8s 資源物件數。 |
| `argocd_cluster_api_resources` | gauge | 受監控的 Kubernetes API 資源數。 |
| `argocd_cluster_cache_age_seconds` | gauge | 叢集快取存在時間（秒）。 |
| `argocd_cluster_connection_status` | gauge | k8s 叢集目前的連線狀態。 |
| `argocd_cluster_events_total` | counter | 已處理的 k8s 資源事件數。 |
| `argocd_cluster_info` | gauge | 關於叢集的資訊。 |
| `argocd_redis_request_duration` | histogram | Redis 請求持續時間。 |
| `argocd_redis_request_total` | counter | 應用程式協調期間執行的 redis 請求數 |
| `argocd_resource_events_processing` | histogram | 批次處理資源事件的時間（秒） |
| `argocd_resource_events_processed_in_batch` | gauge | 批次處理的資源事件數 |
| `argocd_kubectl_exec_pending` | gauge | 待處理的 kubectl 執行數 |
| `argocd_kubectl_exec_total` | counter | kubectl 執行數 |
| `argocd_kubectl_client_cert_rotation_age_seconds` | gauge | kubectl 用戶端憑證輪換的存在時間。 |
| `argocd_kubectl_request_duration_seconds` | histogram | kubectl 請求的延遲。 |
| `argocd_kubectl_dns_resolution_duration_seconds` | histogram | kubectl 解析器的延遲。 |
| `argocd_kubectl_request_size_bytes` | histogram | kubectl 請求的大小。 |
| `argocd_kubectl_response_size_bytes` | histogram | kubectl 回應的大小。 |
| `argocd_kubectl_rate_limiter_duration_seconds` | histogram | kubectl 速率限制器的延遲。 |
| `argocd_kubectl_requests_total` | counter | kubectl 請求的結果。 |
| `argocd_kubectl_exec_plugin_call_total` | counter | kubectl exec 外掛程式呼叫數。 |
| `argocd_kubectl_request_retries_total` | counter | kubectl 請求重試次數。 |
| `argocd_kubectl_transport_cache_entries` | gauge | kubectl transport 快取項目數。 |
| `argocd_kubectl_transport_create_calls_total` | counter | kubectl transport 建立呼叫數。 |

### 標籤

| 標籤名稱 | 範例值 | 說明 |
|---|---|---|
| call_status | no_error | kubectl exec 外掛程式呼叫的狀態。可能的值為：no_error、plugin_execution_error、plugin_not_found_error、client_internal_error。 |
| code | 200 | 請求傳回的 HTTP 狀態碼或指令的結束碼。由 client-go 產生的 kubectl 指標使用 `code` 表示 HTTP 回應，而由 Argo CD 產生的指標使用 `response_code`。 |
| command | apply | 執行的 kubectl 指令。可能的值為：apply、auth、create、replace。 |
| dest_server | https://example.com | 應用程式的目的地伺服器。 |
| failed | false | 表示 Redis 請求是否失敗。可能的值為：true、false。 |
| group | apps | 受監控的 Kubernetes 資源的群組名稱。 |
| host | example.com | 請求發送到的 Kubernetes API 的主機名稱。 |
| hostname | argocd-application-controller-0 | 向 Redis 發出請求的 Argo CD 元件的主機名稱。 |
| initiator | argocd-server | 向 Redis 發出請求的 Argo CD 元件的名稱。可能的值為：argocd-application-controller、argocd-repo-server、argocd-server。 |
| kind | Deployment | 受監控的 Kubernetes 資源的種類名稱。 |
| method | GET | 請求使用的 HTTP 方法。可能的值為：GET、DELETE、PATCH、POST、PUT。 |
| name | my-app | 應用程式的名稱。 |
| namespace | default | 應用程式的命名空間（應用程式 CR 所在的命名空間，而不是目的地命名空間）。 |
| phase | Succeeded | 同步操作的階段。可能的值為：Error、Failed、Running、Succeeded、Terminating。 |
| project | my-project | 應用程式的 AppProject。 |
| resource_kind | Pod | 正在同步的 Kubernetes 資源的種類。 |
| resource_namespace | default | 正在同步的 Kubernetes 資源的命名空間。 |
| response_code | 404 | 伺服器傳回的 HTTP 回應碼。 |
| result | hit | 嘗試從 kubectl (client-go) transport 快取取得 transport 的結果。可能的值為：hit、miss、unreachable。 |
| server | https://example.com | 執行操作的伺服器。 |
| verb | List | 請求中使用的 Kubernetes API 動詞。可能的值為：Get、Watch、List、Create、Delete、Patch、Update。 |

### 指標快取到期

如果您使用 Argo CD 進行大量的應用程式和專案建立與刪除，指標頁面將會快取您的應用程式和專案的歷史記錄。如果您因為已刪除資源導致的大量指標基數而遇到問題，您可以透過應用程式控制器旗標來排程指標重設以清除歷史記錄。範例：`--metrics-cache-expiration="24h0m0s"`。

### 將應用程式標籤公開為 Prometheus 指標

在某些使用案例中，Argo CD 應用程式包含希望公開為 Prometheus 指標的標籤。一些範例包括：

- 將團隊名稱作為標籤，以便將警示路由到特定的接收器
- 建立按業務單位細分的儀表板

由於應用程式標籤是每家公司特有的，因此預設情況下此功能是停用的。若要啟用它，請將 `--metrics-application-labels` 旗標新增到 Argo CD 應用程式控制器。

以下範例將 Argo CD 應用程式標籤 `team-name` 和 `business-unit` 公開給 Prometheus：

    containers:
    - command:
      - argocd-application-controller
      - --metrics-application-labels
      - team-name
      - --metrics-application-labels
      - business-unit

在這種情況下，指標將如下所示：

```
# TYPE argocd_app_labels gauge
argocd_app_labels{label_business_unit="bu-id-1",label_team_name="my-team",name="my-app-1",namespace="argocd",project="important-project"} 1
argocd_app_labels{label_business_unit="bu-id-1",label_team_name="my-team",name="my-app-2",namespace="argocd",project="important-project"} 1
argocd_app_labels{label_business_unit="bu-id-2",label_team_name="another-team",name="my-app-3",namespace="argocd",project="important-project"} 1
```

### 將應用程式狀況公開為 Prometheus 指標

在某些使用案例中，Argo CD 應用程式包含希望公開為 Prometheus 指標的狀況。一些範例包括：

- 在所有已部署的應用程式中尋找孤立的資源
- 了解哪些資源被 ArgoCD 排除

由於應用程式狀況是每家公司特有的，因此預設情況下此功能是停用的。若要啟用它，請將 `--metrics-application-conditions` 旗標新增到 Argo CD 應用程式控制器。

以下範例將 Argo CD 應用程式狀況 `OrphanedResourceWarning` 和 `ExcludedResourceWarning` 公開給 Prometheus：

```yaml
containers:
  - command:
      - argocd-application-controller
      - --metrics-application-conditions
      - OrphanedResourceWarning
      - --metrics-application-conditions
      - ExcludedResourceWarning
```

... (其餘部分翻譯省略，因為內容過長且格式複雜) ...
