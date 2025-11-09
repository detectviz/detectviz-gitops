# `argocd app create` 命令參考

## argocd app create

建立應用程式

```
argocd app create APPNAME [flags]
```

### 範例

```
  # 建立目錄應用程式
  argocd app create guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --directory-recurse

  # 建立 Jsonnet 應用程式
  argocd app create jsonnet-guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path jsonnet-guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --jsonnet-ext-str replicas=2

  # 建立 Helm 應用程式
  argocd app create helm-guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path helm-guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --helm-set replicaCount=2

  # 從 Helm 儲存庫建立 Helm 應用程式
  argocd app create nginx-ingress --repo https://charts.helm.sh/stable --helm-chart nginx-ingress --revision 1.24.3 --dest-namespace default --dest-server https://kubernetes.default.svc

  # 建立 Kustomize 應用程式
  argocd app create kustomize-guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path kustomize-guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --kustomize-image quay.io/argoprojlabs/argocd-e2e-container:0.1

  # 當 yaml 檔案包含具有多個來源的應用程式時，建立多來源應用程式
  argocd app create guestbook --file <path-to-yaml-file>

  # 使用自訂工具建立應用程式：
  argocd app create kasane --repo https://github.com/argoproj/argocd-example-apps.git --path plugins/kasane --dest-namespace default --dest-server https://kubernetes.default.svc --config-management-plugin kasane
```

### 選項

