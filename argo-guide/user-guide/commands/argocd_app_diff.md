# `argocd app diff` 命令參考

## argocd app diff

對目標和即時狀態執行差異比較。

### 摘要

對目標和即時狀態執行差異比較。
使用 'diff' 來呈現差異。KUBECTL_EXTERNAL_DIFF 環境變數可用於選擇您自己的差異比較工具。
傳回下列結束代碼：一般錯誤為 2，找到差異為 1，未找到差異為 0
此差異比較會忽略 Kubernetes Secrets。

```
argocd app diff APPNAME [flags]
```

### 選項

```
  -N, --app-namespace 字串                              僅呈現命名空間中的差異
      --diff-exit-code 整數                                當有差異時傳回指定的結束代碼。典型的錯誤代碼是 20，但如果您想與所有 CLI 指令傳回的通用結束代碼 (20) 區分開來，請使用另一個結束代碼。(預設為 1)
      --exit-code                                         當有差異時傳回非零結束代碼。如果發生錯誤，也可能傳回非零結束代碼。(預設為 true)
      --hard-refresh                                      重新整理應用程式資料以及目標清單快取
  -h, --help                                              diff 的說明
      --ignore-normalizer-jq-execution-timeout duration   設定忽略正規化器 JQ 執行逾時 (預設為 1 秒)
      --local 字串                                      將即時應用程式與本機清單進行比較
      --local-include 字串陣列                         與 --server-side-generate 一起使用，指定要傳送的檔案名稱模式。比對是根據檔案名稱而非路徑。(預設為 [*.yaml,*.yml,*.json])
      --local-repo-root 字串                            儲存庫根目錄的路徑。與 --local 一起使用可設定儲存庫根目錄 (預設為 "/")
      --refresh                                           擷取時重新整理應用程式資料
      --revision 字串                                   將即時應用程式與特定修訂版本進行比較
      --revisions 字串陣列                             在 source-positions 的來源位置顯示特定修訂版本的清單
      --server-side-diff                                  使用伺服器端差異比較來計算差異。如果應用程式上設定了 ServerSideDiff 標註，則預設為 true。
      --server-side-generate                              與 --local 一起使用，這會將您的清單傳送至伺服器進行差異比較
      --source-names 字串陣列                          來源名稱清單。預設為空陣列。
      --source-positions int64Slice                       來源位置清單。預設為空陣列。從 1 開始計數。(預設為 [])
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

