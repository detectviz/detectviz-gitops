# 同步選項

Argo CD 允許使用者自訂其在目標叢集中同步期望狀態的某些方面。某些同步選項可以定義為特定資源中的註解。大多數同步選項是在應用程式資源的 `spec.syncPolicy.syncOptions` 屬性中設定。使用 `argocd.argoproj.io/sync-options` 註解設定的多個同步選項可以在註解值中用 `,` 串連；空白字元將被修剪。

您可以在下面找到每個可用同步選項的詳細資訊：

## 不清理資源

您可能希望防止某個物件被清理：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

同步狀態面板會顯示已略過清理，以及原因：

![同步選項無清理](../assets/sync-option-no-prune-sync-status.png)

如果 Argo CD 預期要清理某個資源，則應用程式將處於不同步狀態。您可能希望將此與[比較選項](compare-options.md)一起使用。

## 帶有確認的資源清理

諸如命名空間之類的資源至關重要，不應未經確認就進行清理。您可以設定 `Prune=confirm`
同步選項，以在清理前要求手動確認。

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=confirm
```

若要確認清理，您可以使用 Argo CD UI、CLI 或手動將 `argocd.argoproj.io/deletion-approved: <ISO 格式的時間戳記>`
註解套用至應用程式。

## 停用 Kubectl 驗證

對於某類物件，需要使用 `--validate=false` 旗標來執行 `kubectl apply`。例如，使用 `RawExtension` 的 Kubernetes 類型，例如 [ServiceCatalog](https://github.com/kubernetes-incubator/service-catalog/blob/master/pkg/apis/servicecatalog/v1beta1/types.go#L497)。您可以使用此註解來執行此操作：

```yaml
metadata:
  annotations:
    argocd.argocd.io/sync-options: Validate=false
```

如果您想全域排除某類物件，請考慮在[系統層級組態](../user-guide/diffing.md#system-level-configuration)中設定 `resource.customizations`。

## 對於新的自訂資源類型略過試運轉

同步一個叢集尚不知道的自訂資源時，通常有兩種選擇：

1. CRD 資訊清單是同一次同步的一部分。然後 Argo CD 將自動略過試運轉，CRD 將被套用，並且可以建立資源。
2. 在某些情況下，CRD 不是同步的一部分，但可以透過另一種方式建立，例如由叢集中的控制器建立。一個例子是 [gatekeeper](https://github.com/open-policy-agent/gatekeeper)，它會回應使用者定義的 `ConstraintTemplates` 來建立 CRD。Argo CD 在同步中找不到 CRD，並會失敗，並出現錯誤 `the server could not find the requested resource`。

若要對遺失的資源類型略過試運轉，請使用以下註解：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
```

如果 CRD 已存在於叢集中，則仍會執行試運轉。

也可以對所有應用程式資源遺失的資源略過試運轉。您可以設定 `SkipDryRunOnMissingResource=true`
同步選項來對遺失的資源略過試運轉

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - SkipDryRunOnMissingResource=true
```

## 不刪除資源

對於某些資源，您可能希望即使在刪除應用程式後也保留它們，例如對於永久磁碟區宣告。
在這種情況下，您可以使用以下註解來阻止這些資源在應用程式刪除期間被清理：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Delete=false
```

## 帶有確認的資源刪除

諸如命名空間之類的資源至關重要，不應未經確認就進行刪除。您可以設定 `Delete=confirm`
同步選項，以在刪除前要求手動確認。

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Delete=confirm
```

若要確認刪除，您可以使用 Argo CD UI、CLI 或手動將 `argocd.argoproj.io/deletion-approved: <ISO 格式的時間戳記>`
註解套用至應用程式。

## 選擇性同步

目前，使用自動同步進行同步時，Argo CD 會套用應用程式中的每個物件。
對於包含數千個物件的應用程式，這需要相當長的時間，並給 api 伺服器帶來不必要的壓力。
開啟選擇性同步選項將只同步未同步的資源。

您可以透過以下方式新增此選項：

1) 在資訊清單中新增 `ApplyOutOfSyncOnly=true`

範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - ApplyOutOfSyncOnly=true
```

2) 透過 argocd cli 設定同步選項

範例：

```bash
$ argocd app set guestbook --sync-option ApplyOutOfSyncOnly=true
```

## 資源清理刪除傳播策略

