# `argocd proj set` 命令參考

## argocd proj set

設定專案參數

```
argocd proj set PROJECT [flags]
```

### 範例

```
  # 為名為 PROJECT 的專案設定專案參數，並允許一些叢集資源 [RES1,RES2,...]
  argocd proj set PROJECT --allow-cluster-resource [RES1,RES2,...]
  
  # 為名為 PROJECT 的專案設定專案參數，並拒絕一些命名空間資源 [RES1,RES2,...]
  argocd proj set PROJECT --deny-namespaced-resource [RES1,RES2,...]
```

### 選項

```
      --allow-cluster-resource stringArray      允許的叢集層級資源清單
      --allow-namespaced-resource stringArray   允許的命名空間層級資源清單
      --deny-cluster-resource stringArray       拒絕的叢集層級資源清單
      --deny-namespaced-resource stringArray    拒絕的命名空間層級資源清單
      --description 字串                      專案描述
  -d, --dest stringArray                        允許的目的地伺服器和命名空間 (例如 https://192.168.99.100:8443,default)
      --dest-service-accounts stringArray       目的地伺服器、命名空間和目標服務帳號 (例如 https://192.168.99.100:8443,default,default-sa)
  -h, --help                                    set 的說明
      --orphaned-resources                      啟用孤立資源監控
      --orphaned-resources-warn                 指定當偵測到孤立資源時，應用程式是否應顯示警告狀態
      --signature-keys strings                  用於提交簽章驗證的 GnuPG 公鑰 ID
      --source-namespaces strings               應用程式的來源命名空間清單
  -s, --src stringArray                         允許的來源儲存庫 URL
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

* [argocd proj](argocd_proj.md)	 - 管理專案
