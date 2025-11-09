# `argocd admin cluster generate-spec` 命令參考

## argocd admin cluster generate-spec

為叢集產生宣告式組態

```
argocd admin cluster generate-spec CONTEXT [旗標]
```

### 選項

```
      --annotation 字串陣列             設定元資料註解 (例如 --annotation key=value)
      --aws-cluster-name 字串            AWS 叢集名稱，如果設定，則會使用 aws cli eks token 指令來存取叢集
      --aws-profile 字串                 可選的 AWS 設定檔。如果設定，則 AWS IAM Authenticator 會使用此設定檔來執行叢集操作，而非預設的 AWS 憑證提供者鏈。
      --aws-role-arn 字串                可選的 AWS 角色 arn。如果設定，則 AWS IAM Authenticator 會擔任一個角色來執行叢集操作，而非預設的 AWS 憑證提供者鏈。
      --bearer-token 字串                應用於存取 K8S API 伺服器的驗證權杖
      --cluster-endpoint 字串            要使用的叢集端點。可以是下列其中之一：'kubeconfig'、'kube-public' 或 'internal'。
      --cluster-resources                  表示是否應管理叢集層級的資源。此設定僅在受管理命名空間清單不為空時使用。
      --disable-compression                繞過對伺服器的自動 GZip 壓縮請求
      --exec-command 字串                執行以提供用戶端憑證給叢集的指令。您可能需要建置一個自訂的 ArgoCD 映像檔，以確保該指令在執行時期可用。
      --exec-command-api-version 字串    --exec-command 可執行檔的 ExecInfo 的偏好輸入版本
      --exec-command-args 字串陣列      提供給 --exec-command 可執行檔的引數
      --exec-command-env stringToString    執行 --exec-command 可執行檔時要設定的環境變數 (預設 [])
      --exec-command-install-hint 字串   當 --exec-command 可執行檔似乎不存在時，向使用者顯示的文字
      --generate-bearer-token              產生應用於存取 K8S API 伺服器的驗證權杖
  -h, --help                               generate-spec 的說明
      --in-cluster                         表示 Argo CD 位於此叢集中，應使用內部 k8s 主機名稱 (kubernetes.default.svc) 進行連線
      --kubeconfig 字串                  使用特定的 kubeconfig 檔案
      --label 字串陣列                  設定元資料標籤 (例如 --label key=value)
      --name 字串                        覆寫叢集名稱
      --namespace 字串陣列              允許管理的命名空間清單
  -o, --output 字串                      輸出格式。可選：json|yaml (預設為 "yaml")
      --project 字串                     叢集的專案
      --service-account 字串             用於 kubernetes 資源管理的系統命名空間服務帳戶。如果未設定，則會使用預設的 "argocd-manager" SA (預設為 "argocd-manager")
      --shard int                          叢集分片編號；如果未設定，則從主機名稱推斷 (預設為 -1)
      --system-namespace 字串            使用不同的系統命名空間 (預設為 "kube-system")
```

### 從父指令繼承的選項

```
      --argocd-context 字串           要使用的 Argo-CD 伺服器上下文名稱
      --auth-token 字串               驗證權杖；設定此選項或 ARGOCD_AUTH_TOKEN 環境變數
      --client-crt 字串               用戶端憑證檔案
      --client-crt-key 字串           用戶端憑證金鑰檔案
      --config 字串                   Argo CD 設定檔的路徑 (預設為 "/home/user/.config/argocd/config")
      --controller-name 字串          Argo CD 應用程式控制器的名稱；當控制器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_APPLICATION_CONTROLLER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-application-controller")
      --core                            如果設定為 true，則 CLI 會直接與 Kubernetes 通訊，而不是與 Argo CD API 伺服器通訊
      --grpc-web                        啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後，此選項很有用。
      --grpc-web-root-path 字串       啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後，此選項很有用。設定 Web 根目錄。
  -H, --header 字串陣列                  設定 Argo CD CLI 發出的所有請求的附加標頭。(可以重複多次以新增多個標頭，也支援以逗號分隔的標頭)
      --http-retry-max 整數              與 Argo CD 伺服器建立 http 連線的最大重試次數
      --insecure                        略過伺服器憑證和網域驗證
      --kube-context 字串             將指令導向至指定的 kube-context
      --logformat 字串                  設定記錄格式。可選：json|text (預設為 "json")
      --loglevel 字串                 設定記錄層級。可選：debug|info|warn|error (預設為 "info")
      --plaintext                       停用 TLS
      --port-forward                    使用連接埠轉發連線至隨機的 argocd-server 連接埠
      --port-forward-namespace 字串   應用於連接埠轉發的命名空間名稱
      --prompts-enabled                 強制啟用或停用可選的互動式提示，覆寫本機組態。如果未指定，將使用本機組態值，預設為 false。
      --redis-compress 字串           如果應用程式控制器已啟用 redis 壓縮，請啟用此選項。(可能的值：gzip, none) (預設為 "gzip")
      --redis-haproxy-name 字串       Redis HA Proxy 的名稱；當 HA Proxy 的名稱標籤與預設值不同時，設定此選項或 ARGOCD_REDIS_HAPROXY_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-redis-ha-haproxy")
      --redis-name 字串               Redis 部署的名稱；當 Redis 的名稱標籤與預設值不同時，設定此選項或 ARGOCD_REDIS_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-redis")
      --repo-server-name 字串         Argo CD Repo 伺服器的名稱；當伺服器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_REPO_SERVER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-repo-server")
      --server 字串                   Argo CD 伺服器位址
      --server-crt 字串               伺服器憑證檔案
      --server-name 字串              Argo CD API 伺服器的名稱；當伺服器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_SERVER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-server")
```

### 另請參閱

* [argocd admin cluster](argocd_admin_cluster.md)	 - 管理叢集組態

