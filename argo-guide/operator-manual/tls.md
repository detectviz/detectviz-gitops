# TLS 組態

Argo CD 提供三個可設定的傳入 TLS 端點：

* `argocd-server` 工作負載的使用者面向端點，提供 UI 和 API
* `argocd-repo-server` 的端點，由 `argocd-server` 和 `argocd-application-controller` 工作負載存取以請求儲存庫操作。
* `argocd-dex-server` 的端點，由 `argocd-server` 存取以處理 OIDC 驗證。

預設情況下，若無進一步組態，這些端點將設定為使用自動產生的自我簽署憑證。然而，大多數使用者會希望明確設定這些 TLS 端點的憑證，可能使用 `cert-manager` 等自動化方式或使用其自己的專用憑證授權單位。

## TLS 組態快速參考

### 憑證組態總覽

| 元件 | Secret 名稱 | 熱重載 | 預設憑證 | 必要 SAN 項目 |
|---|---|---|---|---|
| `argocd-server` | `argocd-server-tls` | ✅ 是 | 自我簽署 | 外部主機名稱（例如 `argocd.example.com`） |
| `argocd-repo-server` | `argocd-repo-server-tls` | ❌ 需要重新啟動 | 自我簽署 | `DNS:argocd-repo-server`、`DNS:argocd-repo-server.argocd.svc` |
| `argocd-dex-server` | `argocd-dex-server-tls` | ❌ 需要重新啟動 | 自我簽署 | `DNS:argocd-dex-server`、`DNS:argocd-dex-server.argocd.svc` |

### 元件間 TLS

| 連線 | 嚴格 TLS 參數 | 純文字參數 | 預設行為 |
|---|---|---|---|
| `argocd-server` → `argocd-repo-server` | `--repo-server-strict-tls` | `--repo-server-plaintext` | 不驗證 TLS |
| `argocd-application-controller` → `argocd-repo-server` | `--repo-server-strict-tls` | `--repo-server-plaintext` | 不驗證 TLS |
| `argocd-server` → `argocd-dex-server` | `--dex-server-strict-tls` | `--dex-server-plaintext` | 不驗證 TLS |

### 憑證優先順序（僅限 argocd-server）

1. `argocd-server-tls` secret（建議）
2. `argocd-secret` secret（已棄用）
3. 自動產生的自我簽署憑證

## 為 argocd-server 設定 TLS

### argocd-server 的傳入 TLS 選項

您可以透過設定命令列參數來為 `argocd-server` 工作負載設定某些 TLS 選項。可用的參數如下：

|參數|預設值|說明|
|---|---|---|
|`--insecure`|`false`|完全停用 TLS|
|`--tlsminversion`|`1.2`|提供給用戶端的最低 TLS 版本|
|`--tlsmaxversion`|`1.3`|提供給用戶端的最高 TLS 版本|
|`--tlsciphers`|`TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_RSA_WITH_AES_256_GCM_SHA384`|提供給用戶端的以冒號分隔的 TLS 加密套件清單|

### argocd-server 使用的 TLS 憑證

有兩種方法可以設定 `argocd-server` 使用的 TLS 憑證：

* 在 `argocd-server-tls` secret 中設定 `tls.crt` 和 `tls.key` 金鑰，以存放憑證的 PEM 資料和對應的私密金鑰。`argocd-server-tls` secret 的類型可以是 `tls`，但不一定要是。
* 在 `argocd-secret` secret 中設定 `tls.crt` 和 `tls.key` 金鑰，以存放憑證的 PEM 資料和對應的私密金鑰。此方法被視為已棄用，僅為向後相容而存在。不應再使用變更 `argocd-secret` 來覆寫 TLS 憑證。

Argo CD 決定使用哪個 TLS 憑證來用於 `argocd-server` 的端點，如下所示：

* 如果 `argocd-server-tls` secret 存在且在 `tls.crt` 和 `tls.key` 金鑰中包含有效的金鑰對，則將使用此金鑰對作為 `argocd-server` 端點的憑證。
* 否則，如果 `argocd-secret` secret 在 `tls.crt` 和 `tls.key` 金鑰中包含有效的金鑰對，則將使用此金鑰對作為 `argocd-server` 端點的憑證。
* 如果在上述兩個 secret 中都找不到 `tls.crt` 和 `tls.key` 金鑰，Argo CD 將產生一個自我簽署的憑證並將其持久化到 `argocd-secret` secret 中。

