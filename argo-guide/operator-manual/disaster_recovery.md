# 災難復原

您可以使用 `argocd admin` 來匯出和匯入所有 Argo CD 資料。

請確保您的 `~/.kube/config` 指向您的 Argo CD 叢集。

找出您正在執行的 Argo CD 版本：

```bash
argocd version | grep server
# ...
export VERSION=v1.0.1
```

匯出至備份檔案：

```bash
docker run -v ~/.kube:/home/argocd/.kube --rm quay.io/argoproj/argocd:$VERSION argocd admin export > backup.yaml
```

從備份檔案匯入：

```bash
docker run -i -v ~/.kube:/home/argocd/.kube --rm quay.io/argoproj/argocd:$VERSION argocd admin import - < backup.yaml
```

> [!NOTE]
> 如果您在不同於預設的命名空間上執行 Argo CD，請記得傳遞 namespace 參數 (-n <namespace>)。如果您在錯誤的命名空間中執行 'argocd admin export'，它不會失敗。
