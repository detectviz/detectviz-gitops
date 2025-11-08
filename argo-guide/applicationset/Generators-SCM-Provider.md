# SCM 提供者產生器

SCM 提供者產生器使用 SCMaaS 提供者（例如 GitHub）的 API 來自動發現組織內的儲存庫。這非常適合將微服務分散到許多儲存庫中的 GitOps 佈局模式。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      # 要使用的克隆協定。
      cloneProtocol: ssh
      # 請參閱下文以取得提供者特定的選項。
      github:
        # ...
```

* `cloneProtocol`：用於 SCM URL 的協定。預設值因提供者而異，但如果可能，則為 ssh。並非所有提供者都必定支援所有協定，請參閱下方的提供者文件以取得可用選項。

> [!NOTE]
> 了解使用 SCM 產生器的安全隱憂。[只有管理員可以建立 ApplicationSets](./Security.md#only-admins-may-createupdatedelete-applicationsets)
> 以避免洩漏密鑰，並且如果具有 SCM 產生器的 ApplicationSet 的
> `project` 欄位是範本化的，則[只有管理員可以建立儲存庫/分支](./Security.md#templated-project-field)，以避免授予對
> 超出範圍資源的管理權限。

## GitHub

GitHub 模式使用 GitHub API 來掃描 github.com 或 GitHub Enterprise 中的組織。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      github:
        # 要掃描的 GitHub 組織。
        organization: myorg
        # 對於 GitHub Enterprise：
        api: https://git.example.com/
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描預設分支。預設為 false。
        allBranches: true
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: github-token
          key: token
        # （可選）使用 GitHub App 存取 API 而非 PAT。
        appSecretName: gh-app-repo-creds
  template:
  # ...
```

* `organization`：必要的 GitHub 組織名稱以進行掃描。如果您有多個組織，請使用多個產生器。
* `api`：如果使用 GitHub Enterprise，則為存取它的 URL。
* `allBranches`：預設情況下 (false)，範本將僅針對每個儲存庫的預設分支進行評估。如果為 true，則每個儲存庫的每個分支都將傳遞給篩選器。如果使用此旗標，您可能需要使用 `branchMatch` 篩選器。
* `tokenRef`：包含用於請求的 GitHub 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。
* `appSecretName`：包含 [repo-creds 格式][repo-creds] 的 GitHub App 密鑰的 `Secret` 名稱。

[repo-creds]: ../declarative-setup.md#repository-credentials

對於標籤篩選，會使用儲存庫主題。

可用的克隆協定為 `ssh` 和 `https`。

## Gitlab

GitLab 模式使用 GitLab API 來掃描 gitlab.com 或自架 GitLab 中的組織。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      gitlab:
        # 要掃描的基本 GitLab 群組。您可以使用群組 ID 或完整的命名空間路徑。
        group: "8675309"
        # 對於自架 GitLab：
        api: https://gitlab.example.com/
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描預設分支。預設為 false。
        allBranches: true
        # 如果為 true，則遞迴搜尋子群組。如果為 false，則僅在基本群組中搜尋。預設為 false。
        includeSubgroups: true
        # 如果為 true 且 includeSubgroups 也為 true，則包含共用專案，這是 gitlab API 的預設值。
        # 如果為 false，則僅搜尋相同路徑下的專案。預設為 true。
        includeSharedProjects: false
        # 按主題篩選專案。Gitlab API 支援單一主題。預設為 ""（所有主題）。
        topic: "my-topic"
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: gitlab-token
          key: token
        # 如果為 true，則跳過驗證 SCM 提供者的 TLS 憑證 - 對於自簽憑證很有用。
        insecure: false
        # 參考包含受信任 CA 憑證的 ConfigMap - 對於自簽憑證很有用。（可選）
        caRef:
          configMapName: argocd-tls-certs-cm
          key: gitlab-ca
  template:
  # ...
