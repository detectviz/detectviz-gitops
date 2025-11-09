# `argocd app sync` 命令參考

## argocd app sync

將應用程式同步至其目標狀態

```
argocd app sync [APPNAME... | -l selector | --project project-name] [flags]
```

### 範例

```
  # 同步一個應用程式
  argocd app sync my-app

  # 同步多個應用程式
  argocd app sync my-app other-app

  # 按標籤同步應用程式，在此範例中，我們同步屬於另一個應用程式的子應用程式 (又稱應用程式的應用程式)
  argocd app sync -l app.kubernetes.io/instance=my-app
  argocd app sync -l app.kubernetes.io/instance!=my-app
  argocd app sync -l app.kubernetes.io/instance
  argocd app sync -l '!app.kubernetes.io/instance'
  argocd app sync -l 'app.kubernetes.io/instance notin (my-app,other-app)'

  # 同步多來源應用程式的特定來源的特定修訂版本
  argocd app sync my-app --revisions 0.0.1 --source-positions 1 --revisions 0.0.2 --source-positions 2
  argocd app sync my-app --revisions 0.0.1 --source-names my-chart --revisions 0.0.2 --source-names my-values

  # 同步特定資源
  # 資源格式應為 GROUP:KIND:NAME。如果未指定 GROUP，則為 :KIND:NAME
  argocd app sync my-app --resource :Service:my-service
  argocd app sync my-app --resource argoproj.io:Rollout:my-rollout
  argocd app sync my-app --resource '!apps:Deployment:my-service'
  argocd app sync my-app --resource apps:Deployment:my-service --resource :Service:my-service
  argocd app sync my-app --resource '!*:Service:*'
  # 如果應用程式在不同命名空間中有同名資源，請指定命名空間
  argocd app sync my-app --resource argoproj.io:Rollout:my-namespace/my-rollout
```

### 選項

```
  -N, --app-namespace 字串                              僅同步命名空間中的應用程式
      --apply-out-of-sync-only                            僅同步非同步資源
      --assumeYes                                         對所有使用者查詢或提示假設回答為「是」
      --async                                             繼續之前不要等待應用程式同步
      --dry-run                                           預覽套用而不影響叢集
      --force                                             使用強制套用
  -h, --help                                              sync 的說明
      --ignore-normalizer-jq-execution-timeout duration   設定忽略正規化器 JQ 執行逾時 (預設為 1 秒)
      --info 字串陣列                                  同步過程中一組鍵值對的清單。這些資訊將會保留在應用程式中。
      --label 字串陣列                                 僅同步具有特定標籤的資源。此選項可重複指定。
      --local 字串                                      本機目錄的路徑。當此旗標存在時，不會進行 git 查詢
      --local-repo-root 字串                            儲存庫根目錄的路徑。與 --local 一起使用可設定儲存庫根目錄 (預設為 "/")
  -o, --output 字串                                     輸出格式。可選：json|yaml|wide|tree|tree=detailed (預設為 "wide")
      --preview-changes                                   在同步應用程式前預覽目標和即時狀態之間的差異，並等待使用者確認
      --project 字串陣列                               同步屬於指定專案的應用程式。此選項可重複指定。
      --prune                                             允許刪除非預期資源
      --replace                                           使用 kubectl create/replace 取代 apply
      --resource 字串陣列                              僅同步特定資源，格式為 GROUP:KIND:NAME 或 !GROUP:KIND:NAME。欄位可為空，且可使用 '*'。此選項可重複指定
      --retry-backoff-duration duration                   重試退避基本持續時間。輸入必須是持續時間 (例如 2m, 1h) (預設為 5s)
      --retry-backoff-factor int                          每次重試失敗後乘以基本持續時間的因子 (預設為 2)
      --retry-backoff-max-duration duration               最大重試退避持續時間。輸入必須是持續時間 (例如 2m, 1h) (預設為 3m0s)
      --retry-limit int                                   允許的最大同步重試次數
      --retry-refresh                                     表示重試時是否應使用最新的修訂版本，而非初始版本
      --revision 字串                                   同步至特定修訂版本。保留參數覆寫
      --revisions 字串陣列                             在 source-positions 的來源位置顯示特定修訂版本的清單
  -l, --selector 字串                                   同步符合此標籤的應用程式。支援 '=', '==', '!=', in, notin, exists & not exists。相符的應用程式必須滿足所有指定的標籤限制。
      --server-side                                       同步應用程式時使用伺服器端套用
      --source-names 字串陣列                          來源名稱清單。預設為空陣列。
      --source-positions int64Slice                       來源位置清單。預設為空陣列。從 1 開始計數。(預設為 [])
      --strategy 字串                                   同步策略 (可選：apply|hook)
      --timeout uint                                      在此秒數後逾時
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

