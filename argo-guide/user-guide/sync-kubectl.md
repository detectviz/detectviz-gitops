# 使用 Kubectl 同步應用程式

您可以使用「kubectl」來要求 Argo CD 同步應用程式，就像您可以使用 CLI 或 UI 一樣。許多設定，例如「force」、「prune」、「apply」，甚至同步特定資源清單，都同樣受到支援。這是透過套用或修補 Argo CD 應用程式，並使用定義「operation」的文件來完成的。

此「operation」定義了同步應如何執行，以及應對哪些資源執行這些同步。

可以將許多設定選項新增到「operation」中。接下來，將解釋其中一些。有關更多詳細資訊，您可以查看 CRD [applications.argoproj.io](https://github.com/argoproj/argo-cd/blob/master/manifests/crds/application-crd.yaml)。其中一些是必要的，而其他則是可選的。

若要要求 Argo CD 同步給定應用程式的所有資源，我們可以執行：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: <namespace>
spec:
  ...
operation:
  initiatedBy:
    username: <username>
  sync:
    syncStrategy:
      hook: {}
```

```bash
$ kubectl apply -f <apply-file>
```

最重要的部分是「operation」欄位中的「sync」定義。您可以傳遞可選資訊，例如「info」或「initiatedBy」。「info」允許您以清單的形式新增有關操作的資訊。「initiatedBy」包含有關誰發起操作請求的資訊。

或者，如果您願意，也可以修補：

```yaml
operation:
  initiatedBy:
    username: <username>
  sync:
    syncStrategy:
      hook: {}
```

```bash
$ kubectl patch -n <namespace> app <app-name> --patch-file <patch-file> --type merge
```

請注意，修補程式，特別是使用合併策略的修補程式，可能無法如您預期般運作，特別是如果您變更同步策略或選項。
在這些情況下，「kubectl apply」會提供更好的結果。

無論是使用「kubectl patch」還是「kubectl apply」，同步的狀態都會在應用程式物件的「operationState」欄位中報告。

```bash
$ kubectl get -n <namespace> app <app-name> -o yaml
...
status:
  operationState:
    finishedAt: "2023-08-03T11:16:17Z"
    message: successfully synced (all tasks run)
    phase: Succeeded
```

# Apply 和 Hook 同步策略

有兩種同步策略：「hook」（預設值）和「apply」。

「apply」同步策略會告訴 Argo CD 執行「kubectl apply」，而「hook」同步策略則會通知 Argo CD 提交操作中參照的任何資源。這樣，這些資源的同步將會考慮到資源已標註的任何 hook。

```yaml
operation:
  sync:
    syncStrategy:
      apply: {}
```

```yaml
operation:
  sync:
    syncStrategy:
      hook: {}
```

兩種策略都支援「force」。但是，您需要注意，當修補程式在重試 5 次後遇到衝突時，強制操作會刪除該資源。

```yaml
operation:
  sync:
    syncStrategy:
      apply:
        force: true
```

```yaml
operation:
  sync:
    syncStrategy:
      hook:
        force: true
```

# Prune (刪除)

如果您想在套用前刪除您的資源，您可以指示 Argo CD 這麼做：

```yaml
operation:
  sync:
    prune: true
```

# 資源清單

總是存在傳遞資源清單的可能性。此清單可以是應用程式管理的所有資源，也可以只是子集，例如由於某些原因而保持未同步的資源。

參照資源時，只有「kind」和「name」是必要欄位，但也可以定義「groups」和「namespace」欄位：

```yaml
operation:
  sync:
    resources:
      - kind: Namespace
        name: namespace-name
      - kind: ServiceAccount
        name: service-account-name
        namespace: namespace-name
      - group: networking.k8s.io
        kind: NetworkPolicy
        name: network-policy-name
        namespace: namespace-name
```

# 同步選項

在操作中，您也可以傳遞同步選項。每個選項都以「name=value」配對的形式傳遞。例如：

```yaml
operations:
  sync:
    syncOptions:
      - Validate=false
      - Prune=false
```

有關同步選項的更多資訊，請參閱 [sync-options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
