# `argocd-application-controller` 指令參考

## argocd-application-controller

執行 ArgoCD 應用程式控制器

### 摘要

ArgoCD 應用程式控制器是一個 Kubernetes 控制器，可持續監控執行中的應用程式，並將目前的即時狀態與期望的目標狀態（如儲存庫中所指定）進行比較。此指令會在前景執行應用程式控制器。可透過以下選項進行設定。

```
argocd-application-controller [flags]
```

### 選項

```
      --app-hard-resync int                                       應用程式強制重新同步的時間週期（秒）。
      --app-resync int                                            應用程式重新同步的時間週期（秒）。（預設 120）
      --app-resync-jitter int                                     應用程式重新同步時，可增加的延遲抖動最大時間週期（秒）。（預設 60）
      --app-state-cache-expiration duration                       應用程式狀態的快取過期時間（預設 1h0m0s）
      --application-namespaces strings                            允許應用程式從中進行協調的其他命名空間清單
      --as string                                                 要模擬操作的使用者名稱
      --as-group stringArray                                      要模擬操作的群組，此旗標可重複使用以指定多個群組。
      --as-uid string                                             要模擬操作的 UID
      --certificate-authority string                              憑證授權單位的憑證檔案路徑
      --client-certificate string                                 TLS 的用戶端憑證檔案路徑
      --client-key string                                         TLS 的用戶端金鑰檔案路徑
      --cluster string                                            要使用的 kubeconfig 叢集名稱
      --commit-server string                                      Commit 伺服器位址。（預設 "argocd-commit-server:8086"）
      --context string                                            要使用的 kubeconfig 上下文名稱
      --default-cache-expiration duration                         預設快取過期時間（預設 24h0m0s）
      --disable-compression                                       如果為 true，則選擇不對所有對伺服器的請求進行回應壓縮
      --dynamic-cluster-distribution-enabled                      啟用動態叢集分發。
      --enable-k8s-event none                                     啟用 ArgoCD 使用 k8s 事件。若要停用所有事件，請將值設為 none。（例如 --enable-k8s-event=none），若要啟用特定事件，請將值設為 `event reason`。（例如 --enable-k8s-event=StatusRefreshed,ResourceCreated）（預設 [all]）
      --gloglevel int                                             設定 glog 記錄層級
  -h, --help                                                      argocd-application-controller 的說明
      --hydrator-enabled                                          啟用 Hydrator 的功能旗標。預設 ("false")
      --ignore-normalizer-jq-execution-timeout-seconds duration   設定忽略正規化器 JQ 執行逾時
      --insecure-skip-tls-verify                                  如果為 true，則不會檢查伺服器憑證的有效性。這會使您的 HTTPS 連線不安全
      --kubeconfig string                                         kube config 的路徑。僅在叢集外才需要
      --kubectl-parallelism-limit int                             允許的並行 kubectl fork/execs 數量。任何小於 1 的值表示沒有限制。（預設 20）
      --logformat string                                          設定記錄格式。可選：json|text（預設 "json"）
      --loglevel string                                           設定記錄層級。可選：debug|info|warn|error（預設 "info"）
      --metrics-application-conditions strings                    將新增到 argocd_application_conditions 指標的應用程式條件清單
      --metrics-application-labels strings                        將新增到 argocd_application_labels 指標的應用程式標籤清單
      --metrics-cache-expiration duration                         Prometheus 指標快取過期時間（預設停用。例如 24h0m0s）
      --metrics-cluster-labels strings                            將新增到 argocd_cluster_labels 指標的叢集標籤清單
      --metrics-port int                                          在指定埠上啟動指標伺服器（預設 8082）
  -n, --namespace string                                          如果存在，則為此 CLI 請求的命名空間範圍
      --operation-processors int                                  應用程式操作處理器數量（預設 10）
      --otlp-address string                                       要傳送追蹤的 OpenTelemetry 收集器位址
      --otlp-attrs strings                                        傳送追蹤時 OpenTelemetry 收集器的額外屬性清單，每個屬性以冒號分隔（例如 key:value）
      --otlp-headers stringToString                               與追蹤一起傳送的 OpenTelemetry 收集器額外標頭清單，標頭是以逗號分隔的鍵值對（例如 key1=value1,key2=value2）（預設 []）
      --otlp-insecure                                             OpenTelemetry 收集器不安全模式（預設 true）
      --password string                                           對 API 伺服器進行基本驗證的密碼
      --persist-resource-health                                   啟用將受管理資源的健康狀況儲存在 Application CRD 中
      --proxy-url string                                          如果提供，此 URL 將用於透過代理連線
      --redis string                                              Redis 伺服器主機名稱和埠（例如 argocd-redis:6379）。
      --redis-ca-certificate string                               Redis 伺服器 CA 憑證的路徑（例如 /etc/certs/redis/ca.crt）。如果未指定，將使用系統信任的 CA 進行伺服器憑證驗證。
      --redis-client-certificate string                           Redis 用戶端憑證的路徑（例如 /etc/certs/redis/client.crt）。
      --redis-client-key string                                   Redis 用戶端金鑰的路徑（例如 /etc/certs/redis/client.crt）。
      --redis-compress string                                     使用所需的壓縮演算法啟用傳送到 Redis 的資料壓縮。（可能的值：gzip, none）（預設 "gzip"）
      --redis-insecure-skip-tls-verify                            略過 Redis 伺服器憑證驗證。
      --redis-use-tls                                             連線到 Redis 時使用 TLS。
      --redisdb int                                               Redis 資料庫。
      --repo-error-grace-period-seconds int                       與 repo 伺服器通訊時，忽略連續錯誤的寬限期（秒）。（預設 180）
      --repo-server string                                        Repo 伺服器位址。（預設 "argocd-repo-server:8081"）
      --repo-server-plaintext                                     停用與 repo 伺服器連線的 TLS
      --repo-server-strict-tls                                    是否對 repo 伺服器提供的 TLS 憑證使用嚴格驗證
      --repo-server-timeout-seconds int                           Repo 伺服器 RPC 呼叫逾時秒數。（預設 60）
      --request-timeout string                                    放棄單一伺服器請求前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。（預設 "0"）
      --self-heal-backoff-cap-seconds int                         指定應用程式自我修復嘗試之間的指數退避最大逾時時間（預設 300）
      --self-heal-backoff-cooldown-seconds int                    指定應用程式在自我修復退避重設前需要保持同步的時間段（預設 330）
      --self-heal-backoff-factor int                              指定應用程式自我修復嘗試之間的指數逾時因子（預設 3）
      --self-heal-backoff-timeout-seconds int                     指定自我修復嘗試之間的指數退避初始逾時時間（預設 2）
      --self-heal-timeout-seconds int                             指定應用程式自我修復嘗試之間的逾時時間
      --sentinel stringArray                                      Redis sentinel 主機名稱和埠（例如 argocd-redis-ha-announce-0:6379）。
      --sentinelmaster string                                     Redis sentinel 主機群組名稱。（預設 "master"）
      --server string                                             Kubernetes API 伺服器的位址和埠
      --server-side-diff-enabled                                  啟用 ServerSide diff 的功能旗標。預設 ("false")
      --sharding-method string                                    啟用分片方法的選擇。支援的分片方法有：[legacy, round-robin, consistent-hashing]（預設 "legacy"）
      --status-processors int                                     應用程式狀態處理器數量（預設 20）
      --sync-timeout int                                          指定同步終止前的逾時時間。0 表示沒有逾時（預設 0）。
      --tls-server-name string                                    如果提供，此名稱將用於驗證伺服器憑證。如果未提供，則使用聯繫伺服器的主機名稱。
      --token string                                              用於對 API 伺服器進行驗證的持有者權杖
      --user string                                               要使用的 kubeconfig 使用者名稱
      --username string                                           對 API 伺服器進行基本驗證的使用者名稱
      --wq-backoff-factor float                                   設定工作佇列每項目速率限制器的退避因子，預設為 1.5（預設 1.5）
      --wq-basedelay-ns duration                                  設定工作佇列每項目速率限制器的基礎延遲時間（奈秒），預設 1000000 (1ms)（預設 1ms）
      --wq-bucket-qps float                                       設定工作佇列速率限制器桶的 QPS，預設設為 MaxFloat64，這會停用桶限制器（預設 1.7976931348623157e+308）
      --wq-bucket-size int                                        設定工作佇列速率限制器桶的大小，預設 500（預設 500）
      --wq-cooldown-ns duration                                   設定工作佇列每項目速率限制器的冷卻時間（奈秒），預設 0（停用每項目速率限制器）
      --wq-maxdelay-ns duration                                   設定工作佇列每項目速率限制器的最大延遲時間（奈秒），預設 1000000000 (1s)（預設 1s）
```
