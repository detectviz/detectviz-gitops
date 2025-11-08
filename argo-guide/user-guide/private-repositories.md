# 私有儲存庫

> [!NOTE]
> 某些 Git 代管服務 - 特別是 GitLab 以及可能的內部 GitLab 實例 - 要求您在儲存庫 URL 中指定 `.git` 後綴，否則它們會將 HTTP 301 重新導向至後綴為 `.git` 的儲存庫 URL。Argo CD **不會**遵循這些重新導向，因此您必須調整您的儲存庫 URL，使其後綴為 `.git`。

## 憑證

如果應用程式資訊清單位於私有儲存庫中，則必須設定儲存庫憑證。Argo CD 支援 HTTPS 和 SSH Git 憑證。

### HTTPS 使用者名稱和密碼憑證

需要使用者名稱和密碼的私有儲存庫通常具有以 `https://` 而非 `git@` 或 `ssh://` 開頭的 URL。

可以使用 Argo CD CLI 設定憑證：

```bash
argocd repo add https://github.com/argoproj/argocd-example-apps --username <username> --password <password>
```

或 UI：

1. 導覽至 `Settings/Repositories`

    ![連線 repo 概觀](../assets/repo-add-overview.png)

2. 按一下 `Connect Repo using HTTPS` 按鈕並輸入憑證

    ![連線 repo](../assets/repo-add-https.png)

    *注意：螢幕截圖中的使用者名稱僅供說明之用，如果該 GitHub 帳戶存在，我們與之無關。*

3. 按一下 `Connect` 來測試連線並新增儲存庫

![連線 repo](../assets/connect-repo.png)

#### 存取權杖

您可以使用存取權杖而非使用者名稱和密碼。請遵循您的 Git 代管服務的說明來產生權杖：

