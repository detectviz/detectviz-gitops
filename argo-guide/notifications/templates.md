通知範本用於產生通知內容，並在 `argocd-notifications-cm` ConfigMap 中設定。範本利用
[html/template](https://golang.org/pkg/html/template/) golang 套件，並允許自訂通知訊息。
範本旨在可重複使用，並可由多個觸發器引用。

以下範本用於通知使用者有關應用程式同步狀態的資訊。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.my-custom-template-slack-template: |
    message: |
      應用程式 {{.app.metadata.name}} 的同步狀態為 {{.app.status.sync.status}}。
      應用程式詳細資訊： {{.context.argocdUrl}}/applications/{{.app.metadata.name}}。
```

每個範本都可以存取以下欄位：

- `app` 持有應用程式物件。
- `context` 是一個使用者定義的字串對應，可以包含任何字串鍵和值。
- `secrets` 提供對儲存在 `argocd-notifications-secret` 中的敏感資料的存取權限。
- `serviceType` 持有通知服務類型名稱（例如「slack」或「email」）。該欄位可用於有條件地
呈現特定於服務的欄位。
- `recipient` 持有收件人姓名。

## 定義使用者定義的 `context`

可以透過設定一個頂層的鍵值對 YAML 文件來定義所有通知範本之間的一些共享上下文
，然後可以在範本中使用這些上下文，如下所示：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  context: |
    region: east
    environmentName: staging

  template.a-slack-template-with-context: |
    message: "在 {{ .context.region }} 資料中心的 {{ .context.environmentName }} 中發生了一些事情！"
```

## 在通知範本中定義和使用密碼

某些通知服務使用案例將需要在範本中使用密碼。這可以透過使用
範本中可用的 `secrets` 資料變數來實現。

假設我們有以下 `argocd-notifications-secret`：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
stringData:
  sampleWebhookToken: secret-token
type: Opaque
```

我們可以在範本中這樣使用已定義的 `sampleWebhookToken`：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.trigger-webhook: |
      webhook:
        sample-webhook:
          method: POST
          path: 'webhook/endpoint/with/auth'
          body: 'token={{ .secrets.sampleWebhookToken }}&variables[APP_SOURCE_PATH]={{ .app.spec.source.path }}
```

## 通知服務特定欄位

範本定義的 `message` 欄位允許為任何通知服務建立基本通知。您可以利用特定於通知服務的
欄位來建立複雜的通知。例如，使用特定於服務的欄位，您可以為 Slack 新增區塊和附件、為電子郵件新增主旨或為 Webhook 新增 URL 路徑和內文。
有關更多資訊，請參閱相應的服務[文件](services/overview.md)。

## 變更時區

您可以如下所示變更要在通知中顯示的時區。

1. 呼叫時間函式。

    ```
    {{ (call .time.Parse .app.status.operationState.startedAt).Local.Format "2006-01-02T15:04:05Z07:00" }}
    ```

2. 在 argocd-notifications-controller 容器上設定 `TZ` 環境變數。

    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: argocd-notifications-controller
    spec:
      template:
        spec:
          containers:
          - name: argocd-notifications-controller
            env:
            - name: TZ
              value: Asia/Tokyo
    ```

## 函式

範本可以存取一組內建函式，例如 [Sprig](https://masterminds.github.io/sprig/) 套件的函式。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  template.my-custom-template-slack-template: |
    message: "作者：{{(call .repo.GetCommitMetadata .app.status.sync.revision).Author}}"
```

### **time**
時間相關函式。

<hr>
**`time.Now() Time`**

執行內建的 Golang [time.Now](https://golang.org/pkg/time/#Now) 函式。返回一個 Golang [Time](https://golang.org/pkg/time/#Time) 的實例。

<hr>
**`time.Parse(val string) Time`**

使用 RFC3339 格式解析指定的字串。返回一個 Golang [Time](https://golang.org/pkg/time/#Time) 的實例。

<hr>
時間相關常數。

**持續時間**

```
	time.Nanosecond   = 1
	time.Microsecond  = 1000 * Nanosecond
	time.Millisecond  = 1000 * Microsecond
	time.Second       = 1000 * Millisecond
	time.Minute       = 60 * Second
	time.Hour         = 60 * Minute
```

**時間戳記**

用於將時間實例格式化為字串時（例如 `time.Now().Format(time.RFC3339)`）。

```
	time.Layout      = "01/02 03:04:05PM '06 -0700" // The reference time, in numerical order.
	time.ANSIC       = "Mon Jan _2 15:04:05 2006"
	time.UnixDate    = "Mon Jan _2 15:04:05 MST 2006"
	time.RubyDate    = "Mon Jan 02 15:04:05 -0700 2006"
	time.RFC822      = "02 Jan 06 15:04 MST"
	time.RFC822Z     = "02 Jan 06 15:04 -0700" // RFC822 with numeric zone
	time.RFC850      = "Monday, 02-Jan-06 15:04:05 MST"
	time.RFC1123     = "Mon, 02 Jan 2006 15:04:05 MST"
	time.RFC1123Z    = "Mon, 02 Jan 2006 15:04:05 -0700" // RFC1123 with numeric zone
	time.RFC3339     = "2006-01-02T15:04:05Z07:00"
	time.RFC3339Nano = "2006-01-02T15:04:05.999999999Z07:00"
	time.Kitchen     = "3:04PM"
	// Handy time stamps.
	time.Stamp      = "Jan _2 15:04:05"
	time.StampMilli = "Jan _2 15:04:05.000"
	time.StampMicro = "Jan _2 15:04:05.000000"
	time.StampNano  = "Jan _2 15:04:05.000000000"
```

### **strings**
字串相關函式。

<hr>
**`strings.ReplaceAll() string`**

執行內建的 Golang [strings.ReplaceAll](https.pkg.go.dev/strings#ReplaceAll) 函式。

<hr>
**`strings.ToUpper() string`**

執行內建的 Golang [strings.ToUpper](https.pkg.go.dev/strings#ToUpper) 函式。

<hr>
**`strings.ToLower() string`**

執行內建的 Golang [strings.ToLower](https.pkg.go.dev/strings#ToLower) 函式。

### **sync**

<hr>
**`sync.GetInfoItem(app map, name string) string`**
按給定名稱返回儲存在 Argo CD 應用程式同步操作中的 `info` 項目值。

### **repo**
提供有關應用程式來源儲存庫的附加資訊的函式。
<hr>
**`repo.RepoURLToHTTPS(url string) string`**

將給定的 GIT URL 轉換為 HTTPs 格式。

<hr>
**`repo.FullNameByRepoURL(url string) string`**

返回儲存庫 URL 的完整名稱 `(<owner>/<repoName>)`。目前僅支援 Github、GitLab 和 Bitbucket。

<hr>
**`repo.QueryEscape(s string) string`**

QueryEscape 會對字串進行轉義，以便可以安全地置於 URL 內。

範例：
```
/projects/{{ call .repo.QueryEscape (call .repo.FullNameByRepoURL .app.status.RepoURL) }}/merge_requests
```

<hr>
**`repo.GetCommitMetadata(sha string) CommitMetadata`**

返回提交的元資料。該提交必須屬於應用程式的來源儲存庫。`CommitMetadata` 欄位：

* `Message string` 提交訊息
* `Author string` - 提交作者
* `Date time.Time` - 提交建立日期
* `Tags []string` - 關聯的標籤

<hr>
**`repo.GetAppDetails() AppDetail`**

返回應用程式的詳細資訊。`AppDetail` 欄位：

* `Type string` - AppDetail 類型
* `Helm HelmAppSpec` - Helm 詳細資訊
  * 欄位：
    * `Name string`
    * `ValueFiles []string`
    * `Parameters []*v1alpha1.HelmParameter`
    * `Values string`
    * `FileParameters []*v1alpha1.HelmFileParameter`
  * 方法：
    * `GetParameterValueByName(Name string)` 根據名稱在 Parameters 欄位中檢索值
    * `GetFileParameterPathByName(Name string)` 根據名稱在 FileParameters 欄位中檢索路徑
*
* `Kustomize *apiclient.KustomizeAppSpec` - Kustomize 詳細資訊
* `Directory *apiclient.DirectoryAppSpec` - Directory 詳細資訊
