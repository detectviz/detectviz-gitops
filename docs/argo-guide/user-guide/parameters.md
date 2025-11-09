# 參數覆寫

Argo CD 提供了一種機制，可以覆寫利用組態管理
工具的 Argo CD 應用程式的參數。這提供了彈性，可以將大部分的應用程式資訊清單定義在 Git 中，同時為
*某些* Kubernetes 資訊清單的部分保留動態決定或在 Git 之外的空間。它也作為一種替代方法，
透過 Argo CD 變更應用程式參數來重新部署應用程式，而不是在 Git 中對資訊清單進行
變更。

> [!TIP]
> 許多人認為這種操作模式是 GitOps 的反模式，因為真相來源
> 變成了 Git 儲存庫和應用程式覆寫的聯集。Argo CD 參數
> 覆寫功能主要是為了方便開發人員而提供的，旨在用於
> 開發/測試環境，而非生產環境。

若要使用參數覆寫，請執行 `argocd app set -p (COMPONENT=)PARAM=VALUE` 指令：

```bash
argocd app set guestbook -p image=example/guestbook:abcd123
argocd app sync guestbook
```

`PARAM` 預期為一個正常的 YAML 路徑

```bash
argocd app set guestbook -p ingress.enabled=true
argocd app set guestbook -p ingress.hosts[0]=guestbook.myclusterurl
```

`argocd app set` [指令](./commands/argocd_app_set.md) 支援更多特定於工具的旗標，例如 `--kustomize-image`、`--jsonnet-ext-var-str` 等。
您也可以直接在應用程式規格的來源欄位中指定覆寫。在對應的工具[文件](./application_sources.md)中閱讀有關支援選項的更多資訊。

## 何時使用覆寫？

以下是參數覆寫有用的情況：

1. 一個團隊維護一個「開發」環境，需要在每次在 master 分支的最新版本中建置後，持續更新其 guestbook 應用程式的最新
版本。為了解決此使用案例，應用程式將公開一個名為 `image` 的參數，其在「開發」
環境中使用的值包含一個佔位符值（例如 `example/guestbook:replaceme`）。佔位符值
將在外部（Git 之外）決定，例如建置系統。然後，作為建置
管線的一部分，`image` 的參數值將持續更新為新建立的映像檔
（例如 `argocd app set guestbook -p image=example/guestbook:abcd123`）。同步操作
將導致應用程式以新映像檔重新部署。

2. Helm 資訊清單的儲存庫已公開可用（例如 https://github.com/helm/charts）。
由於無法對該儲存庫進行提交存取，因此能夠從
公開儲存庫安裝 chart 並使用不同的參數自訂部署，而無需
分叉該儲存庫來進行變更，是很有用的。例如，若要從 Helm chart
儲存庫安裝 Redis 並自訂資料庫密碼，您將執行：

```bash
argocd app create redis --repo https://github.com/helm/charts.git --path stable/redis --dest-server https://kubernetes.default.svc --dest-namespace default -p password=abc123
```

## 在 Git 中儲存覆寫

特定於組態管理工具的覆寫可以在 Git 儲存庫中來源應用程式
目錄中儲存的 `.argocd-source.yaml` 檔案中指定。

`.argocd-source.yaml` 檔案在資訊清單產生期間使用，並覆寫
應用程式來源欄位，例如 `kustomize`、`helm` 等。

範例：

```yaml
kustomize:
  images:
    - quay.io/argocd-labs/argocd-e2e-container:0.2
```

`.argocd-source` 旨在解決以下兩個主要使用案例：

- 提供在 Git 中「覆寫」應用程式參數的統一方式，並為
[argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater) 等專案啟用「寫回」功能。
- 支援由 [applicationset](https://github.com/argoproj/applicationset) 等專案在 Git 儲存庫中「發現」應用程式
（請參閱 [git 檔案產生器](https://github.com/argoproj/argo-cd/blob/master/applicationset/examples/git-generator-files-discovery/git-generator-files.yaml)）

如果您從儲存庫中的單一路徑中取得多個應用程式，您也可以將參數覆寫儲存在應用程式特定的檔案中
。

應用程式特定的檔案必須命名為 `.argocd-source-<appname>.yaml`，
其中 `<appname>` 是覆寫有效的應用程式的名稱。
當與 [apps-in-any-namespace](../operator-manual/app-any-namespace.md)
功能結合使用時，檔名應包含命名空間名稱作為前綴，即
`.argocd-source-<namespace>_<appname>.yaml`。

如果存在非應用程式特定的 `.argocd-source.yaml`，則該檔案中包含的參數
會先合併，然後再合併應用程式特定的
參數，其中也可能包含對非應用程式特定檔案中儲存的參數的覆寫
。
