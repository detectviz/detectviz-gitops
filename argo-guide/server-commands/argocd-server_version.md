# `argocd-server version` 指令參考

## argocd-server version

列印版本資訊

```
argocd-server version [flags]
```

### 選項

```
  -h, --help    version 的說明
      --short   僅列印版本號
```

### 從父指令繼承的選項

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
      --insecure-skip-tls-verify       如果為 true，則不會檢查伺服器憑證的有效性。這會使您的 HTTPS 連線不安全
      --kubeconfig string              kube config 的路徑。僅在叢集外才需要
  -n, --namespace string               如果存在，則為此 CLI 請求的命名空間範圍
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

* [argocd-server](argocd-server.md)	 - 執行 ArgoCD API 伺服器
