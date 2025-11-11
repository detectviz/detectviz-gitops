# 深層連結 (Deep Links)

深層連結允許使用者從 Argo CD 使用者介面快速重新導向到第三方系統，例如 Splunk、Datadog 等。

Argo CD 管理員將能夠透過在 `argocd-cm` 中設定的深層連結範本來設定指向第三方系統的連結。這些範本可以有條件地呈現，並且能夠參考與連結顯示位置相關的不同類型的資源，包括專案、應用程式或個別資源（pods、services 等）。

## 設定深層連結

深層連結的設定存在於 `argocd-cm` 中，格式為 `<location>.links` 欄位，其中 `<location>` 決定了它將在哪裡顯示。`<location>` 的可能值為：

- `project`：此欄位下的所有連結將顯示在 Argo CD UI 的專案標籤中
- `application`：此欄位下的所有連結將顯示在應用程式摘要標籤中
- `resource`：此欄位下的所有連結將顯示在資源（deployments、pods、services 等）摘要標籤中

清單中的每個連結都有五個子欄位：

1. `title`：將在 UI 中顯示的與該連結對應的標題/標籤
2. `url`：深層連結將重新導向到的實際 URL，此欄位可以使用範本來使用來自相應應用程式、專案或資源物件的資料（取決於其位置）。這使用 [text/template](https://pkg.go.dev/text/template) 套件進行範本化
3. `description`（可選）：關於深層連結用途的描述
4. `icon.class`（可選）：在下拉式功能表中顯示連結時使用的 font-awesome 圖示類別
5. `if`（可選）：一個結果為 `true` 或 `false` 的條件陳述式，它也可以存取與 `url` 欄位相同的資料。如果條件解析為 `true`，則將顯示深層連結 - 否則將被隱藏。如果省略該欄位，預設情況下將顯示深層連結。這使用 [expr-lang/expr](https://github.com/expr-lang/expr/tree/master/docs) 來評估條件

> [!NOTE]
> 對於 Secret 類型的資源，資料欄位會被編輯，但其他欄位可用於範本化深層連結。

> [!WARNING]
> 請務必驗證 url 範本和輸入，以防止資料外洩或可能產生任何惡意連結。

如前所述，連結和條件可以被範本化以使用來自資源的資料，每個連結類別都可以存取連結到該資源的不同類型的資料。
總體而言，我們在系統中有以下 4 種資源可用於範本化：

- `app` 或 `application`：此鍵用於存取應用程式資源資料。
- `resource`：此鍵用於存取實際 k8s 資源的值。
- `cluster`：此鍵用於存取相關的目的地叢集資料，如名稱、伺服器、命名空間等。
- `project`：此鍵用於存取專案資源資料。

上述資源可在特定的連結類別中存取，以下是每個類別中可用的資源清單：

- `resource.links`：`resource`、`application`、`cluster` 和 `project`
- `application.links`：`app`/`application` 和 `cluster`
- `project.links`：`project`

一個包含深層連結及其變化的 `argocd-cm.yaml` 範例檔案：

```yaml
  # 專案層級連結範例
  project.links: |
    - url: https://myaudit-system.com?project={{.project.metadata.name}}
      title: Audit
      description: system audit logs
      icon.class: "fa-book"
  # 應用程式層級連結範例
  application.links: |
    # 使用 pkg.go.dev/text/template 評估 url 範本
    - url: https://mycompany.splunk.com?search={{.app.spec.destination.namespace}}&env={{.project.metadata.labels.env}}
      title: Splunk
    # 有條件地顯示連結，例如，對於特定專案
    # 使用 github.com/expr-lang/expr 評估條件
    - url: https://mycompany.splunk.com?search={{.app.spec.destination.namespace}}
      title: Splunk
      if: application.spec.project == "default"
    - url: https://{{.app.metadata.annotations.splunkhost}}?search={{.app.spec.destination.namespace}}
      title: Splunk
      if: app.metadata.annotations.splunkhost != ""
  # 資源層級連結範例
  resource.links: |
    - url: https://mycompany.splunk.com?search={{.resource.metadata.name}}&env={{.project.metadata.labels.env}}
      title: Splunk
      if: resource.kind == "Pod" || resource.kind == "Deployment"
    
    # 檢查是否存在包含 - 或 / 的標籤，以及如何以其他方式存取它的範例
    - url: https://mycompany.splunk.com?tag={{ index .resource.metadata.labels "some.specific.kubernetes.like/tag" }}
      title: Tag Service
      if: resource.metadata.labels["some.specific.kubernetes.like/tag"] != nil && resource.metadata.labels["some.specific.kubernetes.like/tag"] != ""
```
