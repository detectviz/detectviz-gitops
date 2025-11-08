# 略過應用程式協調

> [!WARNING]
> **Alpha 功能 (自 v2.7.0 起)**
>
> 這是一個實驗性的 [alpha 品質](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md#alpha) 功能。
> 主要使用案例是提供與第三方專案的整合。
> 此功能可能會在未來的版本中移除或以不向後相容的方式修改。

Argo CD 允許使用者停止應用程式的協調。
略過協調選項是透過 `argocd.argoproj.io/skip-reconcile: "true"` 註解來設定。
當應用程式設定為略過協調時，
該應用程式的所有處理都會停止。
在應用程式未處理期間，
應用程式的 `status` 欄位將不會更新。
如果新建立的應用程式帶有略過協調註解，
則應用程式的 `status` 欄位將不存在。
若要恢復應用程式的協調或處理，
請移除該註解或將其值設定為 `"false"`。

請參閱以下範例以啟用應用程式略過協調：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/skip-reconcile: "true"
```

請參閱以下範例，了解一個新建立並啟用略過協調的應用程式：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/skip-reconcile: "true"
  name: guestbook
  namespace: argocd
spec:
  destination:
    namespace: guestbook
    server: https://kubernetes.default.svc
  project: default
  source:
    path: guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
```

`status` 欄位不存在。

## 主要使用案例

略過協調選項旨在與希望更新應用程式狀態而不會讓變更被應用程式控制器覆寫的第三方專案一起使用。
此用法的一個範例是 [Open Cluster Management (OCM)](https://github.com/open-cluster-management-io/) 專案使用
[pull-integration](https://github.com/open-cluster-management-io/argocd-pull-integration) 控制器。
在此範例中，中樞叢集應用程式不應由 Argo CD 應用程式控制器進行協調。
相反，OCM pull-integration 控制器將使用從遠端/受管叢集收集的應用程式狀態來填入主要/中樞叢集應用程式狀態。

## 替代使用案例

此略過協調選項還有其他替代使用案例。
重要的是要注意，這是一個實驗性的 alpha 品質功能，
且通常不建議使用以下使用案例。

* 略過應用程式協調時，偵錯更容易。
* 在不刪除應用程式的情況下孤立資源，可能為遷移應用程式提供更安全的方法。
* ApplicationSet 可以產生類似試執行的應用程式，這些應用程式不會自動協調。
* 在災難復原過程中暫停和恢復應用程式協調。
* 透過不允許應用程式立即開始協調，提供另一種替代的核准流程。
