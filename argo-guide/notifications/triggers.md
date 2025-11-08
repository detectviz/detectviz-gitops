觸發器定義了何時應發送通知的條件。其定義包括名稱、條件
和通知範本參考。條件是一個謂詞表達式，如果應發送通知，則返回 true
。觸發器條件評估由 [antonmedv/expr](https://github.com/antonmedv/expr) 提供支援。
條件語言語法在 [language-definition.md](https://github.com/antonmedv/expr/blob/master/docs/language-definition.md) 中有所描述。

觸發器在 `argocd-notifications-cm` ConfigMap 中設定。例如，以下觸發器在
應用程式同步狀態變更為 `Unknown` 時，使用 `app-sync-status` 範本發送通知：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  trigger.on-sync-status-unknown: |
    - when: app.status.sync.status == 'Unknown'     # 觸發器條件
      send: [app-sync-status, github-commit-status] # 範本名稱
```

每個條件可能使用多個範本。通常，每個範本負責產生特定於服務的通知部分。
在上面的範例中，`app-sync-status` 範本「知道」如何建立電子郵件和 Slack 通知，而 `github-commit-status` 知道如何
為 GitHub webhook 產生承載。

## 條件組合包

觸發器通常由管理員管理，並封裝有關何時以及應發送哪個通知的資訊。
終端使用者只需訂閱觸發器並指定通知目的地。為了改善使用者體驗，
觸發器可能包含多個條件，每個條件都有不同的範本集。例如，以下觸發器
涵蓋了同步狀態操作的所有階段，並針對不同情況使用不同的範本：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  trigger.sync-operation-change: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [github-commit-status]
    - when: app.status.operationState.phase in ['Running']
      send: [github-commit-status]
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed, github-commit-status]
```

## 避免過於頻繁地發送相同的通知

在某些情況下，觸發器條件可能會「抖動」。下面的範例說明了這個問題。
該觸發器應該在 Argo CD 應用程式成功同步且健康時產生一次通知。
但是，應用程式健康狀態可能會間歇性地切換到 `Progressing`，然後再切換回 `Healthy`，因此觸發器可能會不必要地產生
多個通知。`oncePer` 欄位設定觸發器僅在相應的應用程式欄位變更時才產生通知。
下面範例中的 `on-deployed` 觸發器僅針對部署儲存庫的每個觀察到的 Git 修訂版本發送一次通知。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  # 可選的 'oncePer' 屬性確保每個指定的欄位值只發送一次通知
  # 例如，以下是每個同步修訂版本觸發一次
  trigger.on-deployed: |
    when: app.status.operationState.phase in ['Succeeded'] and app.status.health.status == 'Healthy'
    oncePer: app.status.sync.revision
    send: [app-sync-succeeded]
```

**單一儲存庫用法**

當一個儲存庫用於同步多個應用程式時，`oncePer: app.status.sync.revision` 欄位將為每個提交觸發一次通知。對於單一儲存庫，更好的方法是使用 `oncePer: app.status.operationState.syncResult.revision` 語句。這樣，只會為特定應用程式的修訂版本發送通知。

### oncePer

`oncePer` 欄位的支援方式如下。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    example.com/version: v0.1
```

```yaml
oncePer: app.metadata.annotations["example.com/version"]
```

## 預設觸發器

您可以使用 `defaultTriggers` 欄位，而不是為註解指定個別觸發器。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
data:
  # 如果未在訂閱中明確指定觸發器，則保留預設使用的觸發器清單
  defaultTriggers: |
    - on-sync-status-unknown

  defaultTriggers.mattermost: |
    - on-sync-running
    - on-sync-succeeded
```

如下所示指定註解以使用 `defaultTriggers`。在此範例中，`slack` 在 `on-sync-status-unknown` 時發送，而 `mattermost` 在 `on-sync-running` 和 `on-sync-succeeded` 時發送。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.slack: my-channel
    notifications.argoproj.io/subscribe.mattermost: my-mattermost-channel
```

## 函式

觸發器可以存取一組內建函式。

範例：

```yaml
when: time.Now().Sub(time.Parse(app.status.operationState.startedAt)).Minutes() >= 5
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
