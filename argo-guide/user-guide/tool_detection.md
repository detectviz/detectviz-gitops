# 工具偵測

用於建置應用程式的工具偵測方式如下：

如果已明確設定特定工具，則會選取該工具來建立您的應用程式資訊清單。

可以在應用程式自訂資源中明確指定工具，如下所示：
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  ...
spec:
  ...
  source:
    ...
    
    # Tool -> plain directory
    directory:
      recurse: true
...
```

您也可以在 Web 使用者介面的應用程式建立精靈中選取工具。預設為「目錄」。如果您想選擇不同的工具，請按下工具名稱下方的下拉式按鈕。


如果未指定，則會隱含地偵測工具，如下所示：

* **Helm** 如果有符合 `Chart.yaml` 的檔案。
* **Kustomize** 如果有 `kustomization.yaml`、`kustomization.yml` 或 `Kustomization`

否則，會假設它是一個純粹的**目錄**應用程式。

## 停用內建工具

可以透過在 `argocd-cm` ConfigMap 中將下列其中一個金鑰設定為 `false` 來選擇性地停用內建組態管理工具：`kustomize.enable`、`helm.enable` 或 `jsonnet.enable`。停用工具後，Argo CD 會假設應用程式目標目錄包含純 Kubernetes YAML 資訊清單。

停用未使用的組態管理工具可以是一個有用的安全性增強功能。漏洞有時僅限於某些組態管理工具。即使沒有漏洞，攻擊者也可能使用特定工具來利用 Argo CD 實例中的設定錯誤。停用未使用的組態管理工具會限制惡意行為者可用的工具。
