# 目錄

目錄類型的應用程式會從 `.yml`、`.yaml` 和 `.json` 檔案載入純資訊清單檔案。目錄類型的
應用程式可以從 UI、CLI 或以宣告方式建立。這是宣告式語法：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
spec:
  destination:
    namespace: default
    server: https://kubernetes.default.svc
  project: default
  source:
    path: guestbook
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
```

除了新增額外的組態選項外，不需要明確地新增 `spec.source.directory` 欄位。
Argo CD 會自動偵測到來源儲存庫/路徑包含純資訊清單檔案。

## 啟用遞迴資源偵測

預設情況下，目錄應用程式只會包含來自已設定儲存庫/路徑根目錄的檔案。

若要啟用遞迴資源偵測，請設定 `recurse` 選項。

```bash
argocd app set guestbook --directory-recurse
```

若要以宣告方式執行相同的操作，請使用此語法：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    directory:
      recurse: true
```

> [!WARNING]
> 目錄類型的應用程式僅適用於純資訊清單檔案。如果 Argo CD 在設定 `directory:` 時遇到 Kustomize、Helm 或 Jsonnet 檔案，它將無法呈現資訊清單。

## 包含/排除檔案

### 僅包含特定檔案

若要在目錄應用程式中僅包含特定檔案/目錄，請設定 `include` 選項。此值為 glob
模式。

例如，如果您只想包含 `.yaml` 檔案，您可以使用此模式：

```shell
argocd app set guestbook --directory-include "*.yaml"
```

> [!NOTE]
> 務必將 `*.yaml` 加上引號，這樣 shell 就不會在將模式傳送給 Argo CD 之前展開它。

也可以包含多個模式。將模式用 `{}` 包起來，並用逗號分隔。若要包含
`.yml` 和 `.yaml` 檔案，請使用此模式：

```shell
argocd app set guestbook --directory-include "{*.yml,*.yaml}"
```

若要僅包含特定目錄，請使用如下模式：

```shell
argocd app set guestbook --directory-include "some-directory/*"
```

若要以宣告方式達成相同目的，請使用此語法：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    directory:
      include: 'some-directory/*'
```

### 排除特定檔案

可以從目錄應用程式中排除符合模式的檔案。例如，在一個包含
一些資訊清單以及一個非資訊清單 YAML 檔案的儲存庫中，您可以像這樣排除組態檔：

```shell
argocd app set guestbook --directory-exclude "config.yaml"
```

可以排除多個模式。例如，一個組態檔和一個不相關的目錄：

```shell
argocd app set guestbook --directory-exclude "{config.yaml,env-use2/*}"
```

如果同時指定了 `include` 和 `exclude`，則應用程式將包含所有符合 `include`
模式且不符合 `exclude` 模式的檔案。例如，考慮此來源儲存庫：

```
config.json
deployment.yaml
env-use2/
  configmap.yaml
env-usw2/
  configmap.yaml
```

若要排除 `config.json` 和 `env-usw2` 目錄，您可以使用此模式組合：

```shell
argocd app set guestbook --directory-include "*.yaml" --directory-exclude "{config.json,env-usw2/*}"
```

這是宣告式語法：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    directory:
      exclude: '{config.json,env-usw2/*}'
      include: '*.yaml'
```

### 略過檔案呈現

在某些情況下，儲存庫可能包含類似 Kubernetes 資訊清單的 YAML 檔案，因為它們包含 `apiVersion`、`kind` 和 `metadata` 等欄位，但並非旨在作為實際的 Kubernetes 資源來呈現或套用。例如 Helm `values.yaml` 檔案或 CI/CD 管線使用的組態片段。

為了防止 Argo CD 嘗試將這些檔案剖析為資訊清單（這可能會導致錯誤），您可以使用特殊的註解指令明確地將它們標記為略過：

```yaml
# +argocd:skip-file-rendering
```

當此註解出現在檔案中的任何位置時，Argo CD 將在資訊清單處理期間忽略該檔案。這允許安全地共存非實際資訊清單的 Kubernetes 樣式檔案。

#### 範例

```yaml
# +argocd:skip-file-rendering
apiVersion: v1
kind: ConfigMap
metadata:
  name: example
data:
  not-actually: a-manifest
```
