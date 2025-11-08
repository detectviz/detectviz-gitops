# 故障排除工具

本文件說明如何使用 `argocd admin` 子指令來簡化 Argo CD 設定的自訂和解決連線問題。

## 設定

Argo CD 提供多種方式來自訂系統行為，並有許多設定。在由多個使用者使用的生產環境中修改 Argo CD 設定可能很危險。在套用設定之前，您可以使用 `argocd admin` 子指令來確保設定有效且 Argo CD 運作正常。

`argocd admin settings validate` 指令會執行基本的設定驗證，並列印每個設定群組的簡短摘要。

**差異比較自訂**

[差異比較自訂](../user-guide/diffing.md)允許從差異比較過程中排除某些資源欄位。差異比較自訂是在 `argocd-cm` ConfigMap 的 `resource.customizations` 欄位中設定的。

以下 `argocd admin` 指令會列印在指定的 ConfigMap 中從差異比較中排除的欄位資訊。

```bash
argocd admin settings resource-overrides ignore-differences ./deploy.yaml --argocd-cm-path ./argocd-cm.yaml
```

**健康評估**

Argo CD 為多個 Kubernetes 資源提供內建的[健康評估](./health.md)，可以透過撰寫您自己的 [Lua](https://www.lua.org/) 健康檢查來進一步自訂。健康檢查是在 `argocd-cm` ConfigMap 的 `resource.customizations` 欄位中設定的。

以下 `argocd admin` 指令會使用在指定的 ConfigMap 中設定的 Lua 腳本來評估資源健康狀況。

```bash
argocd admin settings resource-overrides health ./deploy.yaml --argocd-cm-path ./argocd-cm.yaml
```

**資源動作**

資源動作允許設定具名的 Lua 腳本，以執行資源修改。

以下 `argocd admin` 指令會使用在指定的 ConfigMap 中設定的 Lua 腳本來執行動作，並列印套用的修改。

```bash
argocd admin settings resource-overrides run-action /tmp/deploy.yaml restart --argocd-cm-path /private/tmp/argocd-cm.yaml
```

以下 `argocd admin` 指令會使用在指定的 ConfigMap 中設定的 Lua 腳本來列出給定資源可用的動作。

```bash
argocd admin settings resource-overrides list-actions /tmp/deploy.yaml --argocd-cm-path /private/tmp/argocd-cm.yaml
```

## 叢集憑證

如果您手動建立了包含叢集憑證的 Secret，並且需要解決連線問題，`argocd admin cluster kubeconfig` 指令會很有用。在這種情況下，建議您執行以下步驟：

1. SSH 進入 [argocd-application-controller] Pod。

```
kubectl exec -n argocd -it \
  $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[0].metadata.name}') bash
```

2. 使用 `argocd admin cluster kubeconfig` 指令從設定的 Secret 匯出 kubeconfig 檔案：

```
argocd admin cluster kubeconfig https://<api-server-url> /tmp/kubeconfig --namespace argocd
```

3. 使用 `kubectl` 取得有關連線問題的更多詳細資訊，修正它們並將變更套用回 secret：

```
export KUBECONFIG=/tmp/kubeconfig
kubectl get pods -v 9
```