```

* `group`：必要的 GitLab 基本群組名稱以進行掃描。如果您有多個基本群組，請使用多個產生器。
* `api`：如果使用自架 GitLab，則為存取它的 URL。
* `allBranches`：預設情況下 (false)，範本將僅針對每個儲存庫的預設分支進行評估。如果為 true，則每個儲存庫的每個分支都將傳遞給篩選器。如果使用此旗標，您可能需要使用 `branchMatch` 篩選器。
* `includeSubgroups`：預設情況下 (false)，控制器將僅在基本群組中直接搜尋儲存庫。如果為 true，它將遞迴搜尋所有子群組以尋找要掃描的儲存庫。
* `includeSharedProjects`：如果為 true 且 includeSubgroups 也為 true，則包含共用專案，這是 gitlab API 的預設值。如果為 false，則僅搜尋相同路徑下的專案。通常，大多數人會希望設定為 false 時的行為。預設為 true。
* `topic`：按主題篩選專案。Gitlab API 支援單一主題。預設為 ""（所有主題）。
* `tokenRef`：包含用於請求的 GitLab 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。
* `insecure`：預設為 (false) - 跳過檢查 SCM 憑證的有效性 - 對於自簽 TLS 憑證很有用。
* `caRef`：可選的 `ConfigMap` 名稱和金鑰，包含要信任的 GitLab 憑證 - 對於自簽 TLS 憑證很有用。可能會參考保存受信任憑證的 ArgoCD CM。

對於標籤篩選，會使用儲存庫主題。

可用的克隆協定為 `ssh` 和 `https`。

### 自簽 TLS 憑證

作為將 `insecure` 設定為 true 的較佳替代方案，您可以為 Gitlab 設定自簽 TLS 憑證。

為了讓 ApplicationSet 的 SCM / PR Gitlab 產生器使用自簽 TLS 憑證，需要將憑證掛載到 applicationset-controller 上。掛載的憑證路徑必須使用環境變數 `ARGOCD_APPLICATIONSET_CONTROLLER_SCM_ROOT_CA_PATH` 或參數 `--scm-root-ca-path` 明確設定。applicationset 控制器將讀取掛載的憑證以建立用於 SCM/PR 提供者的 Gitlab 用戶端。

可以透過在 argocd-cmd-params-cm ConfigMap 中設定 `applicationsetcontroller.scm.root.ca.path` 來方便地實現此目的。設定此值後，請務必重新啟動 ApplicationSet 控制器。

## Gitea

Gitea 模式使用 Gitea API 來掃描您執行個體中的組織

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      gitea:
        # 要掃描的 Gitea 擁有者。
        owner: myorg
        # Gitea 執行個體 url
        api: https://gitea.mydomain.com/
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描預設分支。預設為 false。
        allBranches: true
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: gitea-token
          key: token
  template:
  # ...
```

* `owner`：必要的 Gitea 組織名稱以進行掃描。如果您有多個組織，請使用多個產生器。
* `api`：您正在使用的 Gitea 執行個體的 URL。
* `allBranches`：預設情況下 (false)，範本將僅針對每個儲存庫的預設分支進行評估。如果為 true，則每個儲存庫的每個分支都將傳遞給篩選器。如果使用此旗標，您可能需要使用 `branchMatch` 篩選器。
* `tokenRef`：包含用於請求的 Gitea 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。
* `insecure`：允許自簽 TLS 憑證。

此 SCM 提供者尚不支援標籤篩選

可用的克隆協定為 `ssh` 和 `https`。

## Bitbucket Server

使用 Bitbucket Server API (1.0) 來掃描專案中的儲存庫。請注意，Bitbucket Server 與 Bitbucket Cloud (API 2.0) 不同

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      bitbucketServer:
        project: myproject
        # Bitbucket Server 的 URL。必要。
        api: https://mycompany.bitbucket.org
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描預設分支。預設為 false。
        allBranches: true
        # 基本驗證的憑證（應用程式密碼）。存取私有儲存庫需要基本驗證或持有者權杖
        # 驗證
        basicAuth:
          # 用於驗證的使用者名稱
          username: myuser
          # 參考包含密碼或個人存取權杖的 Secret。
          passwordRef:
            secretName: mypassword
            key: password
        # 持有者權杖（應用程式權杖）驗證的憑證。存取私有儲存庫需要基本驗證或持有者權杖
        # 驗證
        bearerToken:
          # 參考包含持有者權杖的 Secret。
          tokenRef:
            secretName: repotoken
            key: token
        # 如果為 true，則跳過驗證 SCM 提供者的 TLS 憑證 - 對於自簽憑證很有用。
        insecure: true
        # 參考包含受信任 CA 憑證的 ConfigMap - 對於自簽憑證很有用。（可選）
        caRef:
          configMapName: argocd-tls-certs-cm
          key: bitbucket-ca
        # 對於按標籤篩選的支援正在開發中。Bitbucket server 不支援 PR 的標籤，但支援儲存庫的標籤
  template:
  # ...
