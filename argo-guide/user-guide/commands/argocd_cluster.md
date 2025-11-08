# `argocd cluster` 命令參考

## argocd cluster

管理叢集憑證

```
argocd cluster [flags]
```

### 範例

```
  # 以 JSON 格式列出所有已知的叢集：
  argocd cluster list -o json

  # 將目標叢集組態新增至 ArgoCD。上下文必須存在於您的 kubectl 組態中：
  argocd cluster add example-cluster

  # 以純文字 (寬) 格式取得有關叢集的特定詳細資訊：
  argocd cluster get example-cluster -o wide

  # 從 ArgoCD 中移除目標叢集上下文
  argocd cluster rm example-cluster

  # 從 ArgoCD 設定目標叢集上下文
  argocd cluster set CLUSTER_NAME --name new-cluster-name --namespace '*'
  argocd cluster set CLUSTER_NAME --name new-cluster-name --namespace namespace-one --namespace namespace-two
```

### 選項

```
      --as 字串                      模擬操作的使用者名稱
      --as-group 字串陣列           模擬操作的群組，此旗標可以重複以指定多個群組。
      --as-uid 字串                  模擬操作的 UID
      --certificate-authority 字串   憑證授權單位的憑證檔案路徑
      --client-certificate 字串      TLS 的用戶端憑證檔案路徑
      --client-key 字串              TLS 的用戶端金鑰檔案路徑
      --cluster 字串                 要使用的 kubeconfig 叢集名稱
      --context 字串                 要使用的 kubeconfig 上下文名稱
      --disable-compression            如果為 true, 則對所有對伺服器的請求停用回應壓縮
  -h, --help                           cluster 的說明
      --insecure-skip-tls-verify       如果為 true, 則不會檢查伺服器憑證的有效性。這將使您的 HTTPS 連線不安全
      --kubeconfig 字串              kube config 的路徑。僅在叢集外才需要
  -n, --namespace 字串               如果存在, 此 CLI 請求的命名空間範圍
      --password 字串                API 伺服器基本驗證的密碼
      --proxy-url 字串               如果提供, 此 URL 將用於透過代理連線
      --request-timeout 字串         在放棄單一伺服器請求之前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。(預設為 "0")
      --tls-server-name 字串         如果提供, 此名稱將用於驗證伺服器憑證。如果未提供, 則使用用於聯絡伺服器的主機名稱。
      --token 字串                   用於向 API 伺服器進行驗證的持有者權杖
      --user 字串                    要使用的 kubeconfig 使用者名稱
      --username 字串                API 伺服器基本驗證的使用者名稱
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

* [argocd](argocd.md)	 - argocd 控制 Argo CD 伺服器
* [argocd cluster add](argocd_cluster_add.md)	 - argocd cluster add CONTEXT
* [argocd cluster get](argocd_cluster_get.md)	 - 取得叢集資訊
* [argocd cluster list](argocd_cluster_list.md)	 - 列出已設定的叢集
* [argocd cluster rm](argocd_cluster_rm.md)	 - 移除叢集憑證
* [argocd cluster rotate-auth](argocd_cluster_rotate-auth.md)	 - argocd cluster rotate-auth SERVER/NAME
* [argocd cluster set](argocd_cluster_set.md)	 - 設定叢集資訊