* [GitHub](https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line)
* [GitLab](https://docs.gitlab.com/ee/user/project/deploy_tokens/)
* [Bitbucket](https://confluence.atlassian.com/bitbucketserver/personal-access-tokens-939515499.html)
* [Azure Repos](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page)

然後，使用任何非空字串作為使用者名稱，並使用存取權杖值作為密碼來連線儲存庫。

> [!NOTE]
> 對於某些服務，您可能需要指定您的帳戶名稱作為使用者名稱，而不是任何字串。

### HTTPS 儲存庫的 TLS 用戶端憑證

如果您的儲存庫伺服器要求您使用 TLS 用戶端憑證進行驗證，您可以設定 Argo CD 儲存庫來使用它們。為此，可以使用 `argocd repo add` 指令的 `--tls-client-cert-path` 和 `--tls-client-cert-key-path` 開關來分別指定本機系統上包含用戶端憑證和對應金鑰的檔案：

```
argocd repo add https://repo.example.com/repo.git --tls-client-cert-path ~/mycert.crt --tls-client-cert-key-path ~/mycert.key
```

當然，如果您的儲存庫伺服器需要，您也可以將其與 `--username` 和 `--password` 開關結合使用。`--tls-client-cert-path` 和 `--tls-client-cert-key-path` 選項必須永遠一起指定。

您的 TLS 用戶端憑證和對應的金鑰也可以使用 UI 進行設定，請參閱使用 HTTPS 新增 Git 儲存庫的說明。

> [!NOTE]
> 您的用戶端憑證和金鑰資料必須是 PEM 格式，不支援其他格式（例如 PKCS12）。另外請確保您的憑證金鑰未受密碼保護，否則 Argo CD 將無法使用它。

> [!NOTE]
> 在 Web UI 的文字區域中貼上 TLS 用戶端憑證和金鑰時，請確保它們不包含非預期的換行符或額外字元。

### SSH 私鑰憑證

需要 SSH 私鑰的私有儲存庫通常具有以 `git@` 或 `ssh://` 而非 `https://` 開頭的 URL。

您可以使用 SSH 透過 CLI 或 UI 設定您的 Git 儲存庫。

> [!NOTE]
> Argo CD 2.4 已升級至 OpenSSH 8.9。OpenSSH 8.8
> [已移除對 `ssh-rsa` SHA-1 金鑰簽章演算法的支援](https://www.openssh.com/txt/release-8.8)。
> 有關測試 SSH 伺服器
> 與 Argo CD 的相容性以及解決不支援較新演算法的伺服器的詳細資訊，請參閱 [2.3 至 2.4 升級指南](../operator-manual/upgrading/2.3-2.4.md)。

使用 CLI：

```
argocd repo add git@github.com:argoproj/argocd-example-apps.git --ssh-private-key-path ~/.ssh/id_rsa
```

使用 UI：

1. 導覽至 `Settings/Repositories`

    ![連線 repo 概觀](../assets/repo-add-overview.png)

2. 按一下 `Connect Repo using SSH` 按鈕，輸入 URL 並貼上 SSH 私鑰

    ![連線 repo](../assets/repo-add-ssh.png)

3. 按一下 `Connect` 來測試連線並新增儲存庫

> [!NOTE]
> 在 UI 中貼上 SSH 私鑰時，請確保文字區域中沒有非預期的換行符或額外字元

> [!NOTE]
> 當您的 SSH 儲存庫是從非標準連接埠提供服務時，您必須使用 `ssh://` 樣式的 URL 來指定您的儲存庫。scp 樣式的 `git@yourgit.com:yourrepo` URL **不**支援連接埠指定，並且會將任何連接埠號碼視為儲存庫路徑的一部分。

### GitHub App 憑證

託管在 GitHub.com 或 GitHub Enterprise 上的私有儲存庫可以使用來自 GitHub 應用程式的憑證進行存取。有關如何建立應用程式的資訊，請參閱 [GitHub 文件](https://docs.github.com/en/developers/apps/about-apps#about-github-apps)。

> [!NOTE]
> 確保您的應用程式對儲存庫的 `Contents` 至少具有 `Read-only` 權限。這是最低要求。

您可以使用 GitHub App 方法，透過 CLI 或 UI，設定對託管在 GitHub.com 或 GitHub Enterprise 上的 Git 儲存庫的存取權限。

使用 CLI：

```
argocd repo add https://github.com/argoproj/argocd-example-apps.git --github-app-id 1 --github-app-installation-id 2 --github-app-private-key-path test.private-key.pem
```

> [!NOTE]
> 若要使用 CLI 在 GitHub Enterprise 上新增私有 Git 儲存庫，請新增 `--github-app-enterprise-base-url https://ghe.example.com/api/v3` 旗標。

使用 UI：

1. 導覽至 `Settings/Repositories`

    ![連線 repo 概觀](../assets/repo-add-overview.png)

2. 按一下 `Connect Repo using GitHub App` 按鈕，選擇類型：`GitHub` 或 `GitHub Enterprise`，輸入 URL、App Id、Installation Id 和應用程式的私鑰。

> [!NOTE]
> 對於 `GitHub Enterprise` 類型，請輸入 GitHub Enterprise Base URL。
> ![連線 repo](../assets/repo-add-github-app.png)

3. 按一下 `Connect` 來測試連線並新增儲存庫

> [!NOTE]
> 在 UI 中貼上 GitHub App 私鑰時，請確保文字區域中沒有非預期的換行符或額外字元

### Google Cloud Source

託管在 Google Cloud Source 上的私有儲存庫可以使用 JSON 格式的 Google Cloud 服務帳戶金鑰進行存取。有關如何建立服務帳戶的資訊，請參閱 [Google Cloud 文件](https://cloud.google.com/iam/docs/creating-managing-service-accounts)。

> [!NOTE]
> 確保您的應用程式對 Google Cloud 專案至少具有 `Source Repository Reader` 權限。這是最低要求。

您可以使用 CLI 或 UI，設定對託管在 Google Cloud Source 上的 Git 儲存庫的存取權限。

使用 CLI：

```
argocd repo add https://source.developers.google.com/p/my-google-cloud-project/r/my-repo --gcp-service-account-key-path service-account-key.json
```

使用 UI：

1. 導覽至 `Settings/Repositories`

   ![連線 repo 概觀](../assets/repo-add-overview.png)

2. 按一下 `Connect Repo using Google Cloud Source` 按鈕，輸入 URL 和 JSON 格式的 Google Cloud 服務帳戶。

   ![連線 repo](../assets/repo-add-google-cloud-source.png)

3. 按一下 `Connect` 來測試連線並新增儲存庫


### 使用 Azure Workload Identity 的 Azure Container Registry/Azure Repos

在使用此功能之前，您必須執行以下步驟以在 Argo CD 中啟用工作負載身分識別組態：

- **為 Pod 加上標籤：** 將 `azure.workload.identity/use: "true"` 標籤新增至 repo-server pod。
- **建立聯合身分識別憑證：** 為 repo-server 服務帳戶產生 Azure 聯合身分識別憑證。有關詳細說明，請參閱[聯合身分識別憑證](https://azure.github.io/azure-workload-identity/docs/topics/federated-identity-credential.html)文件。
- **在服務帳戶中新增註解：** 在 repo-server 服務帳戶中新增 `azure.workload.identity/client-id: "$CLIENT_ID"` 註解，並使用工作負載身分識別中的 `CLIENT_ID`。
- 為工作負載身分識別設定 Azure Container Registry/Azure Repos 的權限。

使用 CLI for Helm OCI with Azure workload identity:

```
argocd repo add contoso.azurecr.io/charts --type helm --enable-oci --use-azure-workload-identity
```

使用 CLI for Azure Repos with Azure workload identity:

```
argocd repo add https://contoso@dev.azure.com/my-projectcollection/my-project/_git/my-repo --use-azure-workload-identity
```

使用 UI：

- 導覽至 `Settings/Repositories`

   ![連線 repo 概觀](../assets/repo-add-overview.png)
- 按一下 `+ Connect Repo`
- 在連線頁面上：
    - 選擇連線方式為 `VIA HTTPS`
    - 選擇類型為 `git` 或 `helm`
    - 輸入儲存庫 URL
    - 如果儲存庫類型是 helm，請輸入名稱
    - 如果儲存庫類型是 helm，請選擇 `Enable OCI`
    - 選擇 `Use Azure Workload Identity`

    ![連線 repo](../assets/repo-add-azure-workload-identity.png)
- 按一下 `Connect`

使用 secret 定義：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: helm-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  url: contoso.azurecr.io/charts
  name: contosocharts
  enableOCI: "true"
  useAzureWorkloadIdentity: "true"
---
apiVersion: v1
kind: Secret
metadata:
  name: git-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://contoso@dev.azure.com/my-projectcollection/my-project/_git/my-repo
  useAzureWorkloadIdentity: "true"
```

## 憑證範本

您也可以設定憑證作為連線儲存庫的範本，而無需重複設定憑證。例如，如果您為 URL 前綴 `https://github.com/argoproj` 設定憑證範本，這些憑證將用於所有以此 URL 為前綴的儲存庫（例如 `https://github.com/argoproj/argocd-example-apps`），前提是它們沒有設定自己的憑證。

若要使用 Web UI 設定憑證範本，只需在「使用 SSH 連線儲存庫」或「使用 HTTPS 連線儲存庫」對話方塊中填寫所有相關的憑證資訊（如上所述），但選擇「另存為憑證範本」而非「連線」來儲存憑證範本。請務必在「儲存庫 URL」欄位中僅輸入前綴 URL（即 `https://github.com/argoproj`）而非完整的儲存庫 URL（即 `https://github.com/argoproj/argocd-example-apps`）。

若要使用 CLI 管理憑證範本，請使用 `repocreds` 子指令，例如 `argocd repocreds add https://github.com/argoproj --username youruser --password yourpass` 將會使用指定的使用者名稱/密碼組合為 URL 前綴 `https://github.com/argoproj` 設定一個憑證範本。與 `repo` 子指令類似，您也可以分別使用 `argocd repocreds list` 和 `argocd repocreds rm` 指令來列出和移除儲存庫憑證。

為了讓 Argo CD 為任何給定的儲存庫使用憑證範本，必須滿足以下條件：

* 儲存庫必須完全未設定，或者如果已設定，則不得包含任何憑證資訊
* 為憑證範本設定的 URL（例如 `https://github.com/argoproj`）必須與儲存庫 URL 的前綴相符（例如 `https://github.com/argoproj/argocd-example-apps`）。

> [!NOTE]
> 需要驗證的儲存庫可以在設定相符的儲存庫憑證後，使用 CLI 或 Web UI 新增而無需指定憑證。

> [!NOTE]
> 符合的憑證範本 URL 前綴是基於_最佳符合_的原則，因此最長的（最佳的）符合項目將優先。定義的順序並不重要，這與 v1.4 之前的組態不同。

以下是一個 CLI 會話的範例，描述了儲存庫憑證的設定：

```bash
# 嘗試在不指定憑證的情況下新增一個私有儲存庫，將會失敗
$ argocd repo add https://docker-build/repos/argocd-example-apps
FATA[0000] rpc error: code = Unknown desc = authentication required 

# 為 https://docker-build/repos 下的所有儲存庫設定一個憑證範本
$ argocd repocreds add https://docker-build/repos --username test --password test
repository credentials for 'https://docker-build/repos' added

# 重複第一步，在不指定憑證的情況下新增儲存庫
# 範本的 URL 符合，將會成功
$ argocd repo add https://docker-build/repos/argocd-example-apps
repository 'https://docker-build/repos/argocd-example-apps' added

# 在 https://docker-build/repos 下新增另一個儲存庫，並指定無效的憑證
# 將會失敗，因為它不會使用範本（有自己的憑證）
$ argocd repo add https://docker-build/repos/example-apps-part-two --username test --password invalid
FATA[0000] rpc error: code = Unknown desc = authentication required
```

## 自我簽署和不受信任的 TLS 憑證

如果您正在使用自我簽署憑證或由 Argo CD 不知道的自訂憑證授權單位 (CA) 簽署的憑證，透過 HTTPS 伺服器連線儲存庫，基於安全原因，儲存庫將不會被新增。這會由一個錯誤訊息表示，例如 `x509: certificate signed by unknown authority`。

1. 您可以讓 ArgoCD 以不安全的方式連線儲存庫，完全不驗證伺服器的憑證。這可以透過在使用 `argocd` CLI 工具新增儲存庫時，使用 `--insecure-skip-server-verification` 旗標來達成。然而，這只應該在非生產環境中進行，因為它會透過可能的中間人攻擊帶來嚴重的安全問題。

2. 您可以使用 `argocd` CLI 工具的 `cert add-tls` 指令，設定 ArgoCD 使用自訂憑證來驗證伺服器的憑證。這是建議的方法，也適用於生產環境。為此，您需要伺服器的憑證，或用於簽署伺服器憑證的 CA 的憑證，格式為 PEM。

> [!NOTE]
> 對於無效的伺服器憑證，例如名稱不符或已過期的憑證，新增 CA 憑證將無濟於事。在這種情況下，您唯一的選擇是使用 `--insecure-skip-server-verification` 旗標來連線儲存庫。強烈建議您在儲存庫伺服器上使用有效的憑證，或敦促伺服器的管理員用有效的憑證替換有問題的憑證。

> [!NOTE]
> TLS 憑證是按伺服器而不是按儲存庫設定的。如果您從同一台伺服器連線多個儲存庫，您只需要為此伺服器設定一次憑證。

> [!NOTE]
> `argocd cert` 指令所做的變更可能需要幾分鐘才能在您的叢集中傳播，具體取決於您的 Kubernetes 設定。

### 使用 CLI 管理 TLS 憑證

您可以使用 `--cert-type https` 修飾符，透過 `argocd cert list` 指令列出所有已設定的 TLS 憑證：

```bash
$ argocd cert list --cert-type https
HOSTNAME      TYPE   SUBTYPE  FINGERPRINT/SUBJECT
docker-build  https  rsa      CN=ArgoCD Test CA
localhost     https  rsa      CN=localhost
```

將 HTTPS 儲存庫新增至 ArgoCD 而不驗證伺服器憑證的範例（**注意：** **不**建議在生產環境中使用）：

```bash
argocd repo add --insecure-skip-server-verification https://git.example.com/test-repo

```

將 `~/myca-cert.pem` 檔案中包含的 CA 憑證新增以正確驗證儲存庫伺服器的範例：

```bash
argocd cert add-tls git.example.com --from ~/myca-cert.pem
argocd repo add https://git.example.com/test-repo
```

您也可以透過將多個 PEM 串連到輸入流中，為伺服器新增多個 PEM。如果儲存庫伺服器即將更換伺服器憑證，且可能由不同的 CA 簽署，這可能會很有用。這樣，您可以讓舊的（目前的）和新的（未來的）憑證共存。如果您已經設定了舊的憑證，請使用 `--upsert` 旗標，並在一次執行中新增舊的和新的：

```bash
cat cert1.pem cert2.pem | argocd cert add-tls git.example.com --upsert
```

> [!NOTE]
> 若要取代伺服器的現有憑證，請使用 `cert add-tls` CLI 指令的 `--upsert` 旗標。

最後，可以使用 `--cert-type https` 修飾符的 `argocd cert rm` 指令來移除 TLS 憑證：

```bash
argocd cert rm --cert-type https localhost
```

### 使用 ArgoCD Web UI 管理 TLS 憑證

可以使用 ArgoCD Web UI 新增和移除 TLS 憑證：

1. 在左側的導覽窗格中，按一下「設定」，然後從設定功能表中選擇「憑證」

2. 以下頁面會列出所有目前已設定的憑證，並提供您新增新的 TLS 憑證或 SSH 已知項目的選項：

    ![管理憑證](../assets/cert-management-overview.png)

3. 按一下「新增 TLS 憑證」，填寫相關資料，然後按一下「建立」。請務必只指定儲存庫伺服器的 FQDN（而非 URL），並將 TLS 憑證的完整 PEM（包括 `----BEGIN CERTIFICATE----` 和 `----END CERTIFICATE----` 行）複製貼上到文字區域欄位中：

    ![新增 tls 憑證](../assets/cert-management-add-tls.png)

4. 若要移除憑證，請按一下憑證項目旁邊的小三點按鈕，從彈出式功能表中選擇「移除」，然後在後續的對話方塊中確認移除。

    ![移除憑證](../assets/cert-management-remove.png)

### 使用宣告式組態管理 TLS 憑證

您也可以在宣告式、自我管理的 ArgoCD 設定中管理 TLS 憑證。所有 TLS 憑證都儲存在 ConfigMap 物件 `argocd-tls-certs-cm` 中。
有關更多資訊，請參閱[操作員手冊](../../operator-manual/declarative-setup/#repositories-using-self-signed-tls-certificates-or-are-signed-by-custom-ca)。

## 未知的 SSH 主機

如果您正在使用透過 SSH 的私有 Git 服務，那麼您有以下選項：

1. 您可以讓 ArgoCD 以不安全的方式連線儲存庫，完全不驗證伺服器的 SSH 主機金鑰。這可以透過在使用 `argocd` CLI 工具新增儲存庫時，使用 `--insecure-skip-server-verification` 旗標來達成。然而，這只應該在非生產環境中進行，因為它會透過可能的中間人攻擊帶來嚴重的安全問題。

2. 您可以使用 `argocd` CLI 工具的 `cert add-ssh` 指令，讓 ArgoCD 知道伺服器的 SSH 公開金鑰。這是建議的方法，也適用於生產環境。為此，您需要伺服器的 SSH 公開主機金鑰，格式為 `ssh` 所理解的 `known_hosts` 格式。您可以使用 `ssh-keyscan` 工具等方式取得伺服器的公開 SSH 主機金鑰。

> [!NOTE]
> `argocd cert` 指令所做的變更可能需要幾分鐘才能在您的叢集中傳播，具體取決於您的 Kubernetes 設定。
> 
> [!NOTE]
> 從 `known_hosts` 檔案匯入 SSH 已知主機金鑰時，輸入資料中的主機名稱或 IP 位址**不得**經過雜湊處理。如果您的 `known_hosts` 檔案包含雜湊項目，則無法用作新增 SSH 已知主機的輸入來源 - 無論是在 CLI 還是 UI 中。如果您絕對希望使用雜湊的已知主機資料，唯一的選擇是使用宣告式設定（見下文）。請注意，這會破壞 CLI 和 UI 憑證管理，因此通常不建議這樣做。

### 使用 CLI 管理 SSH 已知主機

您可以使用 `--cert-type ssh` 修飾符，透過 `argocd cert list` 指令列出所有已設定的 SSH 已知主機項目：

```bash
$ argocd cert list --cert-type ssh
HOSTNAME                 TYPE  SUBTYPE              FINGERPRINT/SUBJECT
bitbucket.org            ssh   ssh-rsa              SHA256:46OSHA1Rmj8E8ERTC6xkNcmGOw9oFxYr0WF6zWW8l1E
github.com               ssh   ssh-rsa              SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s
gitlab.com               ssh   ecdsa-sha2-nistp256  SHA256:HbW3g8zUjNSksFbqTiUWPWg2Bq1x8xdGUrliXFzSnUw
gitlab.com               ssh   ssh-ed25519          SHA256:eUXGGm1YGsMAS7vkcx6JOJdOGHPem5gQp4taiCfCLB8
gitlab.com               ssh   ssh-rsa              SHA256:ROQFvPThGrW4RuWLoL9tq9I9zJ42fK4XywyRtbOz/EQ
ssh.dev.azure.com        ssh   ssh-rsa              SHA256:ohD8VZEXGWo6Ez8GSEJQ9WpafgLFsOfLOtGGQCQo6Og
vs-ssh.visualstudio.com  ssh   ssh-rsa              SHA256:ohD8VZEXGWo6Ez8GSEJQ9WpafgLFsOfLOtGGQCQo6Og
```

若要新增 SSH 已知主機項目，可以使用 `argocd cert add-ssh` 指令。您可以從檔案新增（使用 `--from <file>` 修飾符），或在指定 `--batch` 修飾符時從 `stdin` 讀取。在這兩種情況下，輸入都必須是 OpenSSH 用戶端所理解的 `known_hosts` 格式。

將 `ssh-keyscan` 收集的所有可用 SSH 公開主機金鑰新增至 ArgoCD 的範例：

```bash
ssh-keyscan server.example.com | argocd cert add-ssh --batch 

```

將現有的 `known_hosts` 檔案匯入 ArgoCD 的範例：

```bash
argocd cert add-ssh --batch --from /etc/ssh/ssh_known_hosts
```

最後，可以使用 `--cert-type ssh` 修飾符的 `argocd cert rm` 指令來移除 SSH 已知主機項目：

```bash
argocd cert rm bitbucket.org --cert-type ssh
```

如果您對於給定的主機有多個具有不同金鑰子類型（例如，如上例中的 gitlab.com，有 `ssh-rsa`、`ssh-ed25519` 和 `ecdsa-sha2-nistp256` 子類型的金鑰）的 SSH 已知主機項目，而您只想移除其中一個，您可以使用 `--cert-sub-type` 修飾符進一步縮小選擇範圍：

```bash
argocd cert rm gitlab.com --cert-type ssh --cert-sub-type ssh-ed25519
```

### 使用 ArgoCD Web UI 管理 SSH 已知主機資料

可以使用 ArgoCD Web UI 新增和移除 SSH 已知主機項目：

1. 在左側的導覽窗格中，按一下「設定」，然後從設定功能表中選擇「憑證」

2. 以下頁面會列出所有目前已設定的憑證，並提供您新增新的 TLS 憑證或 SSH 已知項目的選項：

    ![管理憑證](../assets/cert-management-overview.png)

3. 按一下「新增 SSH 已知主機」，然後在以下遮罩中貼上您的 SSH 已知主機資料。**重要事項**：貼上資料時，請確保項目（金鑰資料）中沒有換行符。之後，按一下「建立」。

    ![管理 ssh 已知主機](../assets/cert-management-add-ssh.png)

4. 若要移除憑證，請按一下憑證項目旁邊的小三點按鈕，從彈出式功能表中選擇「移除」，然後在後續的對話方塊中確認移除。

    ![移除憑證](../assets/cert-management-remove.png)

### 使用宣告式設定管理 SSH 已知主機資料

您也可以在宣告式、自我管理的 ArgoCD 設定中管理 SSH 已知主機項目。所有 SSH 公開主機金鑰都儲存在 ConfigMap 物件 `argocd-ssh-known-hosts-cm` 中。有關更多詳細資訊，請參閱[操作員手冊](../operator-manual/declarative-setup.md#ssh-known-host-public-keys)。

## Helm

Helm charts 可以來自受保護的 Helm 儲存庫或 OCI 註冊中心。您可以透過指定 `helm` 作為基於 HTTPS 的儲存庫的_類型_，使用 CLI 或 UI 來設定對受保護 Helm chart 的存取。

使用 CLI：

指定 `argocd repo add` 指令的 `--type` 旗標：

```bash
argocd repo add https://argoproj.github.io/argo-helm --type=helm <additional-flags>
```

使用 UI：

1. 導覽至 `Settings/Repositories`

    ![連線 repo 概觀](../assets/repo-add-overview.png)

2. 按一下 `Connect Repo` 按鈕

3. 選擇 `VIA HTTPS` 作為連線方式

4. 選擇 `helm` 作為類型。

    ![helm 儲存庫類型](../assets/repo-type-helm.png)

5. 按一下 `Connect` 來測試連線並新增儲存庫

儲存在受保護 OCI 註冊中心中的 Helm chart 應遵循先前描述的步驟，並明確指定來源是儲存在 OCI 註冊中心中的 Helm chart。

使用 CLI：

指定 `argocd repo add` 指令的 `--enable-oci` 旗標：

```bash
argocd repo add registry-1.docker.io/bitnamicharts --type=helm --enable-oci=true <additional-flags>
```

> [!NOTE]
> 參照 OCI 註冊中心時，應省略協定，例如 `oci://`

使用 UI：

新增基於 HTTPS 的 _helm_ 儲存庫時，請選取 _啟用 OCI_ 核取方塊。

## Git Submodules

支援子模組，並且會自動偵測。如果子模組儲存庫需要驗證，則憑證需要與父儲存庫的憑證相符。設定 ARGOCD_GIT_MODULES_ENABLED=false 以停用子模組支援。

## 宣告式組態

請參閱[宣告式設定](../operator-manual/declarative-setup.md#repositories)
