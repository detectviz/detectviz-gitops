# 安裝

Argo CD 有兩種安裝類型：多租戶和核心。

## 多租戶

多租戶安裝是安裝 Argo CD 最常見的方式。此類型的安裝通常用於服務組織中的多個應用程式開發團隊，並由一個平台團隊進行維護。

終端使用者可以透過 API 伺服器使用 Web UI 或 `argocd` CLI 存取 Argo CD。`argocd` CLI 必須使用 `argocd login <server-host>` 指令進行設定（在此處了解更多[資訊](../user-guide/commands/argocd_login.md)）。

提供兩種安裝清單：

### 非高可用性：

不建議用於生產環境。此類型的安裝通常在評估期間用於示範和測試。

* [install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/install.yaml) - 具有叢集管理員存取權限的標準 Argo CD 安裝。如果您計劃使用 Argo CD 在與 Argo CD 執行的同一個叢集中部署應用程式（即 kubernetes.svc.default），請使用此清單集。它仍然能夠使用輸入的憑證部署到外部叢集。

  > 注意：安裝清單中的 ClusterRoleBinding 繫結到 argocd 命名空間中的 ServiceAccount。修改命名空間時要小心，因為變更它可能會導致權限相關的錯誤，除非正確調整 ClusterRoleBinding 以反映新的命名空間。

* [namespace-install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/namespace-install.yaml) - 僅需要命名空間級別權限（不需要叢集角色）的 Argo CD 安裝。如果您不需要 Argo CD 在與 Argo CD 執行的同一個叢集中部署應用程式，並且將完全依賴輸入的叢集憑證，請使用此清單集。使用此組清單的一個範例是，如果您為不同的團隊執行多個 Argo CD 執行個體，其中每個執行個體都將向外部叢集部署應用程式。仍然可以使用輸入的憑證部署到同一個叢集（kubernetes.svc.default）（即 `argocd cluster add <CONTEXT> --in-cluster --namespace <YOUR NAMESPACE>`）。使用包含的預設角色，您將只能在同一個叢集中部署 Argo CD 資源（Applications、ApplicationSets 和 AppProjects），因為它僅支援 GitOps 模式，實際部署是在外部叢集上完成的。您可以透過定義新角色並將它們繫結到 `argocd-application-controller` 服務帳戶來修改此行為。

  > 注意：Argo CD CRD 不包含在 [namespace-install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/namespace-install.yaml) 中，必須單獨安裝。CRD 清單位於 [manifests/crds](https://github.com/argoproj/argo-cd/blob/master/manifests/crds) 目錄中。使用以下指令安裝它們：
  > ```
  > kubectl apply -k https://github.com/argoproj/argo-cd/manifests/crds\?ref\=stable
  > ```

### 高可用性：

建議將高可用性安裝用於生產環境。此套件包含相同的元件，但已針對高可用性和彈性進行了調整。

* [ha/install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/ha/install.yaml) - 與 install.yaml 相同，但支援的元件具有多個副本。

* [ha/namespace-install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/ha/namespace-install.yaml) - 與 namespace-install.yaml 相同，但支援的元件具有多個副本。

## 核心

Argo CD 核心安裝主要用於以無頭模式部署 Argo CD。此類型的安裝最適合獨立使用 Argo CD 且不需要多租戶功能的叢集管理員。此安裝包含較少的元件，且設定更容易。此套件不包含 API 伺服器或 UI，並安裝每個元件的輕量級（非 HA）版本。

安裝清單可在 [core-install.yaml](https://github.com/argoproj/argo-cd/blob/master/manifests/core-install.yaml) 取得。

有關 Argo CD 核心的更多詳細資訊，請參閱[官方文件](./core.md)

## Kustomize

Argo CD 清單也可以使用 Kustomize 進行安裝。建議將清單作為遠端資源包含，並使用 Kustomize 修補程式應用其他自訂。


```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: argocd
resources:
- https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

有關此範例，請參閱用於部署 [Argoproj CI/CD 基礎設施](https://github.com/argoproj/argoproj-deployments#argoproj-deployments) 的 [kustomization.yaml](https://github.com/argoproj/argoproj-deployments/blob/master/argocd/kustomization.yaml)。

#### 在自訂命名空間中安裝 Argo CD
如果您想在預設的 `argocd` 以外的命名空間中安裝 Argo CD，您可以使用 Kustomize 應用一個修補程式，更新 ClusterRoleBinding 以參考 ServiceAccount 的正確命名空間。這可確保在您的自訂命名空間中正確設定必要的權限。

以下是如何設定您的 `kustomization.yaml` 以在自訂命名空間中安裝 Argo CD 的範例：
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: <your-custom-namespace>
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


patches:
  - patch: |-
      - op: replace
        path: /subjects/0/namespace
        value: <your-custom-namespace>
    target:
      kind: ClusterRoleBinding
```

此修補程式可確保 ClusterRoleBinding 正確對應到您自訂命名空間中的 ServiceAccount，從而防止在部署期間發生任何與權限相關的問題。

## Helm

Argo CD 可以使用 [Helm](https://helm.sh/) 進行安裝。Helm 圖表目前由社群維護，可在 [argo-helm/charts/argo-cd](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd) 取得。

## 支援的版本

有關 Argo CD 版本支援政策的詳細資訊，請參閱[發行流程和節奏文件](https://argo-cd.readthedocs.io/en/stable/developer-guide/release-process-and-cadence/)。

## 測試過的版本

下表顯示了與每個 Argo CD 版本一起測試的 Kubernetes 版本。

{!docs/operator-manual/tested-kubernetes-versions.md!}