預設情況下，多餘的資源會使用前景刪除策略進行清理。可以使用 `PrunePropagationPolicy` 同步選項來控制傳播策略。支援的策略有 background、foreground 和 orphan。
有關這些策略的更多資訊可以在[這裡](https://kubernetes.io/docs/concepts/workloads/controllers/garbage-collection/#controlling-how-the-garbage-collector-deletes-dependents)找到。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - PrunePropagationPolicy=foreground
```

## 最後清理

此功能允許將資源清理作為同步操作的最後一個隱含階段，
在部署其他資源並變得健康之後，以及在所有其他階段成功完成之後。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - PruneLast=true
```

這也可以在個別資源層級進行設定。
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: PruneLast=true
```

## 替換資源而非套用變更

預設情況下，Argo CD 會執行 `kubectl apply` 操作來套用儲存在 Git 中的組態。在某些情況下，`kubectl apply` 並不適用。例如，資源規格可能太大，無法放入 `kubectl apply` 新增的 `kubectl.kubernetes.io/last-applied-configuration` 註解中。在這種情況下，您可以使用 `Replace=true` 同步選項：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - Replace=true
```

如果設定了 `Replace=true` 同步選項，Argo CD 將使用 `kubectl replace` 或 `kubectl create` 指令來套用變更。

> [!WARNING]
> 在同步過程中，資源將使用「kubectl replace/create」指令進行同步。
> 此同步選項具有潛在的破壞性，可能會導致資源必須重新建立，這可能會導致您的應用程式中斷。

這也可以在個別資源層級進行設定。
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Replace=true
```

## 強制同步

對於某些資源，您可能希望刪除並重新建立，例如每次同步時都應執行的作業資源。

> [!WARNING]
> 在同步過程中，資源將使用「kubectl delete/create」指令進行同步。
> 此同步選項具有破壞性動作，可能會導致您的應用程式中斷。

在這種情況下，您可以在目標資源註解中使用 `Force=true` 同步選項：
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Force=true,Replace=true
```

## 伺服器端套用

此選項啟用 Kubernetes
[伺服器端套用](https://kubernetes.io/docs/reference/using-api/server-side-apply/)。

預設情況下，Argo CD 會執行 `kubectl apply` 操作來套用儲存在 Git 中的組態。
這是一個用戶端操作，依賴 `kubectl.kubernetes.io/last-applied-configuration`
註解來儲存先前的資源狀態。

然而，在某些情況下，您會希望使用 `kubectl apply --server-side` 而非 `kubectl apply`：

- 資源太大，無法放入 262144 位元組的註解大小限制。在這種情況下，
  可以使用伺服器端套用來避免此問題，因為在這種情況下不使用註解。
- 修補叢集上現有的資源，這些資源並非由 Argo CD 完全管理。
- 使用更具宣告性的方法，追蹤使用者的欄位管理，而非使用者上次套用的狀態。

如果設定了 `ServerSideApply=true` 同步選項，Argo CD 將使用 `kubectl apply --server-side`
指令來套用變更。

可以在應用程式層級啟用它，如下例所示：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - ServerSideApply=true
```

若要僅為個別資源啟用 ServerSideApply，可以使用 sync-option 註解：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: ServerSideApply=true
```

如果您想在應用程式層級啟用 ServerSideApply 時，為特定資源停用它，
請在其中新增以下 sync-option 註解：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: ServerSideApply=false
```


ServerSideApply 也可以透過提供部分 yaml 來修補現有資源。
例如，如果需要更新給定 Deployment 中的副本數，
可以將以下 yaml 提供給 Argo CD：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  replicas: 3
```

請注意，根據 Deployment 結構描述規範，這不是一個有效的資訊清單。在這種情況下，
*必須*提供一個額外的同步選項來略過結構描述驗證。以下範例
顯示如何設定應用程式以啟用兩個必要的同步選項：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - ServerSideApply=true
    - Validate=false
```

在這種情況下，Argo CD 將使用 `kubectl apply --server-side --validate=false` 指令
來套用變更。

注意：[`Replace=true`](#replace-resource-instead-of-applying-changes) 的優先順序高於 `ServerSideApply=true`。

### 用戶端套用遷移

Argo CD 支援用戶端套用遷移，透過將資源的受管理欄位從一個管理者移至 Argo CD 的管理者，協助從用戶端套用轉換為伺服器端套用。當您需要將使用 kubectl 用戶端套用建立的現有資源遷移至使用 Argo CD 的伺服器端套用時，此功能特別有用。

預設情況下，用戶端套用遷移已啟用。您可以使用同步選項停用它：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - DisableClientSideApplyMigration=true
```

您可以使用註解為用戶端套用遷移指定自訂欄位管理者：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/client-side-apply-migration-manager: "my-custom-manager"
```

當您有其他操作員管理不再使用的資源，並希望 Argo CD 擁有該操作員的所有欄位時，這非常有用。

### 運作方式

當用戶端套用遷移啟用時：
1. Argo CD 將使用指定的欄位管理者（如果未指定，則為預設值）執行遷移
2. 在伺服器端套用同步操作期間，它將：
   - 使用指定的欄位管理者執行用戶端套用
   - 將「last-applied-configuration」註解移至由指定的管理者管理
   - 執行伺服器端套用，這將自動遷移擁有「last-applied-configuration」註解的管理者下的所有欄位。

此功能基於 Kubernetes 的[用戶端套用遷移 KEP](https://github.com/alexzielenski/enhancements/blob/03df8820b9feca6d2cab78e303c99b2c9c0c4c5c/keps/sig-cli/3517-kubectl-client-side-apply-migration/README.md)，它提供了從用戶端到伺服器端套用的自動遷移。

## 如果找到共用資源，則同步失敗

預設情況下，Argo CD 將套用在應用程式中設定的 git 路徑中找到的所有資訊清單，無論 yamls 中定義的資源是否已由另一個應用程式套用。如果設定了 `FailOnSharedResource` 同步選項，當 Argo CD 在目前應用程式中找到已由另一個應用程式在叢集中套用的資源時，同步將會失敗。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    syncOptions:
    - FailOnSharedResource=true
```

## 尊重忽略差異設定

此同步選項用於讓 Argo CD 在同步階段也考慮 `spec.ignoreDifferences` 屬性中的設定。預設情況下，Argo CD 僅使用 `ignoreDifferences` 設定來計算即時狀態和期望狀態之間的差異，以定義應用程式是否同步。然而，在同步階段，期望狀態會按原樣套用。修補程式是使用即時狀態、期望狀態和 `last-applied-configuration` 註解之間的 3 向合併來計算的。這有時會導致不希望的結果。可以透過設定 `RespectIgnoreDifferences=true` 同步選項來變更此行為，如下例所示：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:

  ignoreDifferences:
  - group: "apps"
    kind: "Deployment"
    jsonPointers:
    - /spec/replicas

  syncPolicy:
    syncOptions:
    - RespectIgnoreDifferences=true
```

上述範例顯示如何設定 Argo CD 應用程式，以便在同步階段忽略期望狀態（git）中的 `spec.replicas` 欄位。這是透過在將期望狀態套用至叢集之前計算並預先修補它來實現的。請注意，`RespectIgnoreDifferences` 同步選項僅在資源已在叢集中建立時才有效。如果正在建立應用程式且不存在即時狀態，則期望狀態會按原樣套用。

## 建立命名空間

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: some-namespace
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
```

上述範例顯示如何設定 Argo CD 應用程式，以便如果 `spec.destination.namespace` 中指定的命名空間不存在，它將建立該命名空間。如果未在應用程式資訊清單中宣告或透過 CLI 傳遞 `--sync-option CreateNamespace=true`，如果命名空間不存在，應用程式將同步失敗。

請注意，要建立的命名空間必須在應用程式資源的 `spec.destination.namespace` 欄位中告知。應用程式子資訊清單中的 `metadata.namespace` 欄位必須與此值相符，或者可以省略，以便在正確的目標中建立資源。

### 命名空間元資料

我們也可以透過 `managedNamespaceMetadata` 將標籤和註解新增到命名空間。如果我們擴充上述範例，
我們可能會執行如下操作：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  namespace: test
spec:
  syncPolicy:
    managedNamespaceMetadata:
      labels: # 要在應用程式命名空間上設定的標籤
        any: label
        you: like
      annotations: # 要在應用程式命名空間上設定的註解
        the: same
        applies: for
        annotations: on-the-namespace
    syncOptions:
    - CreateNamespace=true
```

為了讓 Argo CD 管理命名空間上的標籤和註解，需要將 `CreateNamespace=true` 設定為同步選項，
否則不會發生任何事情。如果命名空間不存在，或者它已存在但尚未在其上設定標籤和/或註解，
那麼您就可以開始了。使用 `managedNamespaceMetadata` 也會在命名空間上設定資源追蹤標籤（或註解），
因此您可以輕鬆追蹤由 Argo CD 管理的命名空間。

如果您沒有任何自訂註解或標籤，但仍希望在命名空間上設定資源追蹤，
可以透過將 `managedNamespaceMetadata` 設定為空的 `labels` 和/或 `annotations` 對應來完成，
如下例所示：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  namespace: test
spec:
  syncPolicy:
    managedNamespaceMetadata:
      labels: # 要在應用程式命名空間上設定的標籤
      annotations: # 要在應用程式命名空間上設定的註解
    syncOptions:
    - CreateNamespace=true
```

如果 Argo CD 正在「採用」一個已在其上設定元資料的現有命名空間，您應該先
[將資源升級為伺服器端套用](https://kubernetes.io/docs/reference/using-api/server-side-apply/#upgrading-from-client-side-apply-to-server-side-apply)
再啟用 `managedNamespaceMetadata`。Argo CD 依賴 `kubectl`，它不支援使用伺服器端套用管理
用戶端套用的資源。如果您不將資源升級為伺服器端套用，Argo CD
可能會移除現有的標籤/註解，這可能是也可能不是期望的行為。

另一件要記住的事情是，如果您在 Argo CD 應用程式中有相同命名空間的 k8s 資訊清單，
那麼它將具有優先權並*覆寫 `managedNamespaceMetadata` 中設定的任何值*。換句話說，如果
您有一個設定 `managedNamespaceMetadata` 的應用程式

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  syncPolicy:
    managedNamespaceMetadata:
      annotations:
        abc: 123
    syncOptions:
      - CreateNamespace=true
```

但您也有一個名稱相符的 k8s 資訊清單

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: foobar
  annotations:
    foo: bar
    something: completely-different
```

產生的命名空間的註解將設定為

```yaml
  annotations:
    foo: bar
    something: completely-different
```