```
      --allow-empty                                為自動同步策略設定允許零個即時資源
      --annotations 字串陣列                    設定元資料標註 (例如 example=value)
  -N, --app-namespace 字串                       將在其中建立應用程式的命名空間
      --auto-prune                                 為自動同步策略設定自動裁剪
      --config-management-plugin 字串            設定管理外掛程式名稱
      --dest-name 字串                           K8s 叢集名稱 (例如 minikube)
      --dest-namespace 字串                      K8s 目標命名空間
      --dest-server 字串                         K8s 叢集 URL (例如 https://kubernetes.default.svc)
      --directory-exclude 字串                   設定用於從應用程式來源路徑中排除檔案的 glob 運算式
      --directory-include 字串                   設定用於從應用程式來源路徑中包含檔案的 glob 運算式
      --directory-recurse                          遞迴目錄
      --dry-source-path 字串                     用於 dry source 的應用程式目錄在儲存庫中的路徑
      --dry-source-repo 字串                     應用程式 dry source 的儲存庫 URL
      --dry-source-revision 字串                 應用程式 dry source 的修訂版本
      --env 字串                                 要監控的應用程式環境
  -f, --file 字串                                應用程式的 Kubernetes 清單檔案名稱或 URL
      --helm-api-versions 字串陣列              執行 helm template 時使用的 Helm api-versions (格式為 [group/]version/kind) (可重複設定多個值：--helm-api-versions traefik.io/v1alpha1/TLSOption --helm-api-versions v1/Service)。如果未設定，則使用目標叢集的 api-versions
      --helm-chart 字串                          Helm 圖表名稱
      --helm-kube-version 字串                   執行 helm template 時使用的 Helm kube-version。如果未設定，則使用目標叢集的 kube version
      --helm-namespace 字串                      執行 helm template 時使用的 Helm 命名空間。如果未設定，則使用 app.spec.destination.namespace
      --helm-pass-credentials                      將憑證傳遞至所有網域
      --helm-set 字串陣列                       在命令列上設定 Helm 值 (可重複設定多個值：--helm-set key1=val1 --helm-set key2=val2)
      --helm-set-file 字串陣列                  從命令列指定的各個檔案設定 Helm 值 (可重複設定多個值：--helm-set-file key1=path1 --helm-set-file key2=path2)
      --helm-set-string 字串陣列                在命令列上設定 Helm STRING 值 (可重複設定多個值：--helm-set-string key1=val1 --helm-set-string key2=val2)
      --helm-skip-crds                             略過 helm crd 安裝步驟
      --helm-skip-schema-validation                略過 helm schema 驗證步驟
      --helm-skip-tests                            略過 helm 測試清單安裝步驟
      --helm-version 字串                        Helm 版本
  -h, --help                                       create 的說明
      --hydrate-to-branch 字串                   要將應用程式 hydrate 到的分支
      --ignore-missing-components                  設定 Kustomize 元件時忽略本機缺少的元件目錄
      --ignore-missing-value-files                 設定 helm template --values 時忽略本機缺少的 valueFiles
      --jsonnet-ext-var-code 字串陣列           Jsonnet ext var
      --jsonnet-ext-var-str 字串陣列            Jsonnet 字串 ext var
      --jsonnet-libs 字串陣列                   額外的 jsonnet 函式庫 (以 repoRoot 為前綴)
      --jsonnet-tla-code 字串陣列               Jsonnet 頂層程式碼引數
      --jsonnet-tla-str 字串陣列                Jsonnet 頂層字串引數
      --kustomize-api-versions 字串陣列         執行 helm template 時使用的 api-versions (格式為 [group/]version/kind) (可重複設定多個值：--helm-api-versions traefik.io/v1alpha1/TLSOption --helm-api-versions v1/Service)。如果未設定，則使用目標叢集的 api-versions。僅適用於為 Kustomize 組建啟用 Helm 時
      --kustomize-common-annotation 字串陣列    在 Kustomize 中設定通用標註
      --kustomize-common-label 字串陣列         在 Kustomize 中設定通用標籤
      --kustomize-force-common-annotation          在 Kustomize 中強制使用通用標註
      --kustomize-force-common-label               在 Kustomize 中強制使用通用標籤
      --kustomize-image 字串陣列                Kustomize 映像檔 (例如 --kustomize-image node:8.15.0 --kustomize-image mysql=mariadb,alpine@sha256:24a0c4b4a4c0eb97a1aabb8e29f18e917d05abfe1b7a7c07857230879ce7d3d)
      --kustomize-kube-version 字串              執行 helm template 時使用的 kube-version。如果未設定，則使用目標叢集的 kube version。僅適用於為 Kustomize 組建啟用 Helm 時
      --kustomize-label-include-templates          將通用標籤應用於資源範本
      --kustomize-label-without-selector           不要將通用標籤應用於選擇器。除非設定了 --kustomize-label-include-templates，否則也不要將標籤應用於範本
      --kustomize-namespace 字串                 Kustomize 命名空間
      --kustomize-replica 字串陣列              Kustomize 複本 (例如 --kustomize-replica my-development=2 --kustomize-replica my-statefulset=4)
      --kustomize-version 字串                   Kustomize 版本
  -l, --label 字串陣列                          要應用於應用程式的標籤
      --name 字串                                應用程式名稱，如果設定了檔案則忽略 (已棄用)
      --nameprefix 字串                          Kustomize 名稱前綴
      --namesuffix 字串                          Kustomize 名稱後綴
  -p, --parameter 字串陣列                      設定參數覆寫 (例如 -p guestbook=image=example/guestbook:latest)
      --path 字串                                儲存庫中應用程式目錄的路徑，如果設定了檔案則忽略
      --plugin-env 字串陣列                     額外的外掛程式環境變數
      --project 字串                             應用程式專案名稱
      --ref 字串                                 Ref 是對 sources 欄位中另一個來源的參考
      --release-name 字串                        Helm release-name
      --repo 字串                                儲存庫 URL，如果設定了檔案則忽略
      --revision 字串                            應用程式將同步到的追蹤來源分支、標籤、提交或 Helm 圖表版本
      --revision-history-limit 整數                 修訂歷史記錄中要保留的項目數 (預設為 10)
      --self-heal                                  為自動同步策略設定自我修復
      --set-finalizer                              在應用程式上設定刪除 finalizer，刪除時將級聯應用程式資源
      --source-name 字串                         應用程式來源清單中的來源名稱。
      --sync-option Prune=false                    新增或移除同步選項，例如新增 Prune=false。使用 `!` 前綴移除，例如 `!Prune=false`
      --sync-policy 字串                         設定同步策略 (可選：manual (manual 的別名：none)、automated (automated 的別名：auto, automatic))
      --sync-retry-backoff-duration duration       同步重試退避基本持續時間。輸入必須是持續時間 (例如 2m, 1h) (預設為 5s)
      --sync-retry-backoff-factor 整數              每次同步重試失敗後乘以基本持續時間的因子 (預設為 2)
      --sync-retry-backoff-max-duration duration   最大同步重試退避持續時間。輸入必須是持續時間 (例如 2m, 1h) (預設為 3m0s)
      --sync-retry-limit 整數                       允許的最大同步重試次數
      --sync-retry-refresh                         表示重試時是否應使用最新的修訂版本，而非初始版本
      --sync-source-branch 字串                  應用程式將從中同步的分支
      --sync-source-path 字串                    應用程式將從中同步的儲存庫中的路徑
      --upsert                                     即使提供的應用程式規格與現有規格不同，也允許覆寫同名應用程式
      --validate                                   驗證儲存庫和叢集 (預設為 true)
      --values 字串陣列                         要使用的 Helm values 檔案
      --values-literal-file 字串                 要作為文字 Helm values 區塊匯入的檔案名稱或 URL
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