`argocd-server-tls` secret 僅包含供 `argocd-server` 使用的 TLS 組態資訊，可以安全地由 `cert-manager` 或 `SealedSecrets` 等第三方工具管理。

若要從現有的金鑰對手動建立此 secret，您可以使用 `kubectl`：

```shell
kubectl create -n argocd secret tls argocd-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

Argo CD 會自動偵測 `argocd-server-tls` secret 的變更，並且不需要重新啟動即可使用更新的憑證。

## 為 argocd-repo-server 設定傳入 TLS

### argocd-repo-server 的傳入 TLS 選項

您可以透過設定命令列參數來為 `argocd-repo-server` 工作負載設定某些 TLS 選項。可用的參數如下：

|參數|預設值|說明|
|---|---|---|
|`--disable-tls`|`false`|完全停用 TLS|
|`--tlsminversion`|`1.2`|提供給用戶端的最低 TLS 版本|
|`--tlsmaxversion`|`1.3`|提供給用戶端的最高 TLS 版本|
|`--tlsciphers`|`TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_RSA_WITH_AES_256_GCM_SHA384`|提供給用戶端的以冒號分隔的 TLS 加密套件清單|

### argocd-repo-server 使用的傳入 TLS 憑證

若要設定 `argocd-repo-server` 工作負載使用的 TLS 憑證，請在執行 Argo CD 的命名空間中建立一個名為 `argocd-repo-server-tls` 的 secret，並將憑證的金鑰對儲存在 `tls.crt` 和 `tls.key` 金鑰中。如果此 secret 不存在，`argocd-repo-server` 將產生並使用自我簽署的憑證。

若要建立此 secret，您可以使用 `kubectl`：

```shell
kubectl create -n argocd secret tls argocd-repo-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

如果憑證是自我簽署的，您還需要在 secret 中新增 `ca.crt`，並填入您的 CA 憑證內容。

請注意，與 `argocd-server` 不同，`argocd-repo-server` 無法自動偵測此 secret 的變更。如果您建立（或更新）此 secret，則需要重新啟動 `argocd-repo-server` pod。

另請注意，憑證應使用正確的 SAN 項目為 `argocd-repo-server` 發行，至少包含 `DNS:argocd-repo-server` 和 `DNS:argocd-repo-server.argo-cd.svc` 的項目，具體取決於您的工作負載如何連線到儲存庫伺服器。

## 為 argocd-dex-server 設定傳入 TLS

### argocd-dex-server 的傳入 TLS 選項

您可以透過設定命令列參數來為 `argocd-dex-server` 工作負載設定某些 TLS 選項。可用的參數如下：

|參數|預設值|說明|
|---|---|---|
|`--disable-tls`|`false`|完全停用 TLS|

### argocd-dex-server 使用的傳入 TLS 憑證

若要設定 `argocd-dex-server` 工作負載使用的 TLS 憑證，請在執行 Argo CD 的命名空間中建立一個名為 `argocd-dex-server-tls` 的 secret，並將憑證的金鑰對儲存在 `tls.crt` 和 `tls.key` 金鑰中。如果此 secret 不存在，`argocd-dex-server` 將產生並使用自我簽署的憑證。

若要建立此 secret，您可以使用 `kubectl`：

```shell
kubectl create -n argocd secret tls argocd-dex-server-tls \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem
```

如果憑證是自我簽署的，您還需要在 secret 中新增 `ca.crt`，並填入您的 CA 憑證內容。

請注意，與 `argocd-server` 不同，`argocd-dex-server` 無法自動偵測此 secret 的變更。如果您建立（或更新）此 secret，則需要重新啟動 `argocd-dex-server` pod。

另請注意，憑證應使用正確的 SAN 項目為 `argocd-dex-server` 發行，至少包含 `DNS:argocd-dex-server` 和 `DNS:argocd-dex-server.argo-cd.svc` 的項目，具體取決於您的工作負載如何連線到儲存庫伺服器。

## 在 Argo CD 元件之間設定 TLS

### 為 argocd-repo-server 設定 TLS

`argocd-server` 和 `argocd-application-controller` 都會透過 TLS 使用 gRPC API 與 `argocd-repo-server` 通訊。預設情況下，`argocd-repo-server` 會在啟動時為其 gRPC 端點產生一個非持久性的自我簽署憑證。由於 `argocd-repo-server` 無法連線到 K8s 控制平面 API，因此外部消費者無法取得此憑證進行驗證。因此，`argocd-server` 和 `argocd-application-server` 都將使用非驗證連線來連線到 `argocd-repo-server`。

