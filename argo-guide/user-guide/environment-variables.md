# 環境變數

以下環境變數可與 `argocd` CLI 一起使用：

| 環境變數                 | 說明                                                                                                                                                                                               |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ARGOCD_SERVER`                      | Argo CD 伺服器的位址，不含 `https://` 前綴 <br> (取代為每個指令指定 `--server`) <br> 例如 `ARGOCD_SERVER=argocd.example.com` (如果透過具有 DNS 的 ingress 提供服務)   |
| `ARGOCD_AUTH_TOKEN`                  | 您的 Argo CD 使用者的 Argo CD `apiKey`，以便能夠進行驗證                                                                                                                                     |
| `ARGOCD_OPTS`                        | 傳遞給 `argocd` CLI 的命令列選項 <br> 例如 `ARGOCD_OPTS="--grpc-web"`                                                                                                                          |
| `ARGOCD_CONFIG_DIR`                  | 設定託管 `argocd` CLI 組態的目錄，例如 `~/.config/argocd/config`。(如果未提供 ENV 變數，則預設為 `$XDG_CONFIG_HOME/argocd`、`~/.config/argocd`，或如果存在舊版 `~/.argocd`) |
| `ARGOCD_SERVER_NAME`                 | Argo CD API 伺服器名稱 (預設為 "argocd-server")                                                                                                                                                     |
| `ARGOCD_REPO_SERVER_NAME`            | Argo CD 儲存庫伺服器名稱 (預設為 "argocd-repo-server")                                                                                                                                         |
| `ARGOCD_APPLICATION_CONTROLLER_NAME` | Argo CD 應用程式控制器名稱 (預設為 "argocd-application-controller")                                                                                                                         |
| `ARGOCD_REDIS_NAME`                  | Argo CD Redis 名稱 (預設為 "argocd-redis")                                                                                                                                                           |
| `ARGOCD_REDIS_HAPROXY_NAME`          | Argo CD Redis HA Proxy 名稱 (預設為 "argocd-redis-ha-haproxy")                                                                                                                                       |
| `ARGOCD_GRPC_KEEP_ALIVE_MIN`         | 定義 GRPCKeepAliveEnforcementMinimum，用於 grpc.KeepaliveEnforcementPolicy。預期為「持續時間」格式 (預設為 `10s`)。                                                                    |
