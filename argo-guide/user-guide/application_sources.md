# 工具

## 正式環境

Argo CD 支援多種定義 Kubernetes 資訊清單的方式：

* [Kustomize](kustomize.md) 應用程式
* [Helm](helm.md) charts
* [OCI](oci.md) 映像檔
* 包含 YAML、JSON 或 [Jsonnet](jsonnet.md) 資訊清單的目錄。
* 任何設定為組態管理外掛程式的[自訂組態管理工具](../operator-manual/config-management-plugins.md)

## 開發環境
Argo CD 也支援直接上傳本地資訊清單。由於這與
GitOps 模式背道而馳，因此只應在開發時使用。
需要具有 `override` 權限的使用者才能在本地上傳資訊清單（通常是管理員）。上述所有不同的 Kubernetes 部署工具都受支援。
若要上傳本地應用程式：

```bash
$ argocd app sync APPNAME --local /path/to/dir/
```
