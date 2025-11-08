# 插件產生器

插件可讓您提供自己的產生器。

- 您可以使用任何語言編寫
- 簡單：插件只需回應 RPC HTTP 請求。
- 您可以在 sidecar 或獨立部署中使用它。
- 您今天就可以讓您的插件執行，無需等待 3-5 個月的審查、批准、合併和 Argo 軟體
  版本發布。
- 您可以將它與 Matrix 或 Merge 結合使用。

若要開始開發您自己的插件，您可以根據範例
[applicationset-hello-plugin](https://github.com/argoj-labs/applicationset-hello-plugin) 產生一個新的儲存庫。

## 簡單範例

使用產生器插件而不將其與 Matrix 或 Merge 結合。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myplugin
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - plugin:
        # 指定插件組態所在的 configMap。
        configMapRef:
          name: my-plugin
        # 您可以將任意參數傳遞給插件。`input.parameters` 是一個 map，但值可以是任何類型。
        # 這些參數也將在產生器的輸出中以 `generator.input.parameters` 鍵提供。
        input:
          parameters:
            key1: "value1"
            key2: "value2"
            list: ["list", "of", "values"]
            boolean: true
            map:
              key1: "value1"
              key2: "value2"
              key3: "value3"

        # 您還可以將任意值附加到產生器的輸出中，鍵為 `values`。這些值將在
        # 範本中以 `values` 鍵提供。
        values:
          value1: something

        # 使用插件產生器時，ApplicationSet 控制器會每隔 `requeueAfterSeconds` 間隔（預設為每 30 分鐘）輪詢一次以偵測變更。
        requeueAfterSeconds: 30
  template:
    metadata:
      name: myplugin
      annotations:
        example.from.input.parameters: "{{ index .generator.input.parameters.map "key1" }}"
        example.from.values: "{{ .values.value1 }}"
        # 插件決定它還會產生什麼。
        example.from.plugin.output: "{{ .something.from.the.plugin }}"
```

- `configMapRef.name`：包含用於 RPC 呼叫的插件組態的 `ConfigMap` 名稱。
- `input.parameters`：包含在對插件的 RPC 呼叫中的輸入參數。（可選）

> [!NOTE]
> 插件的概念不應透過將資料外部化到 Git 之外來破壞 GitOps 的精神。目標是在特定情境下互補。
> 例如，當使用其中一個 PullRequest 產生器時，無法擷取與 CI 相關的參數（只有提交雜湊可用），這限制了可能性。透過使用插件，可以從單獨的資料來源擷取必要的參數，並使用它們來擴充產生器的功能。

### 新增 ConfigMap 以設定插件的存取權限

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-plugin
  namespace: argocd
data:
  token: "$plugin.myplugin.token" # 或者 $<some_K8S_secret>:plugin.myplugin.token
  baseUrl: "http://myplugin.plugin-ns.svc.cluster.local."
  requestTimeout: "60"
```

- `token`：用於驗證 HTTP 請求的預共享權杖（指向您在 `argocd-secret` Secret 中建立的正確金鑰）
- `baseUrl`：在叢集中公開您插件的 k8s 服務的 BaseUrl。
- `requestTimeout`：對插件的請求逾時（以秒為單位）（預設：30）

### 儲存憑證

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-secret
    app.kubernetes.io/part-of: argocd
type: Opaque
data:
  # ...
  # 密鑰值必須進行**一次** base64 編碼。
  # 此值對應於：`printf "strong-password" | base64`。
  plugin.myplugin.token: "c3Ryb25nLXBhc3N3b3Jk"
  # ...
```

#### 替代方案

如果您想將敏感資料儲存在**另一個** Kubernetes `Secret` 中，而不是 `argocd-secret`，ArgoCD 知道如何檢查您的 Kubernetes `Secret` 中 `data` 下的鍵，只要 configmap 中的值以 `$` 開頭，後面接著您的 Kubernetes `Secret` 名稱和 `:`（冒號），然後是鍵名。

語法：`$<k8s_secret_name>:<a_key_in_that_k8s_secret>`

> 注意：Secret 必須具有標籤 `app.kubernetes.io/part-of: argocd`

##### 範例

`another-secret`：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: another-secret
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
type: Opaque
data:
  # ...
  # 如下儲存用戶端密鑰。
  # 密鑰值必須進行**一次** base64 編碼。
  # 此值對應於：`printf "strong-password" | base64`。
  plugin.myplugin.token: "c3Ryb25nLXBhc3N3b3Jk"
```

### HTTP 伺服器

#### 一個簡單的 Python 插件

您可以將其部署為 sidecar 或獨立部署（建議後者）。

在此範例中，權杖儲存在此位置的檔案中：`/var/run/argo/token`

```
strong-password
```

```python
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

with open("/var/run/argo/token") as f:
    plugin_token = f.read().strip()


class Plugin(BaseHTTPRequestHandler):

    def args(self):
        return json.loads(self.rfile.read(int(self.headers.get('Content-Length'))))

    def reply(self, reply):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(reply).encode("UTF-8"))

    def forbidden(self):
        self.send_response(403)
        self.end_headers()

    def unsupported(self):
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if self.headers.get("Authorization") != "Bearer " + plugin_token:
            self.forbidden()

        if self.path == '/api/v1/getparams.execute':
            args = self.args()
            self.reply({
                "output": {
                    "parameters": [
                        {
                            "key1": "val1",
                            "key2": "val2"
                        },
                        {
                            "key1": "val2",
                            "key2": "val2"
                        }
                    ]
                }
            })
        else:
            self.unsupported()


if __name__ == '__main__':
    httpd = HTTPServer(('', 4355), Plugin)
    httpd.serve_forever()
```

使用 curl 執行 getparams：

```
curl http://localhost:4355/api/v1/getparams.execute -H "Authorization: Bearer strong-password" -d \
'{
  "applicationSetName": "fake-appset",
  "input": {
    "parameters": {
      "param1": "value1"
    }
  }
}'
```

這裡有幾點需要注意：

- 您只需要實作 `/api/v1/getparams.execute` 呼叫
- 您應該檢查 `Authorization` 標頭是否包含與 `/var/run/argo/token` 相同的不記名值。如果沒有，則傳回 403
- 輸入參數包含在請求主體中，可以使用 `input.parameters` 變數存取。
- 輸出必須始終是在 map 中巢狀於 `output.parameters` 鍵下的物件 map 清單。
- `generator.input.parameters` 和 `values` 是保留鍵。如果出現在插件輸出中，這些鍵將被 ApplicationSet 的插件產生器規格中 `input.parameters` 和 `values` 鍵的內容覆寫。

## 使用 matrix 和 pull request 範例

在以下範例中，插件實作會傳回給定分支的一組映像摘要。傳回的清單僅包含一個項目，對應於該分支的最新建置映像。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: fb-matrix
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - pullRequest:
              github: ...
              requeueAfterSeconds: 30
          - plugin:
              configMapRef:
                name: cm-plugin
              input:
                parameters:
                  branch: "{{.branch}}" # 由產生器 pull request 提供
              values:
                branchLink: "https://git.example.com/org/repo/tree/{{.branch}}"
  template:
    metadata:
      name: "fb-matrix-{{.branch}}"
    spec:
      source:
        repoURL: "https://github.com/myorg/myrepo.git"
        targetRevision: "HEAD"
        path: charts/my-chart
        helm:
          releaseName: fb-matrix-{{.branch}}
          valueFiles:
            - values.yaml
          values: |
            front:
              image: myregistry:{{.branch}}@{{ .digestFront }} # digestFront 由插件產生
            back:
              image: myregistry:{{.branch}}@{{ .digestBack }} # digestBack 由插件產生
      project: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{.branch}}"
      info:
        - name: Link to the Application's branch
          value: "{{values.branchLink}}"
