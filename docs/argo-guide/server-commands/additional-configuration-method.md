## 其他設定方法

用於設定 `argocd-server`、`argocd-repo-server` 和 `argocd-application-controller` 指令的其他設定方法。


### 摘要

這些指令也可以透過在 `argocd-cmd-params-cm.yaml` 中設定可用選項的各自旗標來進行設定。每個元件都有一個與其關聯的特定前置詞。

```
argocd-server                 --> server
argocd-repo-server            --> reposerver
argocd-application-controller --> controller
```

沒有前置詞的旗標會在多個元件之間共用。`repo.server` 就是這樣一個旗標。
可用的旗標清單可以在 [argocd-cmd-params-cm.yaml](../argocd-cmd-params-cm.yaml) 中找到。


### 範例

若要設定 `argocd-application-controller` 的 `logformat`，請將以下項目新增到設定檔 `argocd-cmd-params-cm.yaml` 中。

```
data:
    controller.log.format: "json"
```
