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
