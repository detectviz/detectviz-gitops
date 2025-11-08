# 建置環境

[自訂工具](../operator-manual/config-management-plugins.md)、[Helm](helm.md)、[Jsonnet](jsonnet.md) 和 [Kustomize](kustomize.md) 支援以下建置環境變數：

| 變數                            | 說明                                                             |
| ----------------------------------- | ----------------------------------------------------------------------- |
| `ARGOCD_APP_NAME`                   | 應用程式的名稱。                                            |
| `ARGOCD_APP_NAMESPACE`              | 應用程式的目標命名空間。                           |
| `ARGOCD_APP_PROJECT_NAME`           | 應用程式所屬專案的名稱。                     |
| `ARGOCD_APP_REVISION`               | 已解析的修訂版本，例如 `f913b6cbf58aa5ae5ca1f8a2b149477aebcbd9d8`。 |
| `ARGOCD_APP_REVISION_SHORT`         | 已解析的簡短修訂版本，例如 `f913b6c`。                            |
| `ARGOCD_APP_REVISION_SHORT_8`       | 長度為 8 的已解析簡短修訂版本，例如 `f913b6cb`。             |
| `ARGOCD_APP_SOURCE_PATH`            | 來源儲存庫中應用程式的路徑。                             |
| `ARGOCD_APP_SOURCE_REPO_URL`        | 來源儲存庫的 URL。                                                    |
| `ARGOCD_APP_SOURCE_TARGET_REVISION` | 來自規格的目標修訂版本，例如 `master`。                       |
| `KUBE_VERSION`                      | 不含尾隨中繼資料的 Kubernetes 語意版本。           |
| `KUBE_API_VERSIONS`                 | Kubernetes API 的版本。                                      |

如果您不希望變數被內插，可以透過 `$$` 來逸出 `$`。

```
command:
  - sh
  - -c
  - |
    echo $$FOO
```