```

* `project`：必要的 Bitbucket 專案名稱
* `api`：存取 Bitbucket REST api 的必要 URL。
* `allBranches`：預設情況下 (false)，範本將僅針對每個儲存庫的預設分支進行評估。如果為 true，則每個儲存庫的每個分支都將傳遞給篩選器。如果使用此旗標，您可能需要使用 `branchMatch` 篩選器。

如果您想存取私有儲存庫，則還必須提供基本驗證的憑證（這是目前唯一支援的驗證）：
* `username`：用於驗證的使用者名稱。它只需要對相關儲存庫的讀取權限。
* `passwordRef`：包含用於請求的密碼或個人存取權杖的 `Secret` 名稱和金鑰。

如果是 Bitbucket 應用程式權杖，請使用 `bearerToken` 部分。
* `tokenRef`：包含用於請求的應用程式權杖的 `Secret` 名稱和金鑰。

如果是自簽 BitBucket Server 憑證，可以使用以下選項：
* `insecure`：預設為 (false) - 跳過檢查 SCM 憑證的有效性 - 對於自簽 TLS 憑證很有用。
* `caRef`：可選的 `ConfigMap` 名稱和金鑰，包含要信任的 BitBucket server 憑證 - 對於自簽 TLS 憑證很有用。可能會參考保存受信任憑證的 ArgoCD CM。

可用的克隆協定為 `ssh` 和 `https`。

## Azure DevOps

使用 Azure DevOps API 來根據 Azure DevOps 組織內的團隊專案來尋找符合資格的儲存庫。
預設的 Azure DevOps URL 為 `https://dev.azure.com`，但可以使用 `azureDevOps.api` 欄位來覆寫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      azureDevOps:
        # Azure DevOps 組織。
        organization: myorg
        # Azure DevOps 的 URL。可選。預設為 https://dev.azure.com。
        api: https://dev.azure.com
        # 如果為 true，則掃描符合資格的儲存庫的每個分支。如果為 false，則僅檢查符合資格的儲存庫的預設分支。預設為 false。
        allBranches: true
        # 指定的 Azure DevOps 組織內的團隊專案。
        teamProject: myProject
        # 參考包含用於存取 Azure DevOps 的 Azure DevOps 個人存取權杖 (PAT) 的 Secret。
        accessTokenRef:
          secretName: azure-devops-scm
          key: accesstoken
  template:
  # ...
```

* `organization`：必要。Azure DevOps 組織的名稱。
* `teamProject`：必要。指定 `organization` 內的團隊專案名稱。
* `accessTokenRef`：必要。包含用於請求的 Azure DevOps 個人存取權杖 (PAT) 的 `Secret` 名稱和金鑰。
* `api`：可選。Azure DevOps 的 URL。如果未設定，則使用 `https://dev.azure.com`。
* `allBranches`：可選，預設為 `false`。如果為 `true`，則掃描符合資格的儲存庫的每個分支。如果為 `false`，則僅檢查符合資格的儲存庫的預設分支。

## Bitbucket Cloud

Bitbucket 模式使用 Bitbucket API V2 來掃描 bitbucket.org 中的工作區。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      bitbucket:
        # 工作區 ID (slug)。
        owner: "example-owner"
        # 用於使用應用程式密碼進行基本驗證的使用者。
        user: "example-user"
        # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描主分支。預設為 false。
        allBranches: true
        # 參考包含應用程式密碼的 Secret。
        appPasswordRef:
          secretName: appPassword
          key: password
  template:
  # ...
