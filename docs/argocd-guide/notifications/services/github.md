# GitHub

## 參數

GitHub 通知服務使用 [GitHub Apps](https://docs.github.com/en/developers/apps) 變更提交狀態，並需要指定以下設定：

- `appID` - 應用程式 ID
- `installationID` - 應用程式安裝 ID
- `privateKey` - 應用程式私鑰
- `enterpriseBaseURL` - 可選的 URL，例如 https://git.example.com/api/v3

> ⚠️ _注意：_ 在 [argoproj/notifications-engine#205](https://github.com/argoproj/notifications-engine/issues/205) 解決之前，需要在 `enterpriseBaseURL` 中指定 `/api/v3`。

## 組態

1. 使用 https://github.com/settings/apps/new 建立一個 GitHub Apps
1. 變更儲存庫權限以啟用寫入提交狀態和/或部署和/或拉取請求註解
   ![2](https://user-images.githubusercontent.com/18019529/108397381-3ca57980-725b-11eb-8d17-5b8992dc009e.png)
1. 產生一個私鑰，並自動下載
   ![3](https://user-images.githubusercontent.com/18019529/108397926-d4a36300-725b-11eb-83fe-74795c8c3e03.png)
1. 將應用程式安裝到帳戶
1. 將 privateKey 儲存在 `argocd-notifications-secret` Secret 中，並在 `argocd-notifications-cm` ConfigMap 中設定 GitHub 整合

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  service.github: |
    appID: <app-id>
    installationID: <installation-id>
    privateKey: $github-privateKey
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <secret-name>
stringData:
  github-privateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    (snip)
    -----END RSA PRIVATE KEY-----
```

6. 為您的 GitHub 整合建立訂閱

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.<trigger-name>.github: ""
```

## 範本

![](https://user-images.githubusercontent.com/18019529/108520497-168ce180-730e-11eb-93cb-b0b91f99bdc5.png)

```yaml
template.app-deployed: |
  message: |
    應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
  github:
    repoURLPath: "{{.app.spec.source.repoURL}}"
    revisionPath: "{{.app.status.operationState.syncResult.revision}}"
    status:
      state: success
      label: "continuous-delivery/{{.app.metadata.name}}"
      targetURL: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
    deployment:
      state: success
      environment: production
      environmentURL: "https://{{.app.metadata.name}}.example.com"
      logURL: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      requiredContexts: []
      autoMerge: true
      transientEnvironment: false
      reference: v1.0.0
    pullRequestComment:
      content: |
        應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
        在此處查看更多資訊：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true
      commentTag: "continuous-delivery/{{.app.metadata.name}}"
    checkRun:
      name: "continuous-delivery/{{.app.metadata.name}}"
      details_url: "{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true"
      status: completed
      conclusion: success
      started_at: "YYYY-MM-DDTHH:MM:SSZ"
      completed_at: "YYYY-MM-DDTHH:MM:SSZ"
      output:
        title: "在 ArgoCD 上部署 {{.app.metadata.name}}"
        summary: "應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。"
        text: |
          應用程式 {{.app.metadata.name}} 現在正在執行新版本的部署資訊清單。
          在此處查看更多資訊：{{.context.argocdUrl}}/applications/{{.app.metadata.name}}?operation=true
```

**注意事項**：

- 如果訊息設定為 140 個字元或更多，它將被截斷。
- 如果 `github.repoURLPath` 和 `github.revisionPath` 與上面相同，則可以省略它們。
- Automerge 是可選的，對於 github 部署，預設為 `true`，以確保請求的 ref 與預設分支保持最新。
  如果您想在預設分支中部署較舊的 ref，則需要將此選項設定為 `false`。
  如需更多資訊，請參閱 [GitHub 部署 API 文件](https://docs.github.com/en/rest/deployments/deployments?apiVersion=2022-11-28#create-a-deployment)。
- 如果 `github.pullRequestComment.content` 設定為 65536 個字元或更多，它將被截斷。
- `github.pullRequestComment.commentTag` 參數用於識別註解。如果找到具有指定標籤的註解，它將被更新（upserted）。如果找不到具有該標籤的註解，則會建立一個新的註解。
- Reference 是可選的。設定後，它將被用作要部署的 ref。如果未設定，則修訂版本將被用作要部署的 ref。
