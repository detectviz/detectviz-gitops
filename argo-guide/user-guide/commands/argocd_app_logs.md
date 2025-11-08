# `argocd app logs` 命令參考

## argocd app logs

取得應用程式 pod 的日誌

```
argocd app logs APPNAME [flags]
```

### 範例

```
  # 取得與應用程式 "my-app" 關聯的 pod 的日誌
  argocd app logs my-app
  
  # 取得與特定資源群組中應用程式 "my-app" 關聯的 pod 的日誌
  argocd app logs my-app --group my-group
  
  # 取得與特定資源種類中應用程式 "my-app" 關聯的 pod 的日誌
  argocd app logs my-app --kind my-kind
  
  # 取得與特定命名空間中應用程式 "my-app" 關聯的 pod 的日誌
  argocd app logs my-app --namespace my-namespace
  
  # 取得與特定資源名稱中應用程式 "my-app" 關聯的 pod 的日誌
  argocd app logs my-app --name my-resource
  
  # 即時串流應用程式 "my-app" 的日誌
  argocd app logs my-app -f
  
  # 取得應用程式 "my-app" 的最後 N 行日誌
  argocd app logs my-app --tail 100
  
  # 取得自指定秒數前的日誌
  argocd app logs my-app --since-seconds 3600
  
  # 取得直到指定時間的日誌 (格式："2023-10-10T15:30:00Z")
  argocd app logs my-app --until-time "2023-10-10T15:30:00Z"
  
  # 篩選日誌以僅顯示包含特定字串的日誌
  argocd app logs my-app --filter "error"
  
  # 篩選日誌以僅顯示包含特定字串並區分大小寫的日誌
  argocd app logs my-app --filter "error" --match-case
  
  # 取得 pod 中特定容器的日誌
  argocd app logs my-app -c my-container
  
  # 取得先前終止的容器日誌
  argocd app logs my-app -p
```

### 選項

```
  -c, --container 字串    可選的容器名稱
      --filter 字串       顯示包含此字串的日誌
  -f, --follow              指定是否應串流日誌
      --group 字串        資源群組
  -h, --help                logs 的說明
      --kind 字串         資源種類
  -m, --match-case          指定篩選器是否應區分大小寫
      --name 字串         資源名稱
      --namespace 字串    資源命名空間
  -p, --previous            指定是否應傳回先前終止的容器日誌
      --since-seconds int   從目前時間往前推算的相對時間 (以秒為單位)，從該時間點開始顯示日誌
      --tail int            要顯示的日誌結尾的行數
      --until-time 字串   顯示直到此時間的日誌
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
      --redis-compress 字串           如果應用程式控制器已啟用 redis 壓縮, 請啟用此選項。(可能的值：gzip, none) (預設為 "gzip")
      --redis-haproxy-name 字串       Redis HA Proxy 的名稱；當 HA Proxy 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_HAPROXY_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis-ha-haproxy")
      --redis-name 字串               Redis 部署的名稱；當 Redis 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis")
      --repo-server-name 字串         Argo CD Repo 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REPO_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-repo-server")
      --server 字串                   Argo CD 伺服器位址
      --server-crt 字串               伺服器憑證檔案
      --server-name 字串              Argo CD API 伺服器的名稱；當伺服器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_SERVER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-server")
```

### 另請參閱

* [argocd app](argocd_app.md)	 - 管理應用程式

