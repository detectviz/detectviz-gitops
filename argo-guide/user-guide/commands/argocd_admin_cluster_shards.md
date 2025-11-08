# `argocd admin cluster shards` 命令參考

## argocd admin cluster shards

列印每個控制器分片及其負責的 Kubernetes 資源預估部分的資訊。

```
argocd admin cluster shards [flags]
```

### 選項

```
      --app-state-cache-expiration duration   應用程式狀態的快取過期時間 (預設 1h0m0s)
      --as string                             模擬操作的使用者名稱
      --as-group stringArray                  模擬操作的群組，此旗標可以重複以指定多個群組。
      --as-uid string                         模擬操作的 UID
      --certificate-authority string          憑證授權單位的憑證檔案路徑
      --client-certificate string             TLS 的用戶端憑證檔案路徑
      --client-key string                     TLS 的用戶端金鑰檔案路徑
      --cluster string                        要使用的 kubeconfig 叢集名稱
      --context string                        要使用的 kubeconfig 上下文名稱
      --default-cache-expiration duration     快取過期預設值 (預設 24h0m0s)
      --disable-compression                   如果為 true, 則對所有對伺服器的請求停用回應壓縮
  -h, --help                                  shards 的說明
      --insecure-skip-tls-verify              如果為 true, 則不會檢查伺服器憑證的有效性。這將使您的 HTTPS 連線不安全
      --kubeconfig string                     kube config 的路徑。僅在叢集外才需要
  -n, --namespace string                      如果存在, 此 CLI 請求的命名空間範圍
      --password string                       API 伺服器基本驗證的密碼
      --port-forward-redis                    是否自動從目前的命名空間轉發 ha proxy redis 的連接埠？ (預設為 true)
      --proxy-url string                      如果提供, 此 URL 將用於透過代理連線
      --redis string                          Redis 伺服器主機名稱和連接埠 (例如 argocd-redis:6379)。
      --redis-ca-certificate string           Redis 伺服器 CA 憑證的路徑 (例如 /etc/certs/redis/ca.crt)。如果未指定, 將使用系統信任的 CA 進行伺服器憑證驗證。
      --redis-client-certificate string       Redis 用戶端憑證的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-client-key string               Redis 用戶端金鑰的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-compress string                 使用所需的壓縮演算法為傳送到 Redis 的資料啟用壓縮。(可能的值：gzip, none) (預設為 "gzip")
      --redis-insecure-skip-tls-verify        略過 Redis 伺服器憑證驗證。
      --redis-use-tls                         連線至 Redis 時使用 TLS。
      --redisdb int                           Redis 資料庫。
      --replicas int                          應用程式控制器複本計數。如果未指定, 則從執行中的控制器 pod 數量推斷
      --request-timeout string                在放棄單一伺服器請求之前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。(預設為 "0")
      --sentinel stringArray                  Redis sentinel 主機名稱和連接埠 (例如 argocd-redis-ha-announce-0:6379)。
      --sentinelmaster string                 Redis sentinel 主群組名稱。(預設為 "master")
      --server string                         Kubernetes API 伺服器的位址和連接埠
      --shard int                             叢集分片篩選器 (預設為 -1)
      --sharding-method string                分片方法。預設值：legacy。支援的分片方法為：[legacy, round-robin, consistent-hashing]  (預設為 "legacy")
      --tls-server-name string                如果提供, 此名稱將用於驗證伺服器憑證。如果未提供, 則使用用於聯絡伺服器的主機名稱。
      --token string                          用於向 API 伺服器進行驗證的持有者權杖
      --user string                           要使用的 kubeconfig 使用者名稱
      --username string                       API 伺服器基本驗證的使用者名稱
```

### 從父指令繼承的選項

```
      --argocd-context 字串           要使用的 Argo-CD 伺服器上下文名稱
      --auth-token 字串               驗證權杖；設定此選項或 ARGOCD_AUTH_TOKEN 環境變數
      --client-crt 字串               用戶端憑證檔案
      --client-crt-key 字串           用戶端憑證金鑰檔案
      --config 字串                   Argo CD 設定檔的路徑 (預設為 "/home/user/.config/argocd/config")
      --controller-name 字串          Argo CD 應用程式控制器的名稱；當控制器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_APPLICATION_CONTROLLER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-application-controller")
      --core                            如果設定為 true, 則 CLI 會直接與 Kubernetes 通訊, 而非與 Argo CD API 伺服器通訊
      --grpc-web                        啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後, 此選項很有用。
      --grpc-web-root-path 字串       啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後, 此選項很有用。設定 Web 根目錄。
  -H, --header 字串陣列                  為 Argo CD CLI 發出的所有請求設定額外的標頭。(可以重複多次以新增多個標頭, 也支援以逗號分隔的標頭)
      --http-retry-max 整數              與 Argo CD 伺服器建立 http 連線的最大重試次數
      --insecure                        略過伺服器憑證和網域驗證
      --kube-context 字串             將指令導向至給定的 kube-context
      --logformat 字串                  設定記錄格式。可選：json|text (預設為 "json")
      --loglevel 字串                 設定記錄層級。可選：debug|info|warn|error (預設為 "info")
      --plaintext                       停用 TLS
      --port-forward                    使用連接埠轉送連線至隨機的 argocd-server 連接埠
      --port-forward-namespace 字串   應用於連接埠轉送的命名空間名稱
      --prompts-enabled                 強制啟用或停用可選的互動式提示, 覆寫本機組態。如果未指定, 將使用本機組態值, 預設為 false。
      --redis-haproxy-name 字串       Redis HA Proxy 的名稱；當 HA Proxy 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_HAPROXY_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis-ha-haproxy")
      --redis-name 字串               Redis 部署的名稱；當 Redis 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis")
      --repo-server-name 字串         Argo CD Repo 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REPO_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-repo-server")
      --server-crt 字串               伺服器憑證檔案
      --server-name 字串              Argo CD API 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-server")
```

### 另請參閱

* [argocd admin cluster](argocd_admin_cluster.md)	 - 管理叢集組態

