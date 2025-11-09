
# 組態管理外掛程式 (Config Management Plugins)

Argo CD 的「原生」組態管理工具是 Helm、Jsonnet 和 Kustomize。如果您想使用不同的組態管理工具，或者 Argo CD 的原生工具支援不包含您需要的功能，您可能需要轉向使用組態管理外掛程式 (CMP)。

Argo CD 的「repo server」元件負責根據來自 Helm、OCI 或 Git 儲存庫的某些來源檔案來建置 Kubernetes 清單。當正確設定組態管理外掛程式時，repo server 可以將建置清單的任務委派給外掛程式。

以下各節將說明如何建立、安裝和使用外掛程式。請查看 [範例外掛程式](https://github.com/argoproj/argo-cd/tree/master/examples/plugins) 以獲得額外指導。

> [!WARNING]
> 外掛程式在 Argo CD 系統中被授予一定程度的信任，因此安全地實作外掛程式非常重要。Argo CD 管理員只應安裝來自可信來源的外掛程式，並且他們應該審核外掛程式以權衡其特定的風險和收益。

## 安裝組態管理外掛程式

### Sidecar 外掛程式

操作員可以透過 repo-server 的 sidecar 來設定外掛程式工具。設定新外掛程式需要進行以下更改：

#### 撰寫外掛程式組態檔

外掛程式將透過位於外掛程式容器內的 `ConfigManagementPlugin` 清單進行設定。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  # 在給定的 Argo CD 執行個體中，外掛程式的名稱必須是唯一的。
  name: my-plugin
spec:
  # 您的外掛程式版本。選用。如果指定，Application 的 spec.source.plugin.name 欄位
  # 必須是 <plugin name>-<plugin version>。
  version: v1.0
  # init 指令在每次清單產生開始時在應用程式來源目錄中執行。init
  # 指令可以輸出任何內容。非零狀態碼將導致清單產生失敗。
  init:
    # Init 總是在 generate 之前立即發生，但其輸出不被視為清單。
    # 這是一個很好的地方，例如，用來下載圖表相依性。
    command: [sh]
    args: [-c, 'echo "正在初始化..."']
  # generate 指令在每次產生清單時在應用程式來源目錄中執行。標準輸出
  # 必須僅為 YAML 或 JSON 格式的有效 Kubernetes 物件。非零結束碼將導致清單產生失敗。
  # 若要從指令中寫入日誌訊息，請將它們寫入 stderr，它將始終被顯示。
  # 錯誤輸出將被發送到 UI，因此請避免列印敏感資訊（例如密碼）。
  generate:
    command: [sh, -c]
    args:
      - |
        echo "{\"kind\": \"ConfigMap\", \"apiVersion\": \"v1\", \"metadata\": { \"name\": \"$ARGOCD_APP_NAME\", \"namespace\": \"$ARGOCD_APP_NAMESPACE\", \"annotations\": {\"Foo\": \"$ARGOCD_ENV_FOO\", \"KubeVersion\": \"$KUBE_VERSION\", \"KubeApiVersion\": \"$KUBE_API_VERSIONS\",\"Bar\": \"baz\"}}}"
  # discovery 設定應用於儲存庫。如果每個設定的發現工具都匹配，則該外掛程式可
  # 用於為使用該儲存庫的應用程式產生清單。如果省略 discovery 設定，則外掛程式
  # 將不匹配任何應用程式，但仍可透過在應用程式規格中指定外掛程式名稱來明確叫用。
  # fileName、find.glob 或 find.command 中只應指定一個。如果指定了多個，則只
  # 評估第一個（按該順序）。
  discover:
    # fileName 是一個 glob 模式 (https://pkg.go.dev/path/filepath#Glob)，應用於應用程式的來源
    # 目錄。如果匹配，此外掛程式可用於該應用程式。
    fileName: "./subdir/s*.yaml"
    find:
      # 這與 fileName 的作用相同，但它支援雙星號（巢狀目錄）glob 模式。
      glob: "**/Chart.yaml"
      # find 指令在儲存庫的根目錄中執行。要匹配，它必須以狀態碼 0 結束 _並且_
      # 向標準輸出產生非空輸出。
      command: [sh, -c, find . -name env.yaml]
  # parameters 設定描述了 UI 應該為應用程式顯示哪些參數。使用者
  # 需自行在應用程式清單中設定參數 (在 spec.source.plugin.parameters 中)。此宣告 _僅_
  # 通知 UI 中「應用程式詳細資料」頁面的「參數」標籤。
  parameters:
    # 靜態參數宣告會針對此此外掛程式處理的 _所有_ 應用程式發送到 UI。
    # 可以將此處設定的 `string`、`array` 和 `map` 值視為「預設值」。外掛程式作者有責任確保
    # 這些預設值確實反映了外掛程式的行為，如果使用者沒有為這些參數明確設定不同的值。
    static:
      - name: string-param
        title: 字串參數的描述
        tooltip: 使用者懸停時顯示的工具提示
        # 如果設定了此欄位，UI 將向使用者指示他們必須設定該值。
        required: false
        # itemType 告訴 UI 如何呈現參數的值（或者，對於陣列和對應，是值）。預設為
        # "string"。未來可能支援的其他類型範例是 "boolean" 或 "number"。
        # 即使 itemType 不是 "string"，來自應用程式規格的參數值也將以
        # 字串形式發送到外掛程式。由外掛程式進行適當的轉換。
        itemType: ""
        # collectionType 描述此參數接受的值類型（字串、陣列或對應），並允許 UI
        # 呈現與該類型匹配的表單。預設為 "string"。對於非字串類型，必須存在此欄位。
        # 它不會從 `array` 或 `map` 欄位的存在中推斷出來。
        collectionType: ""
        # 此欄位將參數的預設值傳達給 UI。設定此欄位是選用的。
        string: default-string-value
      # 上述除 "string" 之外的所有欄位都適用於陣列和對應類型的參數宣告。
      - name: array-param
        # 此欄位將參數的預設值傳達給 UI。設定此欄位是選用的。
        array: [default, items]
        collectionType: array
      - name: map-param
        # 此欄位將參數的預設值傳達給 UI。設定此欄位是選用的。
        map:
          some: value
        collectionType: map
    # 動態參數宣告是針對此此外掛程式處理的特定應用程式的宣告。例如，
    # Helm 圖表的 values.yaml 檔案的值可以作為參數宣告發送。
    dynamic:
      # 該指令在應用程式的來源目錄中執行。標準輸出必須是符合
      # 靜態參數宣告列表結構描述的 JSON。
      command: [echo, '[{"name": "example-param", "string": "default-string-value"}]']

  # 如果設定為 `true`，則外掛程式會接收具有原始檔案模式的儲存庫檔案。這很危險，因為
  # 儲存庫可能包含可執行檔。僅在您信任 CMP 外掛程式作者時才設定為 true。
  preserveFileMode: false

  # 如果設定為 `true`，則外掛程式可以在 generate 期間從 reposerver 檢索 git 憑證。外掛程式作者
  # 應確保這些憑證在執行期間得到適當保護。
  provideGitCreds: false
```

> [!NOTE]
> 雖然 `ConfigManagementPlugin` _看起來像_ 一個 Kubernetes 物件，但它實際上不是一個自訂資源。
> 它只遵循 kubernetes 風格的規格慣例。

`generate` 指令必須將有效的 Kubernetes YAML 或 JSON 物件串流列印到 stdout。`init` 和 `generate` 指令都在應用程式來源目錄內執行。

`discover.fileName` 用作 [glob](https://pkg.go.dev/path/filepath#Glob) 模式，以確定應用程式儲存庫是否受外掛程式支援。

```yaml
  discover:
    find:
      command: [sh, -c, find . -name env.yaml]
```

如果未提供 `discover.fileName`，則執行 `discover.find.command` 以確定應用程式儲存庫是否受外掛程式支援。當應用程式來源類型受支援時，`find` 指令應返回非錯誤的結束碼並向 stdout 產生輸出。

#### 將外掛程式組態檔放置在 sidecar 中

Argo CD 期望外掛程式組態檔位於 sidecar 中的 `/home/argocd/cmp-server/config/plugin.yaml`。

如果您為 sidecar 使用自訂映像檔，您可以將該檔案直接添加到該映像檔中。

```dockerfile
WORKDIR /home/argocd/cmp-server/config/
COPY plugin.yaml ./
```

如果您為 sidecar 使用現成映像檔，或者希望將外掛程式組態維護在 ConfigMap 中，只需將外掛程式組態檔巢狀在 ConfigMap 的 `plugin.yaml` 鍵下，並將 ConfigMap 掛載到 sidecar 中（請參閱下一節）。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-plugin-config
data:
  plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: my-plugin
    spec:
      version: v1.0
      init:
        command: [sh, -c, 'echo "正在初始化..."']
      generate:
        command: [sh, -c, 'echo "{\"kind\": \"ConfigMap\", \"apiVersion\": \"v1\", \"metadata\": { \"name\": \"$ARGOCD_APP_NAME\", \"namespace\": \"$ARGOCD_APP_NAMESPACE\", \"annotations\": {\"Foo\": \"$ARGOCD_ENV_FOO\", \"KubeVersion\": \"$KUBE_VERSION\", \"KubeApiVersion\": \"$KUBE_API_VERSIONS\",\"Bar\": \"baz\"}}}"']
      discover:
        fileName: "./subdir/s*.yaml"
```

#### 註冊外掛程式 sidecar

要安裝外掛程式，請修補 `argocd-repo-server` 以將外掛程式容器作為 sidecar 執行，並以 `argocd-cmp-server` 作為其進入點。您可以使用現成的或自訂建置的外掛程式映像檔作為 sidecar 映像檔。例如：

```yaml
containers:
- name: my-plugin
  command: [/var/run/argocd/argocd-cmp-server] # 進入點應為 Argo CD 輕量級 CMP 伺服器，即 argocd-cmp-server
  image: ubuntu # 這可以是現成的或自訂建置的映像檔
  securityContext:
    runAsNonRoot: true
    runAsUser: 999
  volumeMounts:
    - mountPath: /var/run/argocd
      name: var-files
    - mountPath: /home/argocd/cmp-server/plugins
      name: plugins
    # 如果您選擇將組態檔內建到 sidecar 映像檔中，請移除此 volumeMount。
    - mountPath: /home/argocd/cmp-server/config/plugin.yaml
      subPath: plugin.yaml
      name: my-plugin-config
    # 從 v2.4 開始，不要掛載與 repo-server 容器相同的 tmp 磁碟區。檔案系統隔離有助於
    # 緩解路徑遍歷攻擊。
    - mountPath: /tmp
      name: cmp-tmp
volumes:
- configMap:
    name: my-plugin-config
  name: my-plugin-config
- emptyDir: {}
  name: cmp-tmp
```

> [!IMPORTANT]
> **請仔細檢查這些項目**
>
> 1.  確保使用 `/var/run/argocd/argocd-cmp-server` 作為進入點。`argocd-cmp-server` 是一個輕量級的 GRPC 服務，允許 Argo CD 與外掛程式互動。
> 2.  確保 sidecar 容器以使用者 999 的身份執行。
> 3.  確保外掛程式組態檔存在於 `/home/argocd/cmp-server/config/plugin.yaml`。它可以透過 configmap 進行磁碟區映射或內建到映像檔中。

### 在您的外掛程式中使用環境變數

外掛程式指令可以存取

1.  Sidecar 的系統環境變數
2.  [標準建置環境變數](../user-guide/build-environment.md)
3.  應用程式規格中的變數（對系統和建置變數的引用將在變數值中被內插）：

        apiVersion: argoproj.io/v1alpha1
        kind: Application
        spec:
          source:
            plugin:
              env:
                - name: FOO
                  value: bar
                - name: REV
                  value: test-$ARGOCD_APP_REVISION

    在到達 `init.command`、`generate.command` 和 `discover.find.command` 指令之前，Argo CD 會在所有
    使用者提供的環境變數（上面的 #3）前面加上 `ARGOCD_ENV_`。這可以防止使用者直接設定
    潛在敏感的環境變數。

4.  應用程式規格中的參數：

        apiVersion: argoproj.io/v1alpha1
        kind: Application
        spec:
         source:
           plugin:
             parameters:
               - name: values-files
                 array: [values-dev.yaml]
               - name: helm-parameters
                 map:
                   image.tag: v1.2.3

    這些參數在 `ARGOCD_APP_PARAMETERS` 環境變數中以 JSON 格式提供。上面的範例將
    產生此 JSON：

        [{"name": "values-files", "array": ["values-dev.yaml"]}, {"name": "helm-parameters", "map": {"image.tag": "v1.2.3"}}]

    !!! note
        參數宣告，即使它們指定了預設值，也 _不會_ 在 `ARGOCD_APP_PARAMETERS` 中發送到外掛程式。
        只有在應用程式規格中明確設定的參數才會發送到外掛程式。由外掛程式來應用
        與宣告給 UI 的預設值相同的預設值。

    相同的參數也可以作為單獨的環境變數使用。環境變數的名稱
    遵循此慣例：

           - name: some-string-param
             string: some-string-value
           # PARAM_SOME_STRING_PARAM=some-string-value

           - name: some-array-param
             value: [item1, item2]
           # PARAM_SOME_ARRAY_PARAM_0=item1
           # PARAM_SOME_ARRAY_PARAM_1=item2

           - name: some-map-param
             map:
               image.tag: v1.2.3
           # PARAM_SOME_MAP_PARAM_IMAGE_TAG=v1.2.3

> [!WARNING]
> **清理/轉義使用者輸入**
>
> 作為 Argo CD 清單產生系統的一部分，組態管理外掛程式被賦予一定程度的信任。請
> 務必在外掛程式中轉義使用者輸入，以防止惡意輸入導致不必要的行為。

## 將組態管理外掛程式與應用程式一起使用

您可以將 `plugin` 部分中的 `name` 欄位
留空，以便外掛程式根據其發現規則自動與應用程式匹配。如果您確實提到了名稱，請確保
它要麼是 `<metadata.name>-<spec.version>`（如果在 `ConfigManagementPlugin` 規格中提到了版本），要麼只是 `<metadata.name>`。當明確
指定名稱時，只有該特定外掛程式將被使用，前提是其發現模式/指令與提供的應用程式儲存庫匹配。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
    plugin:
      env:
        - name: FOO
          value: bar
```

如果您不需要設定任何環境變數，您可以設定一個空的 plugin 部分。

```yaml
    plugin: {}
```

> [!IMPORTANT]
> 如果您的 CMP 指令執行時間過長，該指令將被終止，UI 將顯示錯誤。CMP 伺服器
> 遵守 `argocd-cmd-params-cm` 中 `server.repo.server.timeout.seconds` 和 `controller.repo.server.timeout.seconds`
> 項目設定的逾時。請將它們的值從預設的 60 秒增加。
>
> 每個 CMP 指令也將在 CMP sidecar 設定的 `ARGOCD_EXEC_TIMEOUT` 上獨立逾時。預設值
> 是 90 秒。因此，如果您將 repo 伺服器逾時增加到大於 90 秒，請務必在
> sidecar 上設定 `ARGOCD_EXEC_TIMEOUT`。

> [!NOTE]
> 每個應用程式一次只能設定一個組態管理外掛程式。如果您要將透過 `argocd-cm` ConfigMap 設定的現有
> 外掛程式轉換為 sidecar，請確保將外掛程式名稱更新為 `<metadata.name>-<spec.version>`
> （如果在 `ConfigManagementPlugin` 規格中提到了版本），或者只使用 `<metadata.name>`。您也可以完全刪除名稱，
> 讓自動發現來識別外掛程式。

> [!NOTE]
> 如果 CMP 呈現空白清單，且 `prune` 設定為 `true`，Argo CD 將自動移除資源。CMP 外掛程式作者應確保錯誤是結束碼的一部分。通常像 `kustomize build . | cat` 這樣的指令不會傳遞錯誤，因為有管道。考慮設定 `set -o pipefail`，這樣任何透過管道傳遞的內容在失敗時都會傳遞錯誤。

> [!NOTE]
> 如果 CMP 指令在 `ARGOCD_EXEC_TIMEOUT` 時未能正常結束，它將在額外的 `ARGOCD_EXEC_FATAL_TIMEOUT` 逾時後被強制終止。

## 調試 CMP

如果您正在積極開發一個透過 sidecar 安裝的 CMP，請記住以下幾點：

1.  如果您是從 ConfigMap 掛載 `plugin.yaml`，您將必須重新啟動 repo-server Pod，這樣外掛程式才能
    讀取到更改。
2.  如果您已將 `plugin.yaml` 內建到您的映像檔中，您將必須建置、推送並強制
    repo-server Pod 重新拉取該映像檔，這樣外掛程式才能讀取到更改。如果您使用的是 `:latest`，Pod 將始終拉取新的
    映像檔。如果您使用的是不同的靜態標籤，請在 CMP 的 sidecar 容器上設定 `imagePullPolicy: Always`。
3.  CMP 錯誤會被 repo-server 緩存在 Redis 中。重新啟動 repo-server Pod 不會清除緩存。在積極開發 CMP 時，請始終
    進行「硬刷新」，以便您擁有最新的輸出。
4.  透過查看 Pod 並看到有兩個容器正在執行來驗證您的 sidecar 是否已正確啟動 `kubectl get pod -l app.kubernetes.io/component=repo-server -n argocd`
5.  將日誌訊息寫入 stderr 並在 sidecar 中設定 `--loglevel=info` 旗標。這將列印寫入 stderr 的所有內容，即使在指令成功執行時也是如此。


### 其他常見錯誤
| 錯誤訊息 | 原因 |
| -- | -- |
| `no matches for kind "ConfigManagementPlugin" in version "argoproj.io/v1alpha1"` | `ConfigManagementPlugin` CRD 在 Argo CD 2.4 中已棄用，並在 2.8 中移除。此錯誤表示您試圖將外掛程式的組態直接作為 CRD 放入 Kubernetes。請參考[本文件此節](#write-the-plugin-configuration-file)以了解如何編寫外掛程式組態檔並將其正確放置在 sidecar 中。 |

## 外掛程式 tar 串流排除

為了加快清單產生的速度，可以將某些檔案和資料夾排除在發送到您的
外掛程式之外。如果不需要，我們建議排除您的 `.git` 資料夾。使用 Go 的
[filepatch.Match](https://pkg.go.dev/path/filepath#Match) 語法。例如，`.git/*` 用於排除 `.git` 資料夾。

您可以透過以下三種方式之一進行設定：

1.  repo 伺服器上的 `--plugin-tar-exclude` 參數。
2.  如果您使用的是 `argocd-cmd-params-cm`，則為 `reposerver.plugin.tar.exclusions` 鍵。
3.  直接在 repo 伺服器上設定 `ARGOCD_REPO_SERVER_PLUGIN_TAR_EXCLUSIONS` 環境變數。

對於選項 1，該旗標可以重複多次。對於選項 2 和 3，您可以透過分號分隔
來指定多個 glob。

## 使用 argocd.argoproj.io/manifest-generate-paths 產生應用程式清單

為了增強應用程式清單的產生過程，您可以啟用 `argocd.argoproj.io/manifest-generate-paths` 註解的使用。當啟用此旗標時，此註解指定的資源將被傳遞到 CMP 伺服器以產生應用程式清單，而不是發送整個儲存庫。這對於 monorepos 特別有用。

您可以透過以下三種方式之一進行設定：

1.  repo 伺服器上的 `--plugin-use-manifest-generate-paths` 參數。
2.  如果您使用的是 `argocd-cmd-params-cm`，則為 `reposerver.plugin.use.manifest.generate.paths` 鍵。
3.  直接將 repo 伺服器上的 `ARGOCD_REPO_SERVER_PLUGIN_USE_MANIFEST_GENERATE_PATHS` 環境變數設定為 `true`。

## 從 argocd-cm 外掛程式遷移

透過修改 `argocd-cm` ConfigMap 來安裝外掛程式的方式自 v2.4 起已棄用，並從 v2.8 開始已完全移除。

CMP 外掛程式的工作方式是向 `argocd-repo-server` 添加一個 sidecar，以及該 sidecar 中位於 `/home/argocd/cmp-server/config/plugin.yaml` 的組態。可以透過以下步驟輕鬆轉換 argocd-cm 外掛程式。

### 將 ConfigMap 條目轉換為組態檔

首先，將外掛程式的組態複製到其自己的 YAML 檔案中。以以下 ConfigMap 條目為例：

```yaml
data:
  configManagementPlugins: |
    - name: pluginName
      init:                          # 初始化應用程式來源目錄的選用指令
        command: ["sample command"]
        args: ["sample args"]
      generate:                      # 產生 YAML 或 JSON 格式的 Kubernetes 物件的指令
        command: ["sample command"]
        args: ["sample args"]
      lockRepo: true                 # 預設為 false。請參閱下文。
```

`pluginName` 項目將被轉換為如下的組態檔：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: pluginName
spec:
  init:                          # 初始化應用程式來源目錄的選用指令
    command: ["sample command"]
    args: ["sample args"]
  generate:                      # 產生 YAML 或 JSON 格式的 Kubernetes 物件的指令
    command: ["sample command"]
    args: ["sample args"]
```

> [!NOTE]
> `lockRepo` 鍵與 sidecar 外掛程式無關，因為 sidecar 外掛程式在產生清單時不共用單一的來源儲存庫
> 目錄。

接下來，我們需要決定這個 yaml 將如何添加到 sidecar 中。我們可以將 yaml 直接內建到映像檔中，也可以從 ConfigMap 掛載它。

如果使用 ConfigMap，我們的範例如下所示：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pluginName
  namespace: argocd
data:
  pluginName.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: pluginName
    spec:
      init:                          # 初始化應用程式來源目錄的選用指令
        command: ["sample command"]
        args: ["sample args"]
      generate:                      # 產生 YAML 或 JSON 格式的 Kubernetes 物件的指令
        command: ["sample command"]
        args: ["sample args"]
```

然後這將被掛載到我們的外掛程式 sidecar 中。

### 為您的外掛程式編寫發現規則

Sidecar 外掛程式可以使用發現規則或外掛程式名稱將應用程式與外掛程式匹配。如果省略發現規則，
則必須在應用程式規格中明確指定外掛程式名稱，否則該特定外掛程式將不匹配任何應用程式。

如果您想使用發現而不是外掛程式名稱來將應用程式與您的外掛程式匹配，請[使用上面的說明](#1-write-the-plugin-configuration-file)為您的外掛程式編寫適用的規則
，並將它們添加到您的組態檔中。

要使用名稱而不是發現，請將應用程式清單中的名稱更新為 `<metadata.name>-<spec.version>`
（如果在 `ConfigManagementPlugin` 規格中提到了版本），或者只使用 `<metadata.name>`。例如：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
spec:
  source:
    plugin:
      name: pluginName  # 刪除此項以進行自動發現（如果 `name` 是唯一的值，則設定 `plugin: {}`）或使用正確的 sidecar 外掛程式名稱
```

### 確保外掛程式有權存取所需的工具

使用 `argocd-cm` 設定的外掛程式在 Argo CD 映像檔上執行。這使它可以預設存取該
映像檔上安裝的所有工具（有關基礎映像檔和
安裝的工具，請參閱 [Dockerfile](https://github.com/argoproj/argo-cd/blob/master/Dockerfile)）。

您可以使用現成的映像檔（如 ubuntu、busybox 或 alpine/k8s），也可以設計自己的基礎映像檔，其中包含外掛程式所需的工具。為
安全起見，請避免使用安裝了比外掛程式實際需要更多的二進位檔案的映像檔。

### 測試外掛程式

在[根據上述說明](#installing-a-config-management-plugin)將外掛程式作為 sidecar 安裝後，
在將所有應用程式遷移到 sidecar 外掛程式之前，先在幾個應用程式上進行測試。

測試通過後，從您的 `argocd-cm` ConfigMap 中移除該外掛程式條目。

### 其他設定

#### 保留儲存庫檔案模式

預設情況下，組態管理外掛程式會收到重設檔案模式的來源儲存庫檔案。這樣做是出於安全
原因。如果您想保留原始檔案模式，可以在外掛程式規格中將 `preserveFileMode` 設定為 `true`：

> [!WARNING]
> 確保您信任正在使用的外掛程式。如果將 `preserveFileMode` 設定為 `true`，則外掛程式可能會收到
> 具有可執行權限的檔案，這可能存在安全風險。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: pluginName
spec:
  init:
    command: ["sample command"]
    args: ["sample args"]
  generate:
    command: ["sample command"]
    args: ["sample args"]
  preserveFileMode: true
```

##### 提供 Git 憑證

預設情況下，組態管理外掛程式負責為在清單產生期間可能需要存取的其他 Git 儲存庫
提供其自己的憑證。reposerver 在其 git creds
儲存中有這些憑證。當允許憑證共享時，reposerver 用於克隆儲存庫內容的 git 憑證
在組態管理外掛程式的執行生命週期內共享，利用 git 的 `ASKPASS` 方法
從組態管理 sidecar 容器呼叫 reposerver 以檢索初始化的 git 憑證。

利用 `ASKPASS` 意味著憑證不是主動共享的，而只是在操作需要時
才提供。

`ASKPASS` 需要在組態管理外掛程式和 reposerver 之間共享一個 socket。為了緩解路徑遍歷
攻擊，建議使用專用磁碟區來共享 socket，並將其掛載在 reposerver 和 sidecar 中。
要更改 socket 路徑，您必須為這兩個容器設定 `ARGOCD_ASK_PASS_SOCK` 環境變數。

要允許外掛程式存取 reposerver git 憑證，您可以在外掛程式規格中將 `provideGitCreds` 設定為 `true`：

> [!WARNING]
> 確保您信任正在使用的外掛程式。如果將 `provideGitCreds` 設定為 `true`，則外掛程式將收到
> 用於克隆來源 Git 儲存庫的憑證。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ConfigManagementPlugin
metadata:
  name: pluginName
spec:
  init:
    command: ["sample command"]
    args: ["sample args"]
  generate:
    command: ["sample command"]
    args: ["sample args"]
  provideGitCreds: true
```
