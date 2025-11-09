# `argocd admin notifications template` 命令參考

## argocd admin notifications template

通知範本相關指令

```
argocd admin notifications template [flags]
```

### 選項

```
  -h, --help   template 的說明
```

### 從父指令繼承的選項

```
      --argocd-context 字串           要使用的 Argo-CD 伺服器上下文名稱
      --argocd-repo-server 字串       Argo CD repo 伺服器位址 (預設為 "argocd-repo-server:8081")
      --argocd-repo-server-plaintext    使用純文字用戶端 (非 TLS) 連線至儲存庫伺服器
      --argocd-repo-server-strict-tls   連線至 repo 伺服器時執行嚴格的 TLS 憑證驗證
      --as 字串                       模擬操作的使用者名稱
      --as-group 字串陣列            模擬操作的群組，此旗標可以重複以指定多個群組。
      --as-uid 字串                   模擬操作的 UID
      --auth-token 字串               驗證權杖；設定此選項或 ARGOCD_AUTH_TOKEN 環境變數
      --certificate-authority 字串    憑證授權單位的憑證檔案路徑
      --client-certificate 字串       TLS 的用戶端憑證檔案路徑
      --client-crt 字串               用戶端憑證檔案
      --client-crt-key 字串           用戶端憑證金鑰檔案
      --client-key 字串               TLS 的用戶端金鑰檔案路徑
      --cluster 字串                  要使用的 kubeconfig 叢集名稱
      --config 字串                   Argo CD 設定檔的路徑 (預設為 "/home/user/.config/argocd/config")
      --config-map 字串               argocd-notifications-cm.yaml 檔案路徑
      --context 字串                  要使用的 kubeconfig 上下文名稱
      --controller-name 字串          Argo CD 應用程式控制器的名稱；當控制器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_APPLICATION_CONTROLLER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-application-controller")
      --core                            如果設定為 true, 則 CLI 會直接與 Kubernetes 通訊, 而非與 Argo CD API 伺服器通訊
      --disable-compression             如果為 true, 則對所有對伺服器的請求停用回應壓縮
      --grpc-web                        啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後, 此選項很有用。
      --grpc-web-root-path 字串       啟用 gRPC-web 協定。如果 Argo CD 伺服器位於不支援 HTTP2 的代理之後, 此選項很有用。設定 Web 根目錄。
  -H, --header 字串陣列                  為 Argo CD CLI 發出的所有請求設定額外的標頭。(可以重複多次以新增多個標頭, 也支援以逗號分隔的標頭)
      --http-retry-max 整數              與 Argo CD 伺服器建立 http 連線的最大重試次數
      --insecure                        略過伺服器憑證和網域驗證
      --insecure-skip-tls-verify        如果為 true, 則不會檢查伺服器憑證的有效性。這將使您的 HTTPS 連線不安全
      --kube-context 字串             將指令導向至給定的 kube-context
      --kubeconfig 字串               kube config 的路徑。僅在叢集外才需要
      --logformat 字串                  設定記錄格式。可選：json|text (預設為 "json")
      --loglevel 字串                 設定記錄層級。可選：debug|info|warn|error (預設為 "info")
  -n, --namespace 字串                如果存在, 此 CLI 請求的命名空間範圍
      --password 字串                 API 伺服器基本驗證的密碼
      --plaintext                       停用 TLS
      --port-forward                    使用連接埠轉送連線至隨機的 argocd-server 連接埠
      --port-forward-namespace 字串   應用於連接埠轉送的命名空間名稱
      --prompts-enabled                 強制啟用或停用可選的互動式提示, 覆寫本機組態。如果未指定, 將使用本機組態值, 預設為 false。
      --proxy-url 字串                如果提供, 此 URL 將用於透過代理連線
      --redis-compress 字串           如果應用程式控制器已啟用 redis 壓縮, 請啟用此選項。(可能的值：gzip, none) (預設為 "gzip")
      --redis-haproxy-name 字串       Redis HA Proxy 的名稱；當 HA Proxy 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_HAPROXY_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis-ha-haproxy")
      --redis-name 字串               Redis 部署的名稱；當 Redis 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis")
      --repo-server-name 字串         Argo CD Repo 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REPO_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-repo-server")
      --request-timeout 字串          在放棄單一伺服器請求之前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。(預設為 "0")
      --secret 字串                   argocd-notifications-secret.yaml 檔案路徑。如果提供的值為 ':empty', 則使用空密鑰
      --server 字串                   Kubernetes API 伺服器的位址和連接埠
      --server-crt 字串               伺服器憑證檔案
      --server-name 字串              Argo CD API 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-server")
      --tls-server-name 字串          如果提供, 此名稱將用於驗證伺服器憑證。如果未提供, 則使用用於聯絡伺服器的主機名稱。
      --token 字串                    用於向 API 伺服器進行驗證的持有者權杖
      --user 字串                     要使用的 kubeconfig 使用者名稱
      --username 字串                 API 伺服器基本驗證的使用者名稱
```

### 另請參閱

* [argocd admin notifications](argocd_admin_notifications.md)	 - 一組有助於管理通知設定的 CLI 指令
* [argocd admin notifications template get](argocd_admin_notifications_template_get.md)	 - 列印有關已設定範本的資訊
* [argocd admin notifications template notify](argocd_admin_notifications_template_notify.md)	 - 使用指定的範本產生通知並將其傳送給指定的收件人

