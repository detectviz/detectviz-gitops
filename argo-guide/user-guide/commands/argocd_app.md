# `argocd app` 命令參考

## argocd app

管理應用程式

```
argocd app [flags]
```

### 範例

```
  # 列出所有應用程式。
  argocd app list

  # 取得應用程式的詳細資訊
  argocd app get my-app

  # 設定覆寫參數
  argocd app set my-app -p image.tag=v1.0.1
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
  -h, --help                           app 的說明
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
* [argocd app actions](argocd_app_actions.md)	 - 管理資源操作
* [argocd app add-source](argocd_app_add-source.md)	 - 將來源新增至應用程式的來源清單中
* [argocd app confirm-deletion](argocd_app_confirm-deletion.md)	 - 確認刪除/裁剪應用程式資源
* [argocd app create](argocd_app_create.md)	 - 建立應用程式
* [argocd app delete](argocd_app_delete.md)	 - 刪除應用程式
* [argocd app delete-resource](argocd_app_delete-resource.md)	 - 刪除應用程式中的資源
* [argocd app diff](argocd_app_diff.md)	 - 對目標和即時狀態執行差異比較。
* [argocd app edit](argocd_app_edit.md)	 - 編輯應用程式
* [argocd app get](argocd_app_get.md)	 - 取得應用程式詳細資訊
* [argocd app get-resource](argocd_app_get-resource.md)	 - 取得應用程式中資源的即時 Kubernetes 清單的詳細資訊。filter-fields 旗標可用於僅顯示您想查看的欄位。
* [argocd app history](argocd_app_history.md)	 - 顯示應用程式部署歷史記錄
* [argocd app list](argocd_app_list.md)	 - 列出應用程式
* [argocd app logs](argocd_app_logs.md)	 - 取得應用程式 pod 的日誌
* [argocd app manifests](argocd_app_manifests.md)	 - 列印應用程式的清單
* [argocd app patch](argocd_app_patch.md)	 - 修補應用程式
* [argocd app patch-resource](argocd_app_patch-resource.md)	 - 修補應用程式中的資源
* [argocd app remove-source](argocd_app_remove-source.md)	 - 從多個來源應用程式中移除來源。
* [argocd app resources](argocd_app_resources.md)	 - 列出應用程式的資源
* [argocd app rollback](argocd_app_rollback.md)	 - 依歷史記錄 ID 將應用程式復原至先前部署的版本，省略將復原至上一個版本
* [argocd app set](argocd_app_set.md)	 - 設定應用程式參數
* [argocd app sync](argocd_app_sync.md)	 - 將應用程式同步至其目標狀態
* [argocd app terminate-op](argocd_app_terminate-op.md)	 - 終止正在執行的應用程式操作
* [argocd app unset](argocd_app_unset.md)	 - 取消設定應用程式參數
* [argocd app wait](argocd_app_wait.md)	 - 等待應用程式達到同步且健康的狀態

