# 功能成熟度

Argo CD 的功能可能會標示特定的[狀態](https://github.com/argoproj/argoproj/blob/main/community/feature-status.md)
以表明其穩定性和成熟度。以下是 Argo CD 中非穩定功能的狀態：

> [!CAUTION]
> **使用 Alpha/Beta 功能的風險**
>
> Alpha 和 Beta 功能不保證向後相容性，並且在未來的版本中可能會發生破壞性變更。
> 強烈建議 Argo 使用者不要在生產環境中依賴這些功能，特別是如果您無法
> 控制 Argo CD 的升級。
>
> 此外，移除 Alpha 功能可能會在 Argo CD 升級後將您的資源修改為不可預測的狀態。
> 您應該確保記錄正在使用的功能，並在升級前查看[版本說明](./upgrading/overview.md)。

## 總覽

| 功能 | 引入版本 | 狀態 |
|---|---|---|
| [AppSet 漸進式同步][2] | v2.6.0 | Alpha |
| [代理擴充功能][3] | v2.7.0 | Beta |
| [跳過應用程式協調][4] | v2.7.0 | Alpha |
| [任何命名空間中的 AppSet][5] | v2.8.0 | Beta |
| [叢集分片：輪詢][6] | v2.8.0 | Alpha |
| [動態叢集分佈][7] | v2.9.0 | Alpha |
| [叢集分片：一致性雜湊][9] | v2.12.0 | Alpha |
| [服務帳號模擬][10] | v2.13.0 | Alpha |
| [來源注入器][11] | v2.14.0 | Alpha |

## 不穩定的設定

### Application CRD

| 功能 | 屬性 | 狀態 |
|---|---|---|
| [跳過應用程式協調][4] | `metadata.annotations[argocd.argoproj.io/skip-reconcile]` | Alpha |

### AppProject CRD

| 功能 | 屬性 | 狀態 |
|---|---|---|
| [服務帳號模擬][10] | `spec.destinationServiceAccounts.*` | Alpha |

### ApplicationSet CRD

| 功能 | 屬性 | 狀態 |
|---|---|---|
| [AppSet 漸進式同步][2] | `spec.strategy.*` | Alpha |
| [AppSet 漸進式同步][2] | `status.applicationStatus.*` | Alpha |

### 設定

| 功能 | 資源 | 屬性 / 變數 | 狀態 |
|---|---|---|---|
| [任何命名空間中的 AppSet][5] | `Deployment/argocd-applicationset-controller` | `ARGOCD_APPLICATIONSET_CONTROLLER_ALLOWED_SCM_PROVIDERS` | Beta |
| [任何命名空間中的 AppSet][5] | `ConfigMap/argocd-cmd-params-cm` | `applicationsetcontroller.allowed.scm.providers` | Beta |
| [任何命名空間中的 AppSet][5] | `ConfigMap/argocd-cmd-params-cm` | `applicationsetcontroller.enable.scm.providers` | Beta |
| [任何命名空間中的 AppSet][5] | `Deployment/argocd-applicationset-controller` | `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_SCM_PROVIDERS` | Beta |
| [任何命名空間中的 AppSet][5] | `Deployment/argocd-applicationset-controller` | `ARGOCD_APPLICATIONSET_CONTROLLER_NAMESPACES` | Beta |
| [任何命名空間中的 AppSet][5] | `ConfigMap/argocd-cmd-params-cm` | `applicationsetcontroller.namespaces` | Beta |
| [AppSet 漸進式同步][2] | `ConfigMap/argocd-cmd-params-cm` | `applicationsetcontroller.enable.progressive.syncs` | Alpha |
| [AppSet 漸進式同步][2] | `Deployment/argocd-applicationset-controller` | `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS` | Alpha |
| [代理擴充功能][3] | `ConfigMap/argocd-cmd-params-cm` | `server.enable.proxy.extension` | Alpha |
| [代理擴充功能][3] | `Deployment/argocd-server` | `ARGOCD_SERVER_ENABLE_PROXY_EXTENSION` | Alpha |
| [代理擴充功能][3] | `ConfigMap/argocd-cm` | `extension.config` | Alpha |
| [動態叢集分佈][7] | `Deployment/argocd-application-controller` | `ARGOCD_ENABLE_DYNAMIC_CLUSTER_DISTRIBUTION` | Alpha |
| [動態叢集分佈][7] | `Deployment/argocd-application-controller` | `ARGOCD_CONTROLLER_HEARTBEAT_TIME` | Alpha |
| [叢集分片：輪詢][6] | `ConfigMap/argocd-cmd-params-cm` | `controller.sharding.algorithm: round-robin` | Alpha |
| [叢集分片：輪詢][6] | `StatefulSet/argocd-application-controller` | `ARGOCD_CONTROLLER_SHARDING_ALGORITHM=round-robin` | Alpha |
| [叢集分片：一致性雜湊][9] | `ConfigMap/argocd-cmd-params-cm` | `controller.sharding.algorithm: consistent-hashing` | Alpha |
| [叢集分片：一致性雜湊][9] | `StatefulSet/argocd-application-controller` | `ARGOCD_CONTROLLER_SHARDING_ALGORITHM=consistent-hashing` | Alpha |
| [服務帳號模擬][10] | `ConfigMap/argocd-cm` | `application.sync.impersonation.enabled` | Alpha |

[2]: applicationset/Progressive-Syncs.md
[3]: ../developer-guide/extensions/proxy-extensions.md
[4]: ../user-guide/skip_reconcile.md
[5]: applicationset/Appset-Any-Namespace.md
[6]: ./high_availability.md#argocd-application-controller
[7]: dynamic-cluster-distribution.md
[8]: ../user-guide/diff-strategies.md#server-side-diff
[9]: ./high_availability.md#argocd-application-controller
[10]: app-sync-using-impersonation.md
[11]: ../user-guide/source-hydrator.md
