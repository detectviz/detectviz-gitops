# 拉取請求產生器

拉取請求產生器使用 SCMaaS 提供者（GitHub、Gitea 或 Bitbucket Server）的 API 來自動發現儲存庫中開啟的拉取請求。這非常適合在您建立拉取請求時建立測試環境的風格。

```yaml
apiVersion: argroj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      # 使用拉取請求產生器時，ApplicationSet 控制器會每隔 `requeueAfterSeconds` 間隔（預設為每 30 分鐘）輪詢一次以偵測變更。
      requeueAfterSeconds: 1800
      # 請參閱下文以取得提供者特定的選項。
      github:
        # ...
```

> [!NOTE]
> 了解 ApplicationSets 中 PR 產生器的安全隱憂。
> [只有管理員可以建立 ApplicationSets](./Security.md#only-admins-may-createupdatedelete-applicationsets) 以避免
> 洩漏密鑰，並且如果具有 PR 產生器的 ApplicationSet 的 `project` 欄位
> 是範本化的，則[只有管理員可以建立 PR](./Security.md#templated-project-field)，以避免授予超出範圍資源的管理權限。

## GitHub

指定要從中擷取 GitHub 拉取請求的儲存庫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      github:
        # GitHub 組織或使用者。
        owner: myorg
        # Github 儲存庫
        repo: myrepository
        # 對於 GitHub Enterprise（可選）
        api: https://git.example.com/
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: github-token
          key: token
        # （可選）使用 GitHub App 存取 API 而非 PAT。
        appSecretName: github-app-repo-creds
        # Labels 用於篩選您要鎖定的 PR。（可選）
        labels:
        - preview
      requeueAfterSeconds: 1800
  template:
  # ...
```

* `owner`：必要的 GitHub 組織或使用者名稱。
* `repo`：必要的 GitHub 儲存庫名稱。
* `api`：如果使用 GitHub Enterprise，則為存取它的 URL。（可選）
* `tokenRef`：包含用於請求的 GitHub 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。（可選）
* `labels`：將 PR 篩選為包含**所有**所列標籤的 PR。（可選）
* `appSecretName`：包含 [repo-creds 格式][repo-creds] 的 GitHub App 密鑰的 `Secret` 名稱。

[repo-creds]: ../declarative-setup.md#repository-credentials

## GitLab

指定要從中擷取 GitLab 合併請求的專案。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      gitlab:
        # GitLab 專案 ID。
        project: "12341234"
        # 對於自架 GitLab（可選）
        api: https://git.example.com/
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: gitlab-token
          key: token
        # Labels 用於篩選您要鎖定的 MR。（可選）
        labels:
        - preview
        # MR 狀態用於僅篩選具有特定狀態的 MR。（可選）
        pullRequestState: opened
        # 如果為 true，則跳過驗證 SCM 提供者的 TLS 憑證 - 對於自簽憑證很有用。
        insecure: false
        # 參考包含受信任 CA 憑證的 ConfigMap - 對於自簽憑證很有用。（可選）
        caRef:
          configMapName: argocd-tls-certs-cm
          key: gitlab-ca
      requeueAfterSeconds: 1800
  template:
  # ...
```

* `project`：必要的 GitLab 專案的專案 ID。
* `api`：如果使用自架 GitLab，則為存取它的 URL。（可選）
* `tokenRef`：包含用於請求的 GitLab 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。（可選）
* `labels`：Labels 用於篩選您要鎖定的 MR。（可選）
* `pullRequestState`：PullRequestState 是一個額外的 MR 篩選器，僅取得具有特定狀態的 MR。預設為所有狀態。預設值：""（所有狀態）。有效值：`""`、`opened`、`closed`、`merged` 或 `locked`。（可選）
* `insecure`：預設為 (false) - 跳過檢查 SCM 憑證的有效性 - 對於自簽 TLS 憑證很有用。
* `caRef`：可選的 `ConfigMap` 名稱和金鑰，包含要信任的 GitLab 憑證 - 對於自簽 TLS 憑證很有用。可能會參考保存受信任憑證的 ArgoCD CM。

作為將 `insecure` 設定為 true 的較佳替代方案，您可以透過[將自簽憑證掛載到 applicationset 控制器](./Generators-SCM-Provider.md#self-signed-tls-certificates)來為 Gitlab 設定自簽 TLS 憑證。

## Gitea

指定要從中擷取 Gitea 拉取請求的儲存庫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      gitea:
        # Gitea 組織或使用者。
        owner: myorg
        # Gitea 儲存庫
        repo: myrepository
        # 要使用的 Gitea url
        api: https://gitea.mydomain.com/
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: gitea-token
          key: token
        # 許多 gitea 部署使用 TLS，但許多是自架且自簽憑證
        insecure: true
      requeueAfterSeconds: 1800
  template:
  # ...
```

* `owner`：必要的 Gitea 組織或使用者名稱。
* `repo`：必要的 Gitea 儲存庫名稱。
* `api`：Gitea 執行個體的 url。
* `tokenRef`：包含用於請求的 Gitea 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。（可選）
* `insecure`：`允許自簽憑證，主要用於測試。`

## Bitbucket Server

從託管在 Bitbucket Server（與 Bitbucket Cloud 不同）上的儲存庫擷取拉取請求。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      bitbucketServer:
        project: myproject
        repo: myrepository
        # Bitbucket Server 的 URL。必要。
        api: https://mycompany.bitbucket.org
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
      # Bitbucket Server 不支援標籤，因此無法按標籤篩選。
      # 使用來源分支名稱篩選 PR。（可選）
      filters:
      - branchMatch: ".*-argocd"
  template:
  # ...
```

* `project`：必要的 Bitbucket 專案名稱
* `repo`：必要的 Bitbucket 儲存庫名稱。
* `api`：存取 Bitbucket REST API 的必要 URL。對於上面的範例，將向 `https://mycompany.bitbucket.org/rest/api/1.0/projects/myproject/repos/myrepository/pull-requests` 發出 API 請求
* `branchMatch`：應符合來源分支名稱的可選 regexp 篩選器。這是 Bitbucket server 不支援的標籤的替代方案。

如果您想存取私有儲存庫，則還必須提供基本驗證的憑證（這是目前唯一支援的驗證）：
* `username`：用於驗證的使用者名稱。它只需要對相關儲存庫的讀取權限。
* `passwordRef`：包含用於請求的密碼或個人存取權杖的 `Secret` 名稱和金鑰。

如果是 Bitbucket 應用程式權杖，請使用 `bearerToken` 部分。
* `tokenRef`：包含用於請求的應用程式權杖的 `Secret` 名稱和金鑰。

如果是自簽 BitBucket Server 憑證，可以使用以下選項：
* `insecure`：預設為 (false) - 跳過檢查 SCM 憑證的有效性 - 對於自簽 TLS 憑證很有用。
* `caRef`：可選的 `ConfigMap` 名稱和金鑰，包含要信任的 BitBucket server 憑證 - 對於自簽 TLS 憑證很有用。可能會參考保存受信任憑證的 ArgoCD CM。

## Bitbucket Cloud

從託管在 Bitbucket Cloud 上的儲存庫擷取拉取請求。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - pullRequest:
        bitbucket:
          # 儲存庫所在的 Workspace 名稱。必要。
          owner: myproject
          # 儲存庫 slug。必要。
          repo: myrepository
          # Bitbucket Server 的 URL。（可選）將預設為 'https://api.bitbucket.org/2.0'。
          api: https://api.bitbucket.org/2.0
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
        # Bitbucket Cloud 不支援標籤，因此無法按標籤篩選。
        # 使用來源分支名稱篩選 PR。（可選）
        filters:
          - branchMatch: ".*-argocd"

          # 如果您也需要篩選目標分支，可以使用此項
          - targetBranchMatch: "master"

          # 您也可以結合來源和目標分支篩選器，例如
          # 此情況將匹配任何來源分支以「-argocd」結尾且目標分支為 master 的拉取請求
          - branchMatch: ".*-argocd"
            targetBranchMatch: "master"
  template:
  # ...
```

- `owner`：必要的 Bitbucket Workspace 名稱
- `repo`：必要的 Bitbucket 儲存庫名稱。
- `api`：存取 Bitbucket REST API 的可選 URL。對於上面的範例，將向 `https://api.bitbucket.org/2.0/repositories/{workspace}/{repo_slug}/pullrequests` 發出 API 請求。如果未設定，則預設為 `https://api.bitbucket.org/2.0`

您可以使用分支 `filters`，例如
- `branchMatch`：應符合來源分支名稱的可選 regexp 篩選器。
- `targetBranchMatch`：應符合目標分支名稱的可選 regexp 篩選器。

> 注意：Bitbucket 不支援標籤。

如果您想存取私有儲存庫，Argo CD 將需要憑證才能存取 Bitbucket Cloud 中的儲存庫。您可以使用 Bitbucket 應用程式密碼（每個使用者產生，可存取整個 Workspace），或 Bitbucket 應用程式權杖（每個儲存庫產生，存取權限僅限於儲存庫範圍）。如果同時定義了應用程式密碼和應用程式權杖，則將使用應用程式權杖。

若要使用 Bitbucket 應用程式密碼，請使用 `basicAuth` 部分。
- `username`：用於驗證的使用者名稱。它只需要對相關儲存庫的讀取權限。
- `passwordRef`：包含用於請求的密碼或個人存取權杖的 `Secret` 名稱和金鑰。

如果是 Bitbucket 應用程式權杖，請使用 `bearerToken` 部分。
- `tokenRef`：包含用於請求的應用程式權杖的 `Secret` 名稱和金鑰。

## Azure DevOps

指定您要從中擷取拉取請求的組織、專案和儲存庫。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      azuredevops:
        # 要掃描的 Azure DevOps 組織。必要。
        organization: myorg
        # 要掃描的 Azure DevOps 專案名稱。必要。
        project: myproject
        # 要掃描的 Azure DevOps 儲存庫名稱。必要。
        repo: myrepository
        # 要通訊的 Azure DevOps API URL。如果為空，則使用 https://dev.azure.com/。
        api: https://dev.azure.com/
        # 參考包含存取權杖的 Secret。（可選）
        tokenRef:
          secretName: azure-devops-token
          key: token
        # Labels 用於篩選您要鎖定的 PR。（可選）
        labels:
        - preview
      requeueAfterSeconds: 1800
  template:
  # ...
```

* `organization`：必要的 Azure DevOps 組織名稱。
* `project`：必要的 Azure DevOps 專案名稱。
* `repo`：必要的 Azure DevOps 儲存庫名稱。
* `api`：如果使用自架 Azure DevOps Repos，則為存取它的 URL。（可選）
* `tokenRef`：包含用於請求的 Azure DevOps 存取權杖的 `Secret` 名稱和金鑰。如果未指定，將進行匿名請求，其速率限制較低，且只能看到公開儲存庫。（可選）
* `labels`：將 PR 篩選為包含**所有**所列標籤的 PR。（可選）

## 篩選器

篩選器允許選擇要為其產生哪些拉取請求。每個篩選器可以宣告一個或多個條件，所有條件都必須通過。如果存在多個篩選器，則任何一個匹配即可包含儲存庫。如果未指定篩選器，則將處理所有拉取請求。
目前，與 [SCM 提供者](Generators-SCM-Provider.md) 篩選器相比，僅提供一部分篩選器。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      # ...
      # 包含任何以「argocd」結尾的拉取請求分支
      # 和以「feat:」開頭的拉取請求標題。（可選）
      filters:
      - branchMatch: ".*-argocd"
      - titleMatch: "^feat:"
  template:
  # ...
```

* `branchMatch`：針對來源分支名稱進行比對的正規表示式。
* `targetBranchMatch`：針對目標分支名稱進行比對的正規表示式。
* `titleMatch`：針對拉取請求標題進行比對的正規表示式。

[GitHub](#github) 和 [GitLab](#gitlab) 也支援 `labels` 篩選器。

## 範本

與所有產生器一樣，有幾個金鑰可用於在產生的應用程式中進行替換。

以下是一個完整的 Helm 應用程式範例；

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
    # ...
  template:
    metadata:
      name: 'myapp-{{.branch}}-{{.number}}'
    spec:
      source:
        repoURL: 'https://github.com/myorg/myrepo.git'
        targetRevision: '{{.head_sha}}'
        path: kubernetes/
        helm:
          parameters:
          - name: "image.tag"
            value: "pull-{{.author}}-{{.head_sha}}"
      project: "my-project"
      destination:
        server: https://kubernetes.default.svc
        namespace: default
```

而且，這是一個強大的 Kustomize 範例；

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
    # ...
  template:
    metadata:
      name: 'myapp-{{.branch}}-{{.number}}'
    spec:
      source:
        repoURL: 'https://github.com/myorg/myrepo.git'
        targetRevision: '{{.head_sha}}'
        path: kubernetes/
        kustomize:
          nameSuffix: '{{.branch}}'
          commonLabels:
            app.kubernetes.io/instance: '{{.branch}}-{{.number}}'
          images:
          - 'ghcr.io/myorg/myrepo:{{.author}}-{{.head_sha}}'
      project: "my-project"
      destination:
        server: https://kubernetes.default.svc
        namespace: default
```

* `number`：拉取請求的 ID 編號。
* `title`：拉取請求的標題。
* `branch`：拉取請求 head 的分支名稱。
* `branch_slug`：分支名稱將被清理以符合 [RFC 1123](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names) 中定義的 DNS 標籤標準，並截斷為 50 個字元，以便為其附加/後綴 13 個以上的字元留出空間。
* `target_branch`：拉取請求的目標分支名稱。
* `target_branch_slug`：目標分支名稱將被清理以符合 [RFC 1123](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names) 中定義的 DNS 標籤標準，並截斷為 50 個字元，以便為其附加/後綴 13 個以上的字元留出空間。
* `head_sha`：這是拉取請求 head 的 SHA。
* `head_short_sha`：這是拉取請求 head 的短 SHA（8 個字元長，如果 head SHA 較短，則為其長度）。
* `head_short_sha_7`：這是拉取請求 head 的短 SHA（7 個字元長，如果 head SHA 較短，則為其長度）。
* `labels`：拉取請求標籤的陣列。（僅支援 Go 範本 ApplicationSet 資訊清單。）
* `author`：拉取請求的作者/建立者。

## Webhook 組態

使用拉取請求產生器時，ApplicationSet 控制器會每隔 `requeueAfterSeconds` 間隔（預設為每 30 分鐘）輪詢一次以偵測變更。為了消除輪詢的延遲，可以將 ApplicationSet webhook 伺服器設定為接收 webhook 事件，這將觸發拉取請求產生器的應用程式產生。

組態與[Git 產生器](Generators-Git.md)中描述的幾乎相同，但有一個區別：如果您也想使用拉取請求產生器，則需要另外設定以下設定。

> [!NOTE]
> ApplicationSet 控制器 webhook 不使用與[此處](../webhook.md)定義的 API 伺服器相同的 webhook。ApplicationSet 將 webhook 伺服器公開為 ClusterIP 類型的服務。需要建立一個 ApplicationSet 特定的 Ingress 資源以將此服務公開給 webhook 來源。

### Github webhook 組態

在第 1 節「在 Git 提供者中建立 webhook」中，新增一個事件，以便在建立、關閉或標籤變更拉取請求時傳送 webhook 請求。

新增帶有 uri `/api/webhook` 的 Webhook URL，並選取 content-type 為 json
![新增 Webhook URL](../../assets/applicationset/webhook-config-pullrequest-generator.png "新增 Webhook URL")

選取「讓我選取個別事件」，並啟用「拉取請求」的核取方塊。

![新增 Webhook](../../assets/applicationset/webhook-config-pull-request.png "新增 Webhook 拉取請求")

拉取請求產生器將在下一個動作發生時重新排入佇列。

- `opened`
- `closed`
- `reopened`
- `labeled`
- `unlabeled`
- `synchronized`

如需有關每個事件的更多資訊，請參閱[官方文件](https://docs.github.com/en/developers/webhooks-and-events/webhooks/webhook-events-and-payloads)。

### Gitlab webhook 組態

在觸發器清單中啟用「合併請求事件」的核取方塊。

![新增 Gitlab Webhook](../../assets/applicationset/webhook-config-merge-request-gitlab.png "新增 Gitlab 合併請求 Webhook")

拉取請求產生器將在下一個動作發生時重新排入佇列。

- `open`
- `close`
- `reopen`
- `update`
- `merge`

如需有關每個事件的更多資訊，請參閱[官方文件](https://docs.gitlab.com/ee/user/project/integrations/webhook_events.html#merge-request-events)。

## 生命週期

當發現符合設定條件的拉取請求時，將產生一個應用程式 - 即對於 GitHub，當拉取請求符合指定的 `labels` 和/或 `pullRequestState` 時。當拉取請求不再符合指定的條件時，將移除應用程式。

## 透過 `values` 欄位傳遞額外的鍵值對

您可以透過任何拉取請求產生器的 `values` 欄位傳遞額外的、任意的字串鍵值對。透過 `values` 欄位新增的值會新增為 `values.(field)`。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapps
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - pullRequest:
      # ...
      values:
        pr_branch: '{{ .branch }}'
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
> `values.` 前綴總是會附加到透過 `generators.pullRequest.values` 欄位提供的值。在使用時，請確保在 `template` 中的參數名稱中包含此前綴。

在 `values` 中，我們也可以插入上面提到的由拉取請求產生器設定的所有欄位。
