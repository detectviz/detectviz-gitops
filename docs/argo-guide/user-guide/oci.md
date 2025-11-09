# OCI

## 宣告式

Argo CD 支援使用 OCI (Open Container Initiative) 映像檔作為應用程式來源。
您可以使用 OCI 映像檔透過 UI 或以宣告式的 GitOps 方式安裝應用程式。
以下是一個範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-custom-image
  namespace: argocd
spec:
  project: default
  source:
    path: .
    repoURL: oci://registry-1.docker.io/some-user/my-custom-image
    targetRevision: 1.16.1
  destination:
    server: "https://kubernetes.default.svc"
    namespace: my-namespace
```

另一個使用公開 OCI helm chart 的範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
spec:
  project: default
  source:
    path: .
    repoURL: oci://registry-1.docker.io/bitnamicharts/nginx 
    targetRevision: 15.9.0
    helm:
      valuesObject:
        some-value: foo
  destination:
    name: "in-cluster"
    namespace: nginx
```

開始使用 OCI 映像檔的關鍵是應用程式規格中的以下元件：

* `repoURL`：使用 `oci://` 協定指定 OCI 映像檔儲存庫 URL，後面接著註冊中心和映像檔名稱。
* `targetRevision`：使用此欄位指定所需的映像檔標籤或摘要。
* `path`：使用此欄位從展開的映像檔中選取相對路徑。如果您不想選取子路徑，請使用 `.`。
在 OCI Helm chart 的情況下（`mediaType` 設定為 `application/vnd.cncf.helm.chart.content.v1.tar+gzip` 的 OCI 成品），
路徑應永遠設定為 `.`。

## 使用指南

首先，您需要有一個符合 OCI 規範的儲存庫。例如，DockerHub、ECR、GHCR 和 GCR 都符合
要求。

其次，Argo CD 預期 OCI 映像檔包含單一層。它也預期 OCI 映像檔具有
Argo CD 儲存庫伺服器接受的媒體類型。預設情況下，Argo CD 接受映像檔層的以下其中一種媒體類型
：

* `application/vnd.oci.image.layer.v1.tar+gzip`
* `application/vnd.cncf.helm.chart.content.v1.tar+gzip`

可以透過在 repo-server 部署中設定 `ARGOCD_REPO_SERVER_OCI_LAYER_MEDIA_TYPES` 環境變數
來自訂媒體類型。

若要建立與 Argo CD 相容的 OCI 成品，有許多工具可供選擇。在此範例中，我們將
使用 [ORAS](https://oras.land/)。導覽至您的資訊清單所在的目錄並執行 `oras push`。

```shell
oras push <registry-url>/guestbook:latest .
```

ORAS 會負責將目錄打包成單一層，並將 `mediaType` 設定為
`application/vnd.oci.image.layer.v1.tar+gzip`。

您也可以使用壓縮封存檔來打包您的 OCI 映像檔。

```shell
# 建立包含您資訊清單的目錄的 tarball。如果您不在目前目錄中，請確保
# 您正在設定目錄的正確父目錄（這就是 `-C` 旗標的作用）。
tar -czvf archive.tar.gz -C manifests .
```

然後，您可以使用 ORAS 將封存檔推送到您的 OCI 註冊中心：

```shell
# 在 tarball 的情況下，您目前需要手動設定媒體類型。
oras push <registry-url>/guestbook:latest archive.tar.gz:application/vnd.oci.image.layer.v1.tar+gzip
```

## OCI 中繼資料註釋

Argo CD 可以顯示標準的 OCI 中繼資料註釋，直接在 Argo CD UI 中提供有關您的 OCI
映像檔的額外內容和資訊。

### 支援的註釋

Argo CD 會辨識並顯示以下標準 OCI 註釋：

* `org.opencontainers.image.title`
* `org.opencontainers.image.description`
* `org.opencontainers.image.version`
* `org.opencontainers.image.revision`
* `org.opencontainers.image.url`
* `org.opencontainers.image.source`
* `org.opencontainers.image.authors`
* `org.opencontainers.image.created`

使用先前使用 ORAS 的範例，我們可以設定 Argo CD 可以使用的註釋：

```shell
oras push -a "org.opencontainers.image.authors=some author" \
          -a "org.opencontainers.image.url=http://some-url" \
          -a "org.opencontainers.image.version=some-version" \
          -a "org.opencontainers.image.source=http://some-source" \
          -a "org.opencontainers.image.description=some description" \
          <registry-url>/guestbook:latest .
```
