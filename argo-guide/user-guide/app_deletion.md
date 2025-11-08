# 應用程式刪除

應用程式可以帶有或不帶有級聯選項進行刪除。**級聯刪除**會同時刪除應用程式及其資源，而不僅僅是刪除應用程式。

## 使用 `argocd` 刪除

若要執行非級聯刪除：

```bash
argocd app delete APPNAME --cascade=false
```

若要執行級聯刪除：

```bash
argocd app delete APPNAME --cascade
```

或

```bash
argocd app delete APPNAME
```

## 使用 `kubectl` 刪除

若要執行非級聯刪除，請確保 finalizer 未設定，然後刪除應用程式：

```bash
kubectl patch app APPNAME  -p '{"metadata": {"finalizers": null}}' --type merge
kubectl delete app APPNAME
```

若要執行級聯刪除，請設定 finalizer，例如使用 `kubectl patch`：

```bash
kubectl patch app APPNAME  -p '{"metadata": {"finalizers": ["resources-finalizer.argocd.argoproj.io"]}}' --type merge
kubectl delete app APPNAME
```

## 關於刪除 finalizer

```yaml
metadata:
  finalizers:
    # 預設行為是前景級聯刪除
    - resources-finalizer.argocd.argoproj.io
    # 或者，您可以使用背景級聯刪除
    # - resources-finalizer.argocd.argoproj.io/background
```

使用此 finalizer 刪除應用程式時，Argo CD 應用程式控制器將執行應用程式資源的級聯刪除。

在實作[應用程式的應用程式模式](../operator-manual/cluster-bootstrapping.md#cascading-deletion)時，新增 finalizer 可啟用級聯刪除。

級聯刪除的預設傳播策略是[前景級聯刪除](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#foreground-deletion)。
當設定 `resources-finalizer.argocd.argoproj.io/background` 時，Argo CD 會執行[背景級聯刪除](https://kubernetes.io/docs/concepts/architecture/garbage-collection/#background-deletion)。

當您使用 `--cascade` 叫用 `argocd app delete` 時，會自動新增 finalizer。
您可以使用 `--propagation-policy <foreground|background>` 設定傳播策略。
