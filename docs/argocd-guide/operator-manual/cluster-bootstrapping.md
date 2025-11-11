# 叢集引導 (Cluster Bootstrapping)

本指南適用於已安裝 Argo CD 的操作員，他們擁有一個新叢集並希望在該叢集中安裝多個應用程式。

解決這個問題沒有單一的特定模式，例如，您可以編寫一個腳本來創建您的應用程式，或者您甚至可以手動創建它們。然而，Argo CD 的使用者傾向於使用 **應用程式的應用程式模式 (app of apps pattern)**。

> [!WARNING]
> **「應用程式的應用程式」是僅限管理員使用的工具**
>
> 在任意 [專案 (Projects)](./declarative-setup.md#projects) 中創建應用程式的能力
> 是一種管理員級別的功能。只有管理員才應該對父應用程式的來源儲存庫有推送權限。
> 管理員應審查對該儲存庫的拉取請求，特別注意每個
> 應用程式中的 `project` 欄位。有權存取安裝 Argo CD 的命名空間的專案實際上擁有管理員級別的
> 權限。

## 應用程式的應用程式模式 (App Of Apps Pattern)

[宣告式地](declarative-setup.md) 指定一個僅由其他應用程式組成的 Argo CD 應用程式。

![應用程式的應用程式](../assets/application-of-applications.png)

### Helm 範例

此範例展示如何使用 Helm 來實現這一點。當然，您也可以使用您喜歡的其他工具。

您的 Git 儲存庫的典型佈局可能是這樣的：

```
├── Chart.yaml
├── templates
│   ├── guestbook.yaml
│   ├── helm-dependency.yaml
│   ├── helm-guestbook.yaml
│   └── kustomize-guestbook.yaml
└── values.yaml
```

`Chart.yaml` 是樣板檔案。

`templates` 目錄中為每個子應用程式包含一個檔案，大致如下：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  destination:
    namespace: argocd
    server: {{ .Values.spec.destination.server }}
  project: default
  source:
    path: guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
```

同步策略設定為 automated + prune，這樣當清單檔案變更時，子應用程式會自動被創建、同步和刪除，但您可能希望禁用此功能。我還添加了 finalizer，它將確保您的應用程式被正確刪除。

將修訂版本固定到一個特定的 Git 提交 SHA，以確保即使子應用程式的儲存庫發生變化，應用程式也只會在父應用程式更改該修訂版本時才會變更。或者，您可以將其設定為 HEAD 或分支名稱。

因為您可能想要覆蓋叢集伺服器，所以這是一個模板化的值。

`values.yaml` 包含預設值：

```yaml
spec:
  destination:
    server: https://kubernetes.default.svc
```

接下來，您需要創建並同步您的父應用程式，例如，透過 CLI：

```bash
argocd app create apps \
    --dest-namespace argocd \
    --dest-server https://kubernetes.default.svc \
    --repo https://github.com/argoproj/argocd-example-apps.git \
    --path apps
argocd app sync apps
```

父應用程式將顯示為同步狀態，但子應用程式將處於不同步狀態：

![新的應用程式的應用程式](../assets/new-app-of-apps.png)

> 注意：您可能希望修改此行為以分階段引導您的叢集；有關更改此行為的資訊，請參閱[應用程式的健康評估](./health.md#argocd-app)。

您可以透過 UI 進行同步，首先透過正確的標籤進行篩選：

![篩選應用程式](../assets/filter-apps.png)

然後選擇「不同步」的應用程式並進行同步：

![同步應用程式](../assets/sync-apps.png)

或者，透過 CLI：

```bash
argocd app sync -l app.kubernetes.io/instance=apps
```

在 [GitHub 上查看範例](https://github.com/argoproj/argocd-example-apps/tree/master/apps)。



### 級聯刪除 (Cascading deletion)

如果您想確保在刪除父應用程式時，子應用程式及其所有資源也會被刪除，請務必在您的 `Application` 定義中添加適當的 [finalizer](../user-guide/app_deletion.md#about-the-deletion-finalizer)。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
 ...
```

### 忽略子應用程式中的差異

為了允許在不觸發不同步狀態的情況下更改子應用程式，或為了調試等目的進行修改，「應用程式的應用程式」模式可與[差異自定義](../user-guide/diffing/)配合使用。以下範例顯示如何忽略對 syncPolicy 和其他常見值的更改。

```yaml
spec:
  ...
  syncPolicy:
    ...
    syncOptions:
      - RespectIgnoreDifferences=true
    ...
  ignoreDifferences:
    - group: "*"
      kind: "Application"
      jsonPointers:
        # 允許手動禁用應用程式的自動同步，對調試很有用。
        - /spec/syncPolicy/automated
        # 這些會定期自動更新。不忽略最後應用的配置，因為它用於在標準化後計算差異。
        - /metadata/annotations/argocd.argoproj.io~1refresh
        - /operation
  ...
```
