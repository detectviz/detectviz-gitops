# 新增額外的應用程式資訊

您可以在您的 Argo CD 儀表板上為應用程式新增額外資訊。
如果您希望新增可點擊的連結，請參閱[新增外部 URL](https://argo-cd.readthedocs.io/en/stable/user-guide/external-url/)。

這可以透過在您的應用程式資訊清單中為 'info' 欄位提供一個鍵值對來完成。

範例：
```yaml
project: argo-demo
source:
  repoURL: 'https://demo'
  path: argo-demo
destination:
  server: https://demo
  namespace: argo-demo
info:
  - name: Example:
    value: >-
      https://example.com
```
![外部連結](../assets/extra_info-1.png)

額外的資訊將會在 Argo CD 應用程式詳細資料頁面上顯示。

![外部連結](../assets/extra_info.png)

![外部連結](../assets/extra_info-2.png)
