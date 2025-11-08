# `argocd repocreds add` 命令參考

## argocd repocreds add

新增 git 儲存庫連線參數

```
argocd repocreds add REPOURL [flags]
```

### 範例

```
  # 為 https://git.example.com/repos 下的所有儲存庫新增使用者/密碼驗證的憑證
  argocd repocreds add https://git.example.com/repos/ --username git --password secret

  # 為 https://bitbucket.example.com/scm 下的所有 BitBucket 資料中心儲存庫新增持有者權杖驗證的憑證
  argocreds add https://bitbucket.example.com/scm/ --bearer-token secret-token

  # 為 ssh://git@git.example.com/repos 下的所有儲存庫新增 SSH 私鑰驗證的憑證
  argocd repocreds add ssh://git@git.example.com/repos/ --ssh-private-key-path ~/.ssh/id_rsa

  # 為 https://github.com/repos 下的所有儲存庫新增 GitHub App 驗證的憑證
  argocd repocreds add https://github.com/repos/ --github-app-id 1 --github-app-installation-id 2 --github-app-private-key-path test.private-key.pem

  # 為 https://ghe.example.com/repos 下的所有儲存庫新增 GitHub App 驗證的憑證
  argocd repocreds add https://ghe.example.com/repos/ --github-app-id 1 --github-app-installation-id 2 --github-app-private-key-path test.private-key.pem --github-app-enterprise-base-url https://ghe.example.com/api/v3

  # 為 helm oci 登錄檔新增憑證，這樣這些 oci 登錄檔 url 就不需要單獨作為儲存庫新增。
  argocd repocreds add localhost:5000/myrepo --enable-oci --type helm 

  # 為 https://source.developers.google.com/p/my-google-cloud-project/r/ 下的所有儲存庫新增 GCP 憑證
  argocd repocreds add https://source.developers.google.com/p/my-google-cloud-project/r/ --gcp-service-account-key-path service-account-key.json

```

### 選項

```
      --bearer-token 字串                     Git 儲存庫的持有者權杖
      --enable-oci                              指定是否應為此儲存庫啟用 helm-oci 支援
      --force-http-basic-auth                   透過 HTTP 連接時是否強制使用基本驗證
      --gcp-service-account-key-path 字串     Google Cloud Platform 的服務帳號金鑰
      --github-app-enterprise-base-url 字串   使用 GitHub Enterprise 時的基礎 URL (例如 https://ghe.example.com/api/v3
      --github-app-id 整數                       GitHub 應用程式的 ID
      --github-app-installation-id 整數          GitHub 應用程式的安裝 ID
      --github-app-private-key-path 字串      GitHub 應用程式的私鑰
  -h, --help                                    add 的說明
      --password 字串                         儲存庫的密碼
      --proxy-url 字串                        若提供，將使用此 URL 透過代理連線
      --ssh-private-key-path 字串             私有 ssh 金鑰的路徑 (例如 ~/.ssh/id_rsa)
      --tls-client-cert-key-path 字串         TLS 用戶端憑證金鑰的路徑 (必須為 PEM 格式)
      --tls-client-cert-path 字串             TLS 用戶端憑證的路徑 (必須為 PEM 格式)
      --type 字串                             儲存庫的類型，"git" 或 "helm" (預設為 "git")
      --upsert                                  即使規格不同，也要覆寫同名的現有儲存庫
      --use-azure-workload-identity             是否使用 Azure 工作負載身分識別進行驗證
      --username 字串                         儲存庫的使用者名稱
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

* [argocd repocreds](argocd_repocreds.md)	 - 管理儲存庫的憑證範本
