# `argocd app unset` 命令參考

## argocd app unset

取消設定應用程式參數

```
argocd app unset APPNAME parameters [flags]
```

### 範例

```
  # 取消設定 kustomize 覆寫 kustomize image
  argocd app unset my-app --kustomize-image=alpine

  # 取消設定 kustomize 覆寫後綴
  argocd app unset my-app --namesuffix

  # 取消設定應用程式 my-app 的 spec.sources 下位置 1 的來源的 kustomize 覆寫後綴。source-position 從 1 開始。
  argocd app unset my-app --source-position 1 --namesuffix

  # 取消設定應用程式 my-app 的 spec.sources 下名為 "test" 的來源的 kustomize 覆寫後綴。
  argocd app unset my-app --source-name test --namesuffix

  # 取消設定參數覆寫
  argocd app unset my-app -p COMPONENT=PARAM
```

### 選項

```
  -N, --app-namespace 字串            在命名空間中取消設定應用程式參數
  -h, --help                            unset 的說明
      --ignore-missing-components       取消設定 kustomize ignore-missing-components 選項 (還原為 false)
      --ignore-missing-value-files      取消設定 helm ignore-missing-value-files 選項 (還原為 false)
      --kustomize-image 字串陣列     Kustomize 映像檔名稱 (例如 --kustomize-image node --kustomize-image mysql)
      --kustomize-namespace             Kustomize 命名空間
      --kustomize-replica 字串陣列      Kustomize 複本名稱 (例如 --kustomize-replica my-deployment --kustomize-replica my-statefulset)
      --kustomize-version               Kustomize 版本
      --nameprefix                      Kustomize 名稱前綴
      --namesuffix                      Kustomize 名稱後綴
  -p, --parameter 字串陣列           取消設定參數覆寫 (例如 -p guestbook=image)
      --pass-credentials                取消設定 passCredentials
      --plugin-env 字串陣列          取消設定外掛程式環境變數 (例如 --plugin-env name)
      --ref                             取消設定來源上的 ref
      --source-position int             應用程式來源清單中的來源位置。計數從 1 開始。(預設為 -1)
      --values 字串陣列              取消設定一或多個 Helm values 檔案
      --values-literal                  取消設定文字 Helm values 區塊
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