```

* `owner`：在尋找儲存庫時要使用的工作區 ID (slug)。
* `user`：用於向 bitbucket.org 上的 Bitbucket API V2 進行驗證的使用者。
* `allBranches`：預設情況下 (false)，範本將僅針對每個儲存庫的主分支進行評估。如果為 true，則每個儲存庫的每個分支都將傳遞給篩選器。如果使用此旗標，您可能需要使用 `branchMatch` 篩選器。
* `appPasswordRef`：包含用於請求的 bitbucket 應用程式密碼的 `Secret` 名稱和金鑰。

此 SCM 提供者尚不支援標籤篩選

可用的克隆協定為 `ssh` 和 `https`。

## AWS CodeCommit (Alpha)

使用 AWS ResourceGroupsTagging 和 AWS CodeCommit API 來掃描跨 AWS 帳戶和區域的儲存庫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
    - scmProvider:
        awsCodeCommit:
          # 要掃描儲存庫的 AWS 區域。
          # 預設為 ApplicationSet 控制器的環境區域。
          region: us-east-1
          # 用於掃描儲存庫的 AWS 角色。
          # 預設為 ApplicationSet 控制器的環境角色。
          role: arn:aws:iam::111111111111:role/argocd-application-set-discovery
          # 如果為 true，則掃描每個儲存庫的每個分支。如果為 false，則僅掃描主分支。預設為 false。
          allBranches: true
          # 用於篩選儲存庫的 AWS 資源標籤。
          # 如需詳細資訊，請參閱 https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/API_GetResources.html#resourcegrouptagging-GetResources-request-TagFilters
          # 預設為無 tagFilters，以包含區域中的所有儲存庫。
          tagFilters:
            - key: organization
              value: platform-engineering
            - key: argo-ready
  template:
  # ...
```

