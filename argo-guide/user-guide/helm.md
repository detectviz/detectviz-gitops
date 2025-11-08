# Helm

## 宣告式

您可以透過 UI 或以宣告式的 GitOps 方式安裝 Helm chart。
Helm [僅用於使用 `helm template` 展開 chart](../../faq#after-deploying-my-helm-application-with-argo-cd-i-cannot-see-it-with-helm-ls-and-other-helm-commands)。應用程式的生命週期由 Argo CD 而非 Helm 處理。
以下是一個範例：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sealed-secrets
  namespace: argocd
spec:
  project: default
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
    targetRevision: 1.16.1
    helm:
      releaseName: sealed-secrets
  destination:
    server: "https://kubernetes.default.svc"
    namespace: kubeseal
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
    chart: nginx
    repoURL: registry-1.docker.io/bitnamicharts  # 注意：不包含 oci:// 語法。
    targetRevision: 15.9.0
  destination:
    name: "in-cluster"
    namespace: nginx
```

> [!NOTE]
> **使用 Helm 時，有多種方式可以提供值**
>
> 優先順序為 `parameters > valuesObject > values > valueFiles > helm repository values.yaml`（有關更詳細的範例，請參閱[此處](./helm.md#helm-value-precedence)）

有關如何設定私有 Helm 儲存庫和私有 OCI 註冊中心的更多資訊，請參閱[此處](../operator-manual/declarative-setup.md#helm)。

## Values 檔案

Helm 能夠使用一個不同的，甚至是多個 "values.yaml" 檔案來衍生其
參數。可以使用 `--values`
旗標指定替代或多個 values 檔案。此旗標可以重複使用以支援多個 values 檔案：

```bash
argocd app set helm-guestbook --values values-production.yaml
```
> [!NOTE]
> 在 Argo CD `v2.6` 之前，Values 檔案必須與 Helm
> chart 位於同一個 git 儲存庫中。檔案可以位於不同的位置，在這種情況下，可以使用
> 相對於 Helm chart 根目錄的相對路徑來存取。
> 自 `v2.6` 起，可以透過利用
> [應用程式的多個來源](./multiple_sources.md#helm-value-files-from-external-git-repository)從與 Helm chart 不同的儲存庫中取得 values 檔案。

在宣告式語法中：

```yaml
source:
  helm:
    valueFiles:
    - values-production.yaml
```

如果 Helm 在範本擴充期間傳遞了不存在的值檔案，它將會出錯。可以
使用 `--ignore-missing-value-files` 忽略遺失的值檔案（也就是說，不傳遞給 Helm）。這對於
實作[預設/覆寫
模式](https://github.com/argoproj/argo-cd/issues/7767#issue-1060611415)與[應用程式
集](./application-set.md)特別有幫助。

在宣告式語法中：
```yaml
source:
  helm:
    valueFiles:
    - values-common.yaml
    - values-optional-override.yaml
    ignoreMissingValueFiles: true
```

## Values

Argo CD 支援在應用程式資訊清單中使用 `source.helm.valuesObject` 索引鍵，直接提供與 values 檔案等效的功能。

```yaml
source:
  helm:
    valuesObject:
      ingress:
        enabled: true
        path: /
        hosts:
          - mydomain.example.com
        annotations:
          kubernetes.io/ingress.class: nginx
          kubernetes.io/tls-acme: "true"
        labels: {}
        tls:
          - secretName: mydomain-tls
            hosts:
              - mydomain.example.com
```

或者，可以使用 `source.helm.values` 索引鍵以字串形式傳入值。

```yaml
source:
  helm:
    values: |
      ingress:
        enabled: true
        path: /
        hosts:
          - mydomain.example.com
        annotations:
          kubernetes.io/ingress.class: nginx
          kubernetes.io/tls-acme: "true"
        labels: {}
        tls:
          - secretName: mydomain-tls
            hosts:
              - mydomain.example.com
```

## Helm 參數

Helm 能夠設定參數值，這些值會覆寫
`values.yaml` 中的任何值。例如，`service.type` 是 Helm chart 中公開的常見參數：

```bash
helm template . --set service.type=LoadBalancer
```

同樣地，Argo CD 可以使用 `argocd app set` 指令，以 `-p PARAM=VALUE` 的形式覆寫 `values.yaml` 參數中的值。例如：

```bash
argocd app set helm-guestbook -p service.type=LoadBalancer
```

在宣告式語法中：

```yaml
source:
  helm:
    parameters:
    - name: "service.type"
      value: LoadBalancer
```

## Helm 值優先順序
值注入具有以下優先順序
 `parameters > valuesObject > values > valueFiles > helm repository values.yaml`
 或者說

```
    最低  -> valueFiles
            -> values
            -> valuesObject
    最高 -> parameters
```

因此，valuesObject 會覆蓋 values - 因此 values 將被忽略，而 valuesObject 和 values 都會覆蓋 valueFiles。
Parameters 會覆蓋所有這些。

多個 valueFiles 的優先順序：
當指定多個 valueFiles 時，最後列出的檔案具有最高的優先順序：

```
valueFiles:
  - values-file-2.yaml
  - values-file-1.yaml

在這種情況下，values-file-1.yaml 將覆寫來自 values-file-2.yaml 的值。
```

當找到多個相同的鍵時，最後一個獲勝，即

```
例如，如果我們只有 values-file-1.yaml 且它包含

param1: value1
param1: value3000

我們會得到 param1=value3000
```

```
parameters:
  - name: "param1"
    value: value2
  - name: "param1"
    value: value1

結果將是 param1=value1
```

```
values: |
  param1: value2
  param1: value5

結果將是 param1=value5
```

> [!NOTE]
> **當使用 valueFiles 或 values 時**
>
> chart 會使用來自不同可能來源的值集以及任何參數正確呈現，並按照此處記錄的預期順序合併。
> UI 中存在一個錯誤（請參閱[此議題](https://github.com/argoproj/argo-cd/issues/9213)），它只會顯示參數，也就是說，它不會代表完整的值集。
> 作為一個變通方法，使用參數而不是 values/valuesObject 將提供更好的資源使用概觀。

## Helm --set-file 支援

helm 的 `--set-file` 引數可以在 cli 上使用以下語法：

```bash
argocd app set helm-guestbook --helm-set-file some.key=path/to/file.ext
```

或使用 fileParameters for yaml：

```yaml
source:
  helm:
    fileParameters:
      - name: some.key
        path: path/to/file.ext
```

## Helm 發行版本名稱

預設情況下，Helm 發行版本名稱等於其所屬的應用程式名稱。有時，特別是在集中式的 Argo CD 上，
您可能希望覆寫該名稱，這可以透過 cli 上的 `release-name` 旗標來實現：

```bash
argocd app set helm-guestbook --release-name myRelease
```

 或使用 releaseName for yaml：

```yaml
source:
    helm:
      releaseName: myRelease
```

> [!WARNING]
> **覆寫發行版本名稱的重要注意事項**
>
> 請注意，覆寫 Helm 發行版本名稱可能會在您部署的圖表使用 `app.kubernetes.io/instance` 標籤時造成問題。Argo CD 會將此標籤與應用程式名稱的值一起注入以進行追蹤。因此，當覆寫發行版本名稱時，應用程式名稱將不再等於發行版本名稱。由於 Argo CD 會以應用程式名稱覆寫該標籤，這可能會導致資源上的某些選取器停止運作。為了避免這種情況，我們可以在 [ArgoCD configmap argocd-cm.yaml](../operator-manual/argocd-cm.yaml) 中設定 Argo CD 使用另一個標籤進行追蹤 - 請檢查描述 `application.instanceLabelKey` 的行。

## Helm Hooks

Helm hooks 類似於 [Argo CD hooks](resource_hooks.md)。在 Helm 中，一個 hook
是任何以 `helm.sh/hook` 註解標記的普通 Kubernetes 資源。

Argo CD 透過將 Helm 註解對應到 Argo CD 自己的 hook 註解來支援許多（大多數？）Helm hooks：

| Helm 註解                 | 注意事項                                                                                         |
| ------------------------------- |-----------------------------------------------------------------------------------------------|
| `helm.sh/hook: crd-install`     | 支援為與一般 Argo CD CRD 處理等效。                                |
| `helm.sh/hook: pre-delete`      | 不支援。在 Helm stable 中，有 3 種情況用於清理 CRD，3 種情況用於清理作業。 |
| `helm.sh/hook: pre-rollback`    | 不支援。在 Helm stable 中從未使用過。                                                     |
| `helm.sh/hook: pre-install`     | 支援為與 `argocd.argoproj.io/hook: PreSync` 等效。                                |
| `helm.sh/hook: pre-upgrade`     | 支援為與 `argocd.argoproj.io/hook: PreSync` 等效。                                |
| `helm.sh/hook: post-upgrade`    | 支援為與 `argocd.argoproj.io/hook: PostSync` 等效。                               |
| `helm.sh/hook: post-install`    | 支援為與 `argocd.argoproj.io/hook: PostSync` 等效。                               |
| `helm.sh/hook: post-delete`     | 支援為與 `argocd.argoproj.io/hook: PostDelete` 等效。                             |
| `helm.sh/hook: post-rollback`   | 不支援。在 Helm stable 中從未使用過。                                                     |
| `helm.sh/hook: test-success`    | 不支援。在 Argo CD 中沒有等效項。                                                      |
| `helm.sh/hook: test-failure`    | 不支援。在 Argo CD 中沒有等效項。                                                      |
| `helm.sh/hook-delete-policy`    | 支援。另請參閱 `argocd.argoproj.io/hook-delete-policy`)。                                 |
| `helm.sh/hook-delete-timeout`   | 不支援。在 Helm stable 中從未使用過                                                      |
| `helm.sh/hook-weight`           | 支援為與 `argocd.argoproj.io/sync-wave` 等效。                                    |
| `helm.sh/resource-policy: keep` | 支援為與 `argocd.argoproj.io/sync-options: Delete=false` 等效。                   |

不支援的掛鉤會被忽略。在 Argo CD 中，掛鉤是使用 `kubectl apply` 建立的，而不是 `kubectl create`。這意味著如果掛鉤已命名且已存在，除非您已使用 `before-hook-creation` 對其進行註解，否則它不會變更。

> [!WARNING]
> **Helm hooks + ArgoCD hooks**
>
> 如果您定義了任何 Argo CD hooks，_所有_ Helm hooks 都將被忽略。

> [!WARNING]
> **'install' vs 'upgrade' vs 'sync'**
>
> Argo CD 無法知道它是在執行第一次「安裝」還是「升級」——每個操作都是「同步」。這意味著，預設情況下，具有 `pre-install` 和 `pre-upgrade` 的應用程式將同時執行這些掛鉤。

### Hook 提示

* 使您的 hook 具有冪等性。
* 使用 `hook-weight: "-1"` 註解 `pre-install` 和 `post-install`。這將確保它在任何升級 hook 之前成功執行。
* 使用 `hook-delete-policy: before-hook-creation` 註解 `pre-upgrade` 和 `post-upgrade`，以確保它在每次同步時都執行。

閱讀更多關於 [Argo hooks](resource_hooks.md) 和 [Helm hooks](https://helm.sh/docs/topics/charts_hooks/) 的資訊。

## 隨機資料

Helm 範本引擎能夠在圖表呈現期間透過
`randAlphaNum` 函式產生隨機資料。[圖表儲存庫](https://github.com/helm/charts)中的許多 helm 圖表
都利用了此功能。例如，以下是
[redis helm 圖表](https://github.com/helm/charts/blob/master/stable/redis/templates/secret.yaml)的密碼：

```yaml
data:
  {{- if .Values.password }}
  redis-password: {{ .Values.password | b64enc | quote }}
  {{- else }}
  redis-password: {{ randAlphaNum 10 | b64enc | quote }}
  {{- end }}
```

Argo CD 應用程式控制器會定期將 Git 狀態與即時狀態進行比較，並執行
`helm template <CHART>` 指令以產生 helm 資訊清單。由於每次
比較時都會重新產生隨機值，因此任何使用 `randAlphaNum`
函式的應用程式都會一直處於 `OutOfSync` 狀態。可以透過在 values.yaml 中明確設定一個
值，或使用 `argocd app set` 指令覆寫該值，以使該值
在每次比較之間保持穩定，來緩解此問題。例如：

```bash
argocd app set redis -p password=abc123
```

## 建置環境

Helm 應用程式可以透過參數替換的方式存取[標準建置環境](build-environment.md)。

例如，透過 CLI：

```bash
argocd app create APPNAME \
  --helm-set-string 'app=${ARGOCD_APP_NAME}'
```

或透過宣告式語法：

```yaml
  spec:
    source:
      helm:
        parameters:
        - name: app
          value: $ARGOCD_APP_NAME
```

也可以將建置環境變數用於 Helm values 檔案路徑：

```yaml
  spec:
    source:
      helm:
        valueFiles:
        - values.yaml
        - myprotocol://somepath/$ARGOCD_APP_NAME/$ARGOCD_APP_REVISION
```

## Helm 外掛程式

Argo CD 對您使用的雲端供應商和您使用的 Helm 外掛程式種類沒有任何意見，這就是為什麼 ArgoCD 映像檔中沒有提供任何外掛程式的原因。

但有時您會想使用自訂外掛程式。也許您想使用 Google Cloud Storage 或 Amazon S3 儲存來儲存 Helm charts，例如：https://github.com/hayorov/helm-gcs，您可以使用 `gs://` 協定來存取 Helm chart 儲存庫。
有兩種方法可以安裝自訂外掛程式；您可以修改 ArgoCD 容器映像檔，也可以使用 Kubernetes `initContainer`。

### 修改 ArgoCD 容器映像檔
使用此插件的一種方法是準備您自己的 ArgoCD 映像檔，其中包含此插件。

範例 `Dockerfile`：

```dockerfile
FROM argoproj/argocd:v1.5.7

USER root
RUN apt-get update && \
    apt-get install -y \
        curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

USER argocd

ARG GCS_PLUGIN_VERSION="0.3.5"
ARG GCS_PLUGIN_REPO="https://github.com/hayorov/helm-gcs.git"

RUN helm plugin install ${GCS_PLUGIN_REPO} --version ${GCS_PLUGIN_VERSION}

ENV HELM_PLUGINS="/home/argocd/.local/share/helm/plugins/"
```

`HELM_PLUGINS` 環境屬性是 ArgoCD 正確找到外掛程式所必需的。

建置完成後，使用自訂映像檔進行 ArgoCD 安裝。

### 使用 `initContainers`
另一個選項是透過 Kubernetes `initContainers` 安裝 Helm 外掛程式。
有些使用者認為這種模式比維護自己的 ArgoCD 容器映像檔版本更可取。

以下是使用[官方 ArgoCD helm chart](https://github.com/argoproj/argo-helm/tree/master/charts/argo-cd) 安裝 ArgoCD 時如何新增 Helm 外掛程式的範例：

```yaml
repoServer:
  volumes:
    - name: gcp-credentials
      secret:
        secretName: my-gcp-credentials
  volumeMounts:
    - name: gcp-credentials
      mountPath: /gcp
  env:
    - name: HELM_CACHE_HOME
      value: /helm-working-dir
    - name: HELM_CONFIG_HOME
      value: /helm-working-dir
    - name: HELM_DATA_HOME
      value: /helm-working-dir
  initContainers:
    - name: helm-gcp-authentication
      image: alpine/helm:3.16.1
      volumeMounts:
        - name: helm-working-dir
          mountPath: /helm-working-dir
        - name: gcp-credentials
          mountPath: /gcp
      env:
        - name: HELM_CACHE_HOME
          value: /helm-working-dir
        - name: HELM_CONFIG_HOME
          value: /helm-working-dir
        - name: HELM_DATA_HOME
          value: /helm-working-dir
      command: [ "/bin/sh", "-c" ]
      args:
        - apk --no-cache add curl;
          helm plugin install https://github.com/hayorov/helm-gcs.git;
          helm repo add my-gcs-repo gs://my-private-helm-gcs-repository;
          chmod -R 777 $HELM_DATA_HOME;
```

## Helm 版本

Argo CD 會假設 Helm chart 是 v3 版本（即使 chart 中的 apiVersion 欄位是 Helm v2），除非在 Argo CD 應用程式中明確指定為 v2（請參閱下方）。

如果需要，可以透過在 cli 上設定 `helm-version` 旗標來明確設定要使用的 Helm 版本（v2 或 v3）：

```bash
argocd app set helm-guestbook --helm-version v3
```

或使用宣告式語法：

```yaml
spec:
  source:
    helm:
      version: v3
```

## Helm `--pass-credentials`

Helm，[從 v3.6.1 開始](https://github.com/helm/helm/releases/tag/v3.6.1)，
防止傳送儲存庫憑證以下載來自與儲存庫不同網域的圖表。

如果需要，可以透過在 cli 上設定 `helm-pass-credentials` 旗標來選擇為所有網域傳遞憑證：

```bash
argocd app set helm-guestbook --helm-pass-credentials
```

或使用宣告式語法：

```yaml
spec:
  source:
    helm:
      passCredentials: true
```

## Helm `--skip-crds`

預設情況下，如果 `crds` 資料夾中不存在自訂資源定義，Helm 會安裝它們。
詳情請參閱 [CRD 最佳實踐](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/)。

如果需要，可以使用 cli 上的 `helm-skip-crds` 旗標跳過 CRD 安裝步驟：

```bash
argocd app set helm-guestbook --helm-skip-crds
```

或使用宣告式語法：

```yaml
spec:
  source:
    helm:
      skipCrds: true
```

## Helm `--skip-schema-validation`

Helm 使用 values.schema.json 檔案來驗證 values.yaml 檔案。詳情請參閱 [Schema 檔案](https://helm.sh/docs/topics/charts/#schema-files)。

如果需要，可以透過 cli 上的 `helm-skip-schema-validation` 旗標跳過 schema 驗證步驟：

```bash
argocd app set helm-guestbook --helm-skip-schema-validation
```

或使用宣告式語法：

```yaml
spec:
  source:
    helm:
      skipSchemaValidation: true
```


## Helm `--skip-tests`

預設情況下，Helm 在呈現範本時會包含測試資訊清單。Argo CD 目前會略過包含 Argo CD 不支援的 hook 的資訊清單，包括 [Helm 測試 hook](https://helm.sh/docs/topics/chart_tests/)。雖然此功能涵蓋了許多測試使用案例，但它與 --skip-tests 並不完全一致，因此可以使用 --skip-tests 選項。

如果需要，可以透過 cli 上的 `helm-skip-tests` 旗標跳過測試資訊清單安裝步驟：

```bash
argocd app set helm-guestbook --helm-skip-tests
```

或使用宣告式語法：

```yaml
spec:
  source:
    helm:
      skipTests: true # 或 false
```
