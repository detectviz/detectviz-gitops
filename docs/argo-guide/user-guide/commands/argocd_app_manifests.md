# `argocd app manifests` 命令參考

## argocd app manifests

列印應用程式的清單

```
argocd app manifests APPNAME [flags]
```

### 範例

```
  # 取得應用程式的清單
  argocd app manifests my-app
  
  # 取得特定修訂版本中應用程式的清單
  argocd app manifests my-app --revision 0.0.1
  
  # 取得多來源應用程式中特定來源在特定修訂版本的清單
  argocd app manifests my-app --revisions 0.0.1 --source-names src-base --revisions 0.0.2 --source-names src-values
  
  # 取得多來源應用程式中特定來源在特定修訂版本的清單
  argocd app manifests my-app --revisions 0.0.1 --source-positions 1 --revisions 0.0.2 --source-positions 2
```

### 選項

```
  -h, --help                          manifests 的說明
      --local 字串                  如果設定，顯示本機產生的清單。值是清單儲存庫中應用程式清單的絕對路徑。範例：'/home/username/apps/env/app-1'。
      --local-repo-root 字串        本機儲存庫根目錄的路徑。與 --local 一起使用可設定儲存庫根目錄。範例：'/home/username/apps'。(預設為 ".")
      --revision 字串               在特定修訂版本顯示清單
      --revisions 字串陣列         在 source-positions 中來源位置的特定修訂版本顯示清單
      --source 字串                 清單的來源。可選：live|git (預設為 "git")
      --source-names 字串陣列      來源名稱清單。預設為空陣列。
      --source-positions int64Slice   來源位置清單。預設為空陣列。從 1 開始計數。(預設為 [])
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

