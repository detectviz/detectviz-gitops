# `argocd admin repo generate-spec` 命令參考

## argocd admin repo generate-spec

為儲存庫產生宣告式設定

```
argocd admin repo generate-spec REPOURL [flags]
```

### 範例

```
  
  # 透過 SSH 使用私鑰進行驗證來新增 Git 儲存庫，忽略伺服器的主機金鑰：
  argocd admin repo generate-spec git@git.example.com:repos/repo --insecure-ignore-host-key --ssh-private-key-path ~/id_rsa

  # 透過非預設連接埠的 SSH 新增 Git 儲存庫 - 這裡需要使用 ssh:// 樣式的 URL
  argocd admin repo generate-spec ssh://git@git.example.com:2222/repos/repo --ssh-private-key-path ~/id_rsa

  # 透過 HTTPS 使用使用者名稱/密碼和 TLS 用戶端憑證新增私有 Git 儲存庫：
  argocd admin repo generate-spec https://git.example.com/repos/repo --username git --password secret --tls-client-cert-path ~/mycert.crt --tls-client-cert-key-path ~/mycert.key

  # 透過 HTTPS 使用持有者權杖新增私有 Git BitBucket 資料中心儲存庫：
  argocd admin repo generate-spec https://bitbucket.example.com/scm/proj/repo --bearer-token secret-token

  # 透過 HTTPS 使用使用者名稱/密碼新增私有 Git 儲存庫，且不驗證伺服器的 TLS 憑證
  argocd admin repo generate-spec https://git.example.com/repos/repo --username git --password secret --insecure-skip-server-verification

  # 透過 HTTPS 新增名為 'stable' 的公開 Helm 儲存庫
  argocd admin repo generate-spec https://charts.helm.sh/stable --type helm --name stable  

  # 透過 HTTPS 新增名為 'stable' 的私有 Helm 儲存庫
  argocd admin repo generate-spec https://charts.helm.sh/stable --type helm --name stable --username test --password test

  # 透過 HTTPS 新增名為 'stable' 的私有 Helm OCI 型儲存庫
  argocd admin repo generate-spec helm-oci-registry.cn-zhangjiakou.cr.aliyuncs.com --type helm --name stable --enable-oci --username test --password test

  # 新增名為 'stable' 的私有 HTTPS OCI 儲存庫
  argocd admin repo generate-spec oci://helm-oci-registry.cn-zhangjiakou.cr.aliyuncs.com --type oci --name stable --username test --password test
  
  # 新增名為 'stable' 的私有 OCI 儲存庫，且不驗證伺服器的 TLS 憑證
  argocd admin repo generate-spec oci://helm-oci-registry.cn-zhangjiakou.cr.aliyuncs.com --type oci --name stable --username test --password test --insecure-skip-server-verification
  
  # 新增名為 'stable' 的私有 HTTP OCI 儲存庫
  argocd admin repo generate-spec oci://helm-oci-registry.cn-zhangjiakou.cr.aliyuncs.com --type oci --name stable --username test --password test --insecure-oci-force-http

```

### 選項

```
      --bearer-token 字串                     Git BitBucket 資料中心儲存庫的持有者權杖
      --enable-lfs                              在此儲存庫上啟用 git-lfs (大檔案支援)
      --enable-oci                              啟用 helm-oci (Helm OCI 型儲存庫) (僅適用於 helm 類型的儲存庫)
      --force-http-basic-auth                   透過 HTTP 連線儲存庫時是否強制使用基本驗證
      --gcp-service-account-key-path 字串     Google Cloud Platform 的服務帳戶金鑰
      --github-app-enterprise-base-url 字串   使用 GitHub Enterprise 時使用的基本 URL (例如 https://ghe.example.com/api/v3
      --github-app-id 整數                       GitHub 應用程式的 ID
      --github-app-installation-id 整數          GitHub 應用程式的安裝 ID
      --github-app-private-key-path 字串      GitHub 應用程式的私鑰
  -h, --help                                    generate-spec 的說明
      --insecure-ignore-host-key                停用 SSH 嚴格主機金鑰檢查 (已棄用，請改用 --insecure-skip-server-verification)
      --insecure-oci-force-http                 存取 OCI 儲存庫時使用 http
      --insecure-skip-server-verification       停用伺服器憑證和主機金鑰檢查
      --name 字串                               儲存庫名稱，對於 helm 類型的儲存庫為必填
      --no-proxy 字串                           不要透過代理存取這些目標
  -o, --output 字串                           輸出格式。可選：json|yaml (預設為 "yaml")
      --password 字串                         儲存庫的密碼
      --project 字串                          儲存庫的專案
      --proxy 字串                            使用代理存取儲存庫
      --ssh-private-key-path 字串             私有 ssh 金鑰的路徑 (例如 ~/.ssh/id_rsa)
      --tls-client-cert-key-path 字串         TLS 用戶端憑證金鑰的路徑 (必須為 PEM 格式)
      --tls-client-cert-path 字串             TLS 用戶端憑證的路徑 (必須為 PEM 格式)
      --type 字串                             儲存庫類型，"git"、"oci" 或 "helm" (預設為 "git")
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

* [argocd admin repo](argocd_admin_repo.md)	 - 管理儲存庫設定

