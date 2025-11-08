# `argocd app get` 命令參考

## argocd app get

取得應用程式詳細資訊

```
argocd app get APPNAME [flags]
```

### 範例

```
  # 以寬格式取得應用程式 "my-app" 的基本詳細資訊
  argocd app get my-app -o wide
  
  # 以 YAML 格式取得應用程式 "my-app" 的詳細資訊
  argocd app get my-app -o yaml
  
  # 以 JSON 格式取得應用程式 "my-app" 的詳細資訊
  argocd get my-app -o json
  
  # 取得應用程式詳細資訊並包含目前操作的資訊
  argocd app get my-app --show-operation
  
  # 顯示應用程式參數和覆寫
  argocd app get my-app --show-params
  
  # 顯示應用程式 my-app 的 spec.sources 下位置 1 的來源的應用程式參數和覆寫
  argocd app get my-app --show-params --source-position 1
  
  # 顯示名為 "test" 的來源的應用程式參數和覆寫
  argocd app get my-app --show-params --source-name test
  
  # 擷取時重新整理應用程式資料
  argocd app get my-app --refresh
  
  # 執行硬性重新整理，包括重新整理應用程式資料和目標清單快取
  argocd app get my-app --hard-refresh
  
  # 取得應用程式詳細資訊並以樹狀格式顯示
  argocd app get my-app --output tree
  
  # 取得應用程式詳細資訊並以詳細的樹狀格式顯示
  argocd app get my-app --output tree=detailed
```

### 選項

```
  -N, --app-namespace 字串   僅從命名空間取得應用程式
      --hard-refresh           重新整理應用程式資料以及目標清單快取
  -h, --help                   get 的說明
  -o, --output 字串          輸出格式。可選：json|yaml|wide|tree (預設為 "wide")
      --refresh                擷取時重新整理應用程式資料
      --show-operation         顯示應用程式操作
      --show-params            顯示應用程式參數和覆寫
      --source-name 字串     應用程式來源清單中的來源名稱。
      --source-position int    應用程式來源清單中的來源位置。從 1 開始計數。(預設為 -1)
      --timeout uint           在此秒數後逾時
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

