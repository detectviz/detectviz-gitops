# `argocd-dex gendexcfg` 指令參考

## argocd-dex gendexcfg

從 Argo CD 設定產生 dex 設定

```
argocd-dex gendexcfg [flags]
```

### 選項

```
      --as string                      用於模擬操作的使用者名稱
      --as-group stringArray           用於模擬操作的群組，此旗標可重複使用以指定多個群組。
      --as-uid string                  用於模擬操作的 UID
      --certificate-authority string   憑證授權單位的憑證檔案路徑
      --client-certificate string      TLS 的用戶端憑證檔案路徑
      --client-key string              TLS 的用戶端金鑰檔案路徑
      --cluster string                 要使用的 kubeconfig 叢集名稱
      --context string                 要使用的 kubeconfig 上下文名稱
      --disable-compression            如果為 true，則選擇不對所有對伺服器的請求進行回應壓縮
      --disable-tls                    停用 HTTP 端點上的 TLS
  -h, --help                           gendexcfg 的說明
      --insecure-skip-tls-verify       如果為 true，則不會檢查伺服器憑證的有效性。這會使您的 HTTPS 連線不安全
      --kubeconfig string              kube config 的路徑。僅在叢集外才需要
      --logformat string               設定記錄格式。可選：json|text（預設 "json"）
      --loglevel string                設定記錄層級。可選：debug|info|warn|error（預設 "info"）
  -n, --namespace string               如果存在，則為此 CLI 請求的命名空間範圍
  -o, --out string                     輸出到指定檔案而非標準輸出
      --password string                對 API 伺服器進行基本驗證的密碼
      --proxy-url string               如果提供，此 URL 將用於透過代理連線
      --request-timeout string         放棄單一伺服器請求前等待的時間長度。非零值應包含對應的時間單位（例如 1s、2m、3h）。值為零表示請求不會逾時。（預設 "0"）
      --server string                  Kubernetes API 伺服器的位址和埠
      --tls-server-name string         如果提供，此名稱將用於驗證伺服器憑證。如果未提供，則使用聯繫伺服器的主機名稱。
      --token string                   用於對 API 伺服器進行驗證的持有者權杖
      --user string                    要使用的 kubeconfig 使用者名稱
      --username string                對 API 伺服器進行基本驗證的使用者名稱
```

### 另請參閱

* [argocd-dex](argocd-dex.md)	 - Argo CD 使用的 argocd-dex 工具
