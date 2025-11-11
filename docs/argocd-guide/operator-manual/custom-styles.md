# 自訂樣式

Argo CD 的大部分 UI 樣式表都從 [argo-ui](https://github.com/argoproj/argo-ui) 專案匯入。
有時，為了品牌目的或為了幫助區分在不同環境中執行的多個 Argo CD 執行個體，可能需要自訂 UI 的某些元件。

此類自訂樣式可以透過提供遠端託管 CSS 檔案的 URL，或直接將 CSS 檔案載入到 argocd-server 容器中來應用。這兩種機制都由修改 argocd-cm configMap 驅動。

## 透過遠端 URL 新增樣式

第一種方法僅需要在 argocd-cm configMap 中新增遠端 URL：

### argocd-cm
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  ...
  name: argocd-cm
data:
  ui.cssurl: "https://www.example.com/my-styles.css"
```

## 透過磁碟區掛載新增樣式

第二種方法需要將 CSS 檔案直接掛載到 argocd-server 容器上，然後
為 argocd-cm 提供指向該檔案的正確設定路徑。在以下範例中，
CSS 檔案實際上定義在一個單獨的 configMap 中（透過在 initContainer 中產生或下載 CSS 檔案也可以達到相同的效果）：

### argocd-cm
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  ...
  name: argocd-cm
data:
  ui.cssurl: "./custom/my-styles.css"
```

請注意，`cssurl` 應相對於 `/shared/app` 目錄指定；
而不是絕對路徑。

### argocd-styles-cm
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  ...
  name: argocd-styles-cm
data:
  my-styles.css: |
    .sidebar {
      background: linear-gradient(to bottom, #999, #777, #333, #222, #111);
    }
```

### argocd-server
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
  ...
spec:
  template:
    ...
    spec:
      containers:
      - command:
        ...
        volumeMounts:
        ...
        - mountPath: /shared/app/custom
          name: styles
      ...
      volumes:
      ...
      - configMap:
          name: argocd-styles-cm
        name: styles
```

請注意，CSS 檔案應掛載在 `/shared/app` 目錄的子目錄中
（例如 `/shared/app/custom`）。否則，瀏覽器很可能會因為「不正確的 MIME 類型」錯誤而無法匯入該檔案。
可以使用 [argocd-cmd-params-cm.yaml](./argocd-cmd-params-cm.yaml) ConfigMap 的 `server.staticassets` 鍵來變更子目錄。

## 開發樣式覆蓋
注入的 CSS 檔案中指定的樣式應特定於 [argo-ui](https://github.com/argoproj/argo-ui) 中定義的元件和類別。
建議您先利用瀏覽器內建的開發人員工具來測試您希望應用的樣式。若要獲得功能更全面的體驗，
您可能希望使用 [Argo CD UI 開發伺服器](https://webpack.js.org/configuration/dev-server/) 來建置一個單獨的專案。

## 橫幅

Argo CD 可以選擇性地顯示一個橫幅，可用於通知您的使用者即將進行的維護和操作變更。此功能可以透過在 `argocd-cm` ConfigMap 中使用 `ui.bannercontent` 欄位指定橫幅訊息來啟用，Argo CD 將在每個 UI 頁面的頂部顯示此訊息。您可以選擇性地透過設定 `ui.bannerurl` 為此訊息新增連結。您還可以透過將 `ui.bannerpermanent` 設定為 true 來使橫幅具有黏性（永久），並透過使用 `ui.bannerposition: "both"` 將其位置變更為「兩者」或「底部」，讓橫幅顯示在頂部和底部，或使用 `ui.bannerposition: "bottom"` 讓它專門顯示在底部。

### argocd-cm
```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  ...
  name: argocd-cm
data:
    ui.bannercontent: "連結到 URL 的橫幅訊息"
    ui.bannerurl: "www.bannerlink.com"
    ui.bannerpermanent: "true"
    ui.bannerposition: "bottom"
```

![帶有連結的橫幅](../assets/banner.png)