若要變更此行為以使其更安全，讓 `argocd-server` 和 `argocd-application-controller` 驗證 `argocd-repo-server` 端點的 TLS 憑證，需要執行以下步驟：

* 如上所示，為 `argocd-repo-server` 建立一個持久性 TLS 憑證
* 重新啟動 `argocd-repo-server` pod
* 修改 `argocd-server` 和 `argocd-application-controller` 的 pod 啟動參數，以包含 `--repo-server-strict-tls` 參數。

`argocd-server` 和 `argocd-application-controller` 工作負載現在將使用儲存在 `argocd-repo-server-tls` secret 中的憑證來驗證 `argocd-repo-server` 的 TLS 憑證。

> [!NOTE]
> **憑證到期**
>
> 請確保憑證具有適當的生命週期。請記住，更換憑證時，必須重新啟動所有工作負載才能取得憑證並正常運作。

### 為 argocd-dex-server 設定 TLS

`argocd-server` 透過 TLS 使用 HTTPS API 與 `argocd-dex-server` 通訊。預設情況下，`argocd-dex-server` 會在啟動時為其 HTTPS 端點產生一個非持久性的自我簽署憑證。由於 `argocd-dex-server` 無法連線到 K8s 控制平面 API，因此外部消費者無法取得此憑證進行驗證。因此，`argocd-server` 將使用非驗證連線來連線到 `argocd-dex-server`。

若要變更此行為以使其更安全，讓 `argocd-server` 驗證 `argocd-dex-server` 端點的 TLS 憑證，需要執行以下步驟：

* 如上所示，為 `argocd-dex-server` 建立一個持久性 TLS 憑證
* 重新啟動 `argocd-dex-server` pod
* 修改 `argocd-server` 的 pod 啟動參數，以包含 `--dex-server-strict-tls` 參數。

`argocd-server` 工作負載現在將使用儲存在 `argocd-dex-server-tls` secret 中的憑證來驗證 `argocd-dex-server` 的 TLS 憑證。

> [!NOTE]
> **憑證到期**
>
> 請確保憑證具有適當的生命週期。請記住，更換憑證時，必須重新啟動所有工作負載才能取得憑證並正常運作。

### 停用與 argocd-repo-server 的 TLS

在某些涉及透過 sidecar 代理進行 mTLS 的情境中（例如在服務網格中），您可能希望將 `argocd-server` 和 `argocd-application-controller` 到 `argocd-repo-server` 的連線設定為完全不使用 TLS。

在這種情況下，您需要：

* 將 `argocd-repo-server` 設定為在 gRPC API 上停用 TLS，方法是將 `--disable-tls` 參數指定給 pod 容器的啟動參數。此外，請考慮將監聽位址限制為回送介面，方法是指定 `--listen 127.0.0.1` 參數，以便不安全的端點不會在 pod 的網路介面上公開，但仍可供 sidecar 容器使用。
* 將 `argocd-server` 和 `argocd-application-controller` 設定為不使用 TLS 連線到 `argocd-repo-server`，方法是將 `--repo-server-plaintext` 參數指定給 pod 容器的啟動參數。
* 將 `argocd-server` 和 `argocd-application-controller` 設定為連線到 sidecar 而不是直接連線到 `argocd-repo-server` 服務，方法是透過 `--repo-server <address>` 參數指定其位址。

此變更後，`argocd-server` 和 `argocd-application-controller` 將使用純文字連線到 sidecar 代理，該代理將處理到 `argocd-repo-server` 的 TLS sidecar 代理的所有 TLS 方面。

### 停用與 argocd-dex-server 的 TLS

在某些涉及透過 sidecar 代理進行 mTLS 的情境中（例如在服務網格中），您可能希望將 `argocd-server` 到 `argocd-dex-server` 的連線設定為完全不使用 TLS。

在這種情況下，您需要：

* 將 `argocd-dex-server` 設定為在 HTTPS API 上停用 TLS，方法是將 `--disable-tls` 參數指定給 pod 容器的啟動參數。
* 將 `argocd-server` 設定為不使用 TLS 連線到 `argocd-dex-server`，方法是將 `--dex-server-plaintext` 參數指定給 pod 容器的啟動參數。
* 將 `argocd-server` 設定為連線到 sidecar 而不是直接連線到 `argocd-dex-server` 服務，方法是透過 `--dex-server <address>` 參數指定其位址。

此變更後，`argocd-server` 將使用純文字連線到 sidecar 代理，該代理將處理到 `argocd-dex-server` 的 TLS sidecar 代理的所有 TLS 方面。