* `region`：（可選）要掃描儲存庫的 AWS 區域。預設情況下，使用 ApplicationSet 控制器的目前區域。
* `role`：（可選）用於掃描儲存庫的 AWS 角色。預設情況下，使用 ApplicationSet 控制器的目前角色。
* `allBranches`：（可選）如果為 `true`，則掃描符合資格的儲存庫的每個分支。如果為 `false`，則僅檢查符合資格的儲存庫的預設分支。預設為 `false`。
* `tagFilters`：（可選）用於篩選 AWS CodeCommit 儲存庫的 tagFilters 清單。如需詳細資訊，請參閱 [AWS ResourceGroupsTagging API](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/API_GetResources.html#resourcegrouptagging-GetResources-request-TagFilters)。預設情況下，不包含任何篩選器。

此 SCM 提供者不支援以下功能

* 標籤篩選
* `sha`、`short_sha` 和 `short_sha_7` 範本參數

可用的克隆協定為 `ssh`、`https` 和 `https-fips`。

### AWS IAM 權限注意事項

為了呼叫 AWS API 以發現 AWS CodeCommit 儲存庫，ApplicationSet 控制器必須使用有效的環境 AWS 組態進行設定，例如目前的 AWS 區域和 AWS 憑證。
可以透過所有標準選項提供 AWS 組態，例如執行個體中繼資料服務 (IMDS)、組態檔、環境變數或服務帳戶的 IAM 角色 (IRSA)。

根據 `awsCodeCommit` 屬性中是否提供 `role`，AWS IAM 權限要求會有所不同。

#### 在與 ApplicationSet 控制器相同的 AWS 帳戶中發現 AWS CodeCommit 儲存庫

如果未指定 `role`，ApplicationSet 控制器將使用自己的 AWS 身分來掃描 AWS CodeCommit 儲存庫。
當您有一個簡單的設定，所有 AWS CodeCommit 儲存庫都與您的 Argo CD 位於同一個 AWS 帳戶中時，這很適用。

由於 ApplicationSet 控制器 AWS 身分直接用於儲存庫發現，因此必須授予其以下 AWS 權限。

* `tag:GetResources`
* `codecommit:ListRepositories`
* `codecommit:GetRepository`
* `codecommit:GetFolder`
* `codecommit:ListBranches`

#### 跨 AWS 帳戶和區域發現 AWS CodeCommit 儲存庫

透過指定 `role`，ApplicationSet 控制器將首先擔任 `role`，並將其用於儲存庫發現。
這使得更複雜的使用案例能夠從不同的 AWS 帳戶和區域發現儲存庫。

ApplicationSet 控制器 AWS 身分應被授予擔任目標 AWS 角色的權限。

* `sts:AssumeRole`

所有 AWS 角色都必須具有儲存庫發現相關權限。

* `tag:GetResources`
* `codecommit:ListRepositories`
* `codecommit:GetRepository`
* `codecommit:GetFolder`
* `codecommit:ListBranches`

## 篩選器

篩選器允許選擇要為其產生哪些儲存庫。每個篩選器可以宣告一個或多個條件，所有條件都必須通過。如果存在多個篩選器，則任何一個匹配即可包含儲存庫。如果未指定篩選器，則將處理所有儲存庫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  generators:
  - scmProvider:
      filters:
      # 包含任何以「myapp」開頭的儲存庫，且包含 Kustomize 組態，且標記為「deploy-ok」…
      - repositoryMatch: ^myapp
        pathsExist: [kubernetes/kustomization.yaml]
        labelMatch: deploy-ok
      # … 或包含任何以「otherapp」開頭的儲存庫，且具有 Helm 資料夾，且沒有檔案 disabledrepo.txt。
      - repositoryMatch: ^otherapp
        pathsExist: [helm]
        pathsDoNotExist: [disabledrepo.txt]
  template:
  # ...
```

* `repositoryMatch`：針對儲存庫名稱進行比對的正規表示式。
* `pathsExist`：儲存庫中必須存在的一組路徑。可以是檔案或目錄。
* `pathsDoNotExist`：儲存庫中不得存在的一組路徑。可以是檔案或目錄。
* `labelMatch`：針對儲存庫標籤進行比對的正規表示式。如果任何標籤符合，則包含儲存庫。
* `branchMatch`：針對分支名稱進行比對的正規表示式。

## 範本

與所有產生器一樣，有幾個參數可供在 `ApplicationSet` 資源範本中使用。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - scmProvider:
    # ...
  template:
    metadata:
      name: '{{ .repository }}'
    spec:
      source:
        repoURL: '{{ .url }}'
        targetRevision: '{{ .branch }}'
        path: kubernetes/
      project: default
      destination:
        server: https://kubernetes.default.svc
        namespace: default
```

* `organization`：儲存庫所在的組織名稱。
* `repository`：儲存庫的名稱。
* `repository_id`：儲存庫的 ID。
* `url`：儲存庫的克隆 URL。
* `branch`：儲存庫的預設分支。
* `sha`：分支的 Git 提交 SHA。
* `short_sha`：分支的縮寫 Git 提交 SHA（8 個字元或 `sha` 的長度，如果較短）。
* `short_sha_7`：分支的縮寫 Git 提交 SHA（7 個字元或 `sha` 的長度，如果較短）。
* `labels`：如果是 Gitea，則為儲存庫標籤的逗號分隔清單；如果是 Gitlab 和 Github，則為儲存庫主題。Bitbucket Cloud、Bitbucket Server 或 Azure DevOps 不支援。
* `branchNormalized`：`branch` 的值，正規化為僅包含小寫字母數字字元、「-」或「.」。

## 透過 `values` 欄位傳遞額外的鍵值對

您可以透過任何 SCM 產生器的 `values` 欄位傳遞額外的、任意的字串鍵值對。透過 `values` 欄位新增的值會新增為 `values.(field)`。

在此範例中，傳遞了一個 `name` 參數值。它從 `organization` 和 `repository` 中插值，以產生不同的範本名稱。
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - scmProvider:
      bitbucketServer:
        project: myproject
        api: https://mycompany.bitbucket.org
        allBranches: true
        basicAuth:
          username: myuser
          passwordRef:
            secretName: mypassword
            key: password
      values:
        name: "{{.organization}}-{{.repository}}"

  template:
    metadata:
      name: '{{ .values.name }}'
    spec:
      source:
        repoURL: '{{ .url }}'
        targetRevision: '{{ .branch }}'
        path: kubernetes/
      project: default
      destination:
        server: https://kubernetes.default.svc
        namespace: default
```

> [!NOTE]
> `values.` 前綴總是會附加到透過 `generators.scmProvider.values` 欄位提供的值。在使用時，請確保在 `template` 中的參數名稱中包含此前綴。

在 `values` 中，我們也可以插入上面提到的由 SCM 產生器設定的所有欄位。
