# `argocd-server` 指令參考

## argocd-server

執行 ArgoCD API 伺服器

### 摘要

API 伺服器是一個 gRPC/REST 伺服器，它會公開供 Web UI、CLI 和 CI/CD 系統使用的 API。此指令會在前景執行 API 伺服器。可透過以下選項進行設定。

```
argocd-server [flags]
```

### 範例

```
  # 使用預設設定啟動 Argo CD API 伺服器
  $ argocd-server
  
  # 在自訂埠上啟動 Argo CD API 伺服器並啟用追蹤
  $ argocd-server --port 8888 --otlp-address localhost:4317
```

### 選項

```
      --address string                                  監聽指定位址 (預設 "0.0.0.0")
      --api-content-types string                        非 GET API 請求允許的內容類型分號分隔清單。如果為空，則允許任何內容類型。(預設 "application/json")
      --app-state-cache-expiration duration             應用程式狀態的快取過期時間 (預設 1h0m0s)
      --application-namespaces strings                  可在其中管理應用程式資源的其他命名空間清單
      --appset-allowed-scm-providers strings            允許的自訂 SCM 提供者 API URL 清單。此限制不適用於不接受自訂 API URL 的 SCM 或 PR 產生器。（預設值：空值 = 全部）
      --appset-enable-github-api-metrics                為使用 GitHub API 的產生器啟用 GitHub API 指標
      --appset-enable-new-git-file-globbing             在 Git 檔案產生器中啟用新的 globbing。
      --appset-enable-scm-providers                     啟用從 SCM 提供者擷取資訊，由 SCM 和 PR 產生器使用（預設：true）（預設 true）
      --appset-scm-root-ca-path string                  為自簽署 TLS 憑證提供根 CA 路徑
      --as string                                       用於模擬操作的使用者名稱
      --as-group stringArray                            用於模擬操作的群組，此旗標可重複使用以指定多個群組。
      --as-uid string                                   用於模擬操作的 UID
      --basehref string                                 index.html 中 base href 的值。如果 Argo CD 在反向代理後以不同於 / 的子路徑執行，則使用此選項 (預設 "/")
      --certificate-authority string                    憑證授權單位的憑證檔案路徑
      --client-certificate string                       TLS 的用戶端憑證檔案路徑
      --client-key string                               TLS 的用戶端金鑰檔案路徑
      --cluster string                                  要使用的 kubeconfig 叢集名稱
      --connection-status-cache-expiration duration     叢集/儲存庫連線狀態的快取過期時間 (預設 1h0m0s)
      --content-security-policy value                   將 HTTP 回應中的 Content-Security-Policy 標頭設為指定值。若要停用，請設為 ""。(預設 "frame-ancestors 'self';")
      --context string                                  要使用的 kubeconfig 上下文名稱
      --default-cache-expiration duration               預設快取過期時間 (預設 24h0m0s)
      --dex-server string                               Dex 伺服器位址 (預設 "argocd-dex-server:5556")
      --dex-server-plaintext                            使用純文字用戶端 (非 TLS) 連線到 dex 伺服器
      --dex-server-strict-tls                           連線到 dex 伺服器時執行嚴格的 TLS 憑證驗證
      --disable-auth                                    停用用戶端驗證
      --disable-compression                             如果為 true，則選擇不對所有對伺服器的請求進行回應壓縮
      --enable-gzip                                     啟用 GZIP 壓縮 (預設 true)
      --enable-k8s-event none                           啟用 ArgoCD 使用 k8s 事件。若要停用所有事件，請將值設為 none。（例如 --enable-k8s-event=none），若要啟用特定事件，請將值設為 `event reason`。（例如 --enable-k8s-event=StatusRefreshed,ResourceCreated）（預設 [all]）
      --enable-proxy-extension                          啟用代理擴充功能
      --gloglevel int                                   設定 glog 記錄層級
  -h, --help                                            argocd-server 的說明
      --hydrator-enabled                                啟用 Hydrator 的功能旗標。預設 ("false")
      --insecure                                        在沒有 TLS 的情況下執行伺服器
      --insecure-skip-tls-verify                        如果為 true，則不會檢查伺服器憑證的有效性。這會使您的 HTTPS 連線不安全
      --kubeconfig string                               kube config 的路徑。僅在叢集外才需要
      --logformat string                                設定記錄格式。可選：json|text (預設 "json")
      --login-attempts-expiration duration              失敗登入嘗試的快取過期時間。已棄用：此旗標未使用，將在未來版本中移除。(預設 24h0m0s)
      --loglevel string                                 設定記錄層級。可選：debug|info|warn|error (預設 "info")
      --metrics-address string                          監聽指定位址的指標 (預設 "0.0.0.0")
      --metrics-port int                                在指定埠上啟動指標 (預設 8083)
  -n, --namespace string                                如果存在，則為此 CLI 請求的命名空間範圍
      --oidc-cache-expiration duration                  OIDC 狀態的快取過期時間 (預設 3m0s)
      --otlp-address string                             要傳送追蹤的 OpenTelemetry 收集器位址
      --otlp-attrs strings                              傳送追蹤時 OpenTelemetry 收集器的額外屬性清單，每個屬性以冒號分隔（例如 key:value）
      --otlp-headers stringToString                     與追蹤一起傳送的 OpenTelemetry 收集器額外標頭清單，標頭是以逗號分隔的鍵值對（例如 key1=value1,key2=value2）（預設 []）
      --otlp-insecure                                   OpenTelemetry 收集器不安全模式 (預設 true)
      --password string                                 對 API 伺服器進行基本驗證的密碼
      --port int                                        監聽指定埠 (預設 8080)
      --proxy-url string                                如果提供，此 URL 將用於透過代理連線
      --redis string                                    Redis 伺服器主機名稱和埠 (例如 argocd-redis:6379)。
      --redis-ca-certificate string                     Redis 伺服器 CA 憑證的路徑 (例如 /etc/certs/redis/ca.crt)。如果未指定，將使用系統信任的 CA 進行伺服器憑證驗證。
      --redis-client-certificate string                 Redis 用戶端憑證的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-client-key string                         Redis 用戶端金鑰的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-compress string                           使用所需的壓縮演算法啟用傳送到 Redis 的資料壓縮。(可能的值：gzip, none) (預設 "gzip")
      --redis-insecure-skip-tls-verify                  略過 Redis 伺服器憑證驗證。
      --redis-use-tls                                   連線到 Redis 時使用 TLS。
      --redisdb int                                     Redis 資料庫。
      --repo-cache-expiration duration                  repo 狀態的快取過期時間，包括應用程式清單、應用程式詳細資料、清單產生、修訂版本元資料 (預設 24h0m0s)
      --repo-server string                              Repo 伺服器位址 (預設 "argocd-repo-server:8081")
      --repo-server-default-cache-expiration duration   預設快取過期時間 (預設 24h0m0s)
      --repo-server-plaintext                           使用純文字用戶端 (非 TLS) 連線到儲存庫伺服器
      --repo-server-redis string                        Redis 伺服器主機名稱和埠 (例如 argocd-redis:6379)。
      --repo-server-redis-ca-certificate string         Redis 伺服器 CA 憑證的路徑 (例如 /etc/certs/redis/ca.crt)。如果未指定，將使用系統信任的 CA 進行伺服器憑證驗證。
      --repo-server-redis-client-certificate string     Redis 用戶端憑證的路徑 (例如 /etc/certs/redis/client.crt)。
      --repo-server-redis-client-key string             Redis 用戶端金鑰的路徑 (例如 /etc/certs/redis/client.crt)。
      --repo-server-redis-compress string               使用所需的壓縮演算法啟用傳送到 Redis 的資料壓縮。(可能的值：gzip, none) (預設 "gzip")
      --repo-server-redis-insecure-skip-tls-verify      略過 Redis 伺服器憑證驗證。
      --repo-server-redis-use-tls                       連線到 Redis 時使用 TLS。
      --repo-server-redisdb int                         Redis 資料庫。
      --repo-server-sentinel stringArray                Redis sentinel 主機名稱和埠 (例如 argocd-redis-ha-announce-0:6379)。
      --repo-server-sentinelmaster string               Redis sentinel 主機群組名稱。(預設 "master")
      --repo-server-strict-tls                          連線到 repo 伺服器時執行嚴格的 TLS 憑證驗證
      --repo-server-timeout-seconds int                 Repo 伺服器 RPC 呼叫逾時秒數。(預設 60)
      --request-timeout string                          放棄單一伺服器請求前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。（預設 "0"）
      --revision-cache-expiration duration              快取修訂版本的快取過期時間 (預設 3m0s)
      --revision-cache-lock-timeout duration            鎖定快取的 TTL，以防止對修訂版本的重複請求，設為 0 以停用 (預設 10s)
      --rootpath string                                 如果 Argo CD 在反向代理後以不同於 / 的子路徑執行，則使用此選項
      --sentinel stringArray                            Redis sentinel 主機名稱和埠 (例如 argocd-redis-ha-announce-0:6379)。
      --sentinelmaster string                           Redis sentinel 主機群組名稱。(預設 "master")
      --server string                                   Kubernetes API 伺服器的位址和埠
      --staticassets string                             包含其他靜態資產的目錄路徑 (預設 "/shared/app")
      --sync-with-replace-allowed                       是否允許使用者從 UI/CLI 選擇取代同步 (預設 true)
      --tls-server-name string                          如果提供，此名稱將用於驗證伺服器憑證。如果未提供，則使用聯繫伺服器的主機名稱。
      --tlsciphers string                               建立 TLS 連線時可接受的加密套件清單。使用 'list' 列出可用的加密套件。(預設 "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384")
      --tlsmaxversion string                            可接受的最大 SSL/TLS 版本 (可選：1.0|1.1|1.2|1.3) (預設 "1.3")
      --tlsminversion string                            可接受的最小 SSL/TLS 版本 (可選：1.0|1.1|1.2|1.3) (預設 "1.2")
      --token string                                    用於對 API 伺服器進行驗證的持有者權杖
      --user string                                     要使用的 kubeconfig 使用者名稱
      --username string                                 對 API 伺服器進行基本驗證的使用者名稱
      --webhook-parallelism-limit int                   同時處理的 Webhook 請求數 (預設 50)
      --x-frame-options value                           將 HTTP 回應中的 X-Frame-Options 標頭設為指定值。若要停用，請設為 ""。(預設 "sameorigin")
```

### 另請參閱

* [argocd-server version](argocd-server_version.md)	 - 列印版本資訊
