# 應用程式修剪與資源刪除

由 ApplicationSet 控制器（從 ApplicationSet）建立的所有 `Application` 資源將包含：

- 一個指向*父* `ApplicationSet` 資源的 `.metadata.ownerReferences` 引用
- 如果 `.syncPolicy.preserveResourcesOnDeletion` 設定為 false，則在應用程式的 `.metadata.finalizers` 中會有一個 Argo CD `resources-finalizer.argocd.argoproj.io` finalizer。

最終結果是，當刪除 ApplicationSet 時，會發生以下情況（大致順序）：

- `ApplicationSet` 資源本身被刪除
- 從此 `ApplicationSet` 建立的任何 `Application` 資源（由所有者引用標識）將被刪除
- 在受控叢集上部署的任何資源（`Deployments`、`Services`、`ConfigMaps` 等），只要是從該 `Application` 資源（由 Argo CD）建立的，都將被刪除。
    - Argo CD 負責透過[刪除 finalizer](../../../user-guide/app_deletion/#about-the-deletion-finalizer) 處理此刪除。
    - 若要保留已部署的資源，請在 ApplicationSet 中將 `.syncPolicy.preserveResourcesOnDeletion` 設定為 true。

因此，`ApplicationSet`、`Application` 和 `Application` 資源的生命週期是相同的。

> [!NOTE]
> 有關如何防止 ApplicationSet 控制器刪除或修改應用程式資源的更多資訊，另請參閱[控制資源修改](Controlling-Resource-Modification.md) 頁面。

仍然可以刪除 `ApplicationSet` 資源，同時使用非級聯刪除來防止 `Application`（及其已部署的資源）也被刪除：
```
kubectl delete ApplicationSet (NAME) --cascade=orphan
```

> [!WARNING]
> 即使使用非級聯刪除，`resources-finalizer.argocd.argoproj.io` 仍會在 `Application` 上指定。因此，當刪除 `Application` 時，其所有已部署的資源也將被刪除。（應用程式及其*子*物件的生命週期仍然相同。）
>
> 若要防止刪除應用程式的資源，例如服務、部署等，請在 ApplicationSet 中將 `.syncPolicy.preserveResourcesOnDeletion` 設定為 true。此 syncPolicy 參數可防止將 finalizer 新增到應用程式中。
