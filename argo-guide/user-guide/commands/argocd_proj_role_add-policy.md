# `argocd proj role add-policy` 命令參考

## argocd proj role add-policy

將策略新增至專案角色

```
argocd proj role add-policy PROJECT ROLE-NAME [flags]
```

### 範例

```
# 新增策略前
$ argocd proj role get test-project test-role
角色名稱:     test-role
描述:
策略:
p, proj:test-project:test-role, projects, get, test-project, allow
JWT 權杖:
ID          核發於                                到期於
1696759698  2023-10-08T11:08:18+01:00 (3 小時前)  <無>

# 新增一個允許更新專案的策略
$ argocd proj role add-policy test-project test-role -a update -p allow -o project

# 策略應已更新
$  argocd proj role get test-project test-role
角色名稱:     test-role
描述:
策略:
p, proj:test-project:test-role, projects, get, test-project, allow
p, proj:test-project:test-role, applications, update, test-project/project, allow
JWT 權杖:
ID          核發於                                到期於
1696759698  2023-10-08T11:08:18+01:00 (3 小時前)  <無>

# 新增一個允許取得專案日誌的策略
$ argocd proj role add-policy test-project test-role -a get -p allow -o project -r logs

# 策略應已更新
$  argocd proj role get test-project test-role
角色名稱:     test-role
描述:
策略:
p, proj:test-project:test-role, projects, get, test-project, allow
p, proj:test-project:test-role, applications, update, test-project/project, allow
p, proj:test-project:test-role, logs, get, test-project/project, allow
JWT 權杖:
ID          核發於                                到期於
1696759698  2023-10-08T11:08:18+01:00 (3 小時前)  <無>

```

### 選項

```
  -a, --action 字串       授予/拒絕權限的動作 (例如 get, create, list, update, delete)
  -h, --help                add-policy 的說明
  -o, --object 字串       專案中要授予/拒絕存取的物件。使用 '*' 作為萬用字元。將會需要存取 '<專案>/<物件>'
  -p, --permission 字串   是否允許或拒絕使用該動作存取物件。此選項只能是 'allow' 或 'deny' (預設為 "allow")
  -r, --resource 字串     資源，例如 'applications', 'applicationsets', 'logs', 'exec' 等。(預設為 "applications")
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
      --redis-haprox-name 字串       Redis HA Proxy 的名稱；當 HA Proxy 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_HAPROXY_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis-ha-haproxy")
      --redis-name 字串               Redis 部署的名稱；當 Redis 的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REDIS_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-redis")
      --repo-server-name 字串         Argo CD Repo 伺服器的名稱；當伺服器的名稱標籤與預設值不同時, 設定此選項或 ARGOCD_REPO_SERVER_NAME 環境變數, 例如透過 Helm 圖表安裝時 (預設為 "argocd-repo-server")
      --server 字串                   Argo CD 伺服器位址
      --server-crt 字串               伺服器憑證檔案
      --server-name 字串              Argo CD API 伺服器的名稱；當伺服器的名稱標籤與預設值不同時，設定此選項或 ARGOCD_SERVER_NAME 環境變數，例如透過 Helm 圖表安裝時 (預設為 "argocd-server")
```

### 另請參閱

* [argocd proj role](argocd_proj_role.md)	 - 管理專案的角色