```

為了說明：

- 產生器 pullRequest 將會傳回，例如，2 個分支：`feature-branch-1` 和 `feature-branch-2`。

- 產生器插件接著將會執行 2 個請求，如下所示：

```shell
curl http://localhost:4355/api/v1/getparams.execute -H "Authorization: Bearer strong-password" -d \
'{
  "applicationSetName": "fb-matrix",
  "input": {
    "parameters": {
      "branch": "feature-branch-1"
    }
  }
}'
```

然後，

```shell
curl http://localhost:4355/api/v1/getparams.execute -H "Authorization: Bearer strong-password" -d \
'{
  "applicationSetName": "fb-matrix",
  "input": {
    "parameters": {
      "branch": "feature-branch-2"
    }
  }
}'
```

對於每個呼叫，它將傳回唯一的結果，例如：

```json
{
  "output": {
    "parameters": [
      {
        "digestFront": "sha256:a3f18c17771cc1051b790b453a0217b585723b37f14b413ad7c5b12d4534d411",
        "digestBack": "sha256:4411417d614d5b1b479933b7420079671facd434fd42db196dc1f4cc55ba13ce"
      }
    ]
  }
}
```

然後，

```json
{
  "output": {
    "parameters": [
      {
        "digestFront": "sha256:7c20b927946805124f67a0cb8848a8fb1344d16b4d0425d63aaa3f2427c20497",
        "digestBack": "sha256:e55e7e40700bbab9e542aba56c593cb87d680cefdfba3dd2ab9cfcb27ec384c2"
      }
    ]
  }
}
```

在此範例中，透過結合兩者，您可以確保一個或多個 pull request 可用，並且產生的標籤已正確產生。這僅憑提交雜湊是不可能的，因為雜湊本身並不能證明建置成功。
