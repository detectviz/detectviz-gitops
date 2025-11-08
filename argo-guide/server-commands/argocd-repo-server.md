# `argocd-repo-server` 指令參考

## argocd-repo-server

執行 ArgoCD 儲存庫伺服器

### 摘要

ArgoCD 儲存庫伺服器是一個內部服務，它會維護存放應用程式清單的 Git 儲存庫的本機快取，並負責產生和傳回 Kubernetes 清單。此指令會在前景執行儲存庫伺服器。可透過以下選項進行設定。

```
argocd-repo-server [flags]
```

### 選項

```
      --address string                                 監聽指定位址的連入連線 (預設 "0.0.0.0")
      --allow-oob-symlinks                             允許儲存庫中的越界符號連結 (不建議)
      --default-cache-expiration duration              預設快取過期時間 (預設 24h0m0s)
      --disable-helm-manifest-max-extracted-size       停用解壓縮 helm 清單封存檔時的大小上限
      --disable-oci-manifest-max-extracted-size        停用解壓縮 oci 清單封存檔時的大小上限
      --disable-tls                                    停用 gRPC 端點上的 TLS
      --helm-manifest-max-extracted-size string        解壓縮 helm 清單封存檔時的大小上限 (預設 "1G")
      --helm-registry-max-index-size string            註冊索引檔的大小上限 (預設 "1G")
  -h, --help                                           argocd-repo-server 的說明
      --include-hidden-directories                     從 Git 中包含隱藏目錄
      --logformat string                               設定記錄格式。可選：json|text (預設 "json")
      --loglevel string                                設定記錄層級。可選：debug|info|warn|error (預設 "info")
      --max-combined-directory-manifests-size string   目錄類型應用程式中清單檔案的組合大小上限 (預設 "10M")
      --metrics-address string                         監聽指定位址的指標 (預設 "0.0.0.0")
      --metrics-port int                               在指定埠上啟動指標伺服器 (預設 8084)
      --oci-layer-media-types strings                  允許的 OCI 媒體類型媒體類型逗號分隔清單。這僅適用於層內的媒體類型。(預設 [application/vnd.oci.image.layer.v1.tar,application/vnd.oci.image.layer.v1.tar+gzip,application/vnd.cncf.helm.chart.content.v1.tar+gzip])
      --oci-manifest-max-extracted-size string         解壓縮 oci 清單封存檔時的大小上限 (預設 "1G")
      --otlp-address string                            要傳送追蹤的 OpenTelemetry 收集器位址
      --otlp-attrs strings                             傳送追蹤時 OpenTelemetry 收集器的額外屬性清單，每個屬性以冒號分隔（例如 key:value）
      --otlp-headers stringToString                    與追蹤一起傳送的 OpenTelemetry 收集器額外標頭清單，標頭是以逗號分隔的鍵值對（例如 key1=value1,key2=value2）（預設 []）
      --otlp-insecure                                  OpenTelemetry 收集器不安全模式 (預設 true)
      --parallelismlimit int                           並行清單產生請求的數量限制。任何小於 1 的值表示沒有限制。
      --plugin-tar-exclude stringArray                 傳送 tarball 到外掛程式時要篩選的 glob。
      --plugin-use-manifest-generate-paths             將 argocd.argoproj.io/manifest-generate-paths 值中描述的資源傳遞給 cmpserver 以產生應用程式清單。
      --port int                                       監聽指定埠的連入連線 (預設 8081)
      --redis string                                   Redis 伺服器主機名稱和埠 (例如 argocd-redis:6379)。
      --redis-ca-certificate string                    Redis 伺服器 CA 憑證的路徑 (例如 /etc/certs/redis/ca.crt)。如果未指定，將使用系統信任的 CA 進行伺服器憑證驗證。
      --redis-client-certificate string                Redis 用戶端憑證的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-client-key string                        Redis 用戶端金鑰的路徑 (例如 /etc/certs/redis/client.crt)。
      --redis-compress string                          使用所需的壓縮演算法啟用傳送到 Redis 的資料壓縮。(可能的值：gzip, none) (預設 "gzip")
      --redis-insecure-skip-tls-verify                 略過 Redis 伺服器憑證驗證。
      --redis-use-tls                                  連線到 Redis 時使用 TLS。
      --redisdb int                                    Redis 資料庫。
      --repo-cache-expiration duration                 repo 狀態的快取過期時間，包括應用程式清單、應用程式詳細資料、清單產生、修訂版本元資料 (預設 24h0m0s)
      --revision-cache-expiration duration             快取修訂版本的快取過期時間 (預設 3m0s)
      --revision-cache-lock-timeout duration           鎖定快取的 TTL，以防止對修訂版本的重複請求，設為 0 以停用 (預設 10s)
      --sentinel stringArray                           Redis sentinel 主機名稱和埠 (例如 argocd-redis-ha-announce-0:6379)。
      --sentinelmaster string                          Redis sentinel 主機群組名稱。(預設 "master")
      --streamed-manifest-max-extracted-size string    解壓縮串流清單封存檔時的大小上限 (預設 "1G")
      --streamed-manifest-max-tar-size string          串流清單封存檔的大小上限 (預設 "100M")
      --tlsciphers string                              建立 TLS 連線時可接受的加密套件清單。使用 'list' 列出可用的加密套件。(預設 "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384")
      --tlsmaxversion string                           可接受的最大 SSL/TLS 版本 (可選：1.0|1.1|1.2|1.3) (預設 "1.3")
      --tlsminversion string                           可接受的最小 SSL/TLS 版本 (可選：1.0|1.1|1.2|1.3) (預設 "1.2")
```
