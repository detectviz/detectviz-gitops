# 狀態徽章

Argo CD 可以為任何應用程式顯示一個包含健康狀態和同步狀態的徽章。此功能預設為停用，因為徽章圖片可供任何使用者在未經身份驗證的情況下使用。
可以使用 `argocd-cm` ConfigMap 的 `statusbadge.enabled` 金鑰來啟用此功能（請參閱 [argocd-cm.yaml](../operator-manual/argocd-cm-yaml/)）。


![健康且已同步](../assets/status-badge-healthy-synced.png)

若要顯示此徽章，請使用以下 URL 格式 `${argoCdBaseUrl}/api/badge?name=${appName}`，例如 http://localhost:8080/api/badge?name=guestbook。

若要覆寫 `${argoCdBaseUrl}` 值，您可以使用 `argocd-cm` ConfigMap 的 `statusbadge.url` 金鑰。

狀態圖片的 URL 可在應用程式詳細資料頁面上取得：

1. 導覽至應用程式詳細資料頁面，然後按一下「詳細資料」按鈕。
2. 向下捲動至「狀態徽章」部分。
3. 選擇所需的範本，例如 URL、Markdown 等。
   狀態圖片的 URL 範本，適用於 markdown、html 等。
4. 複製文字並將其貼到您的 README 或網站中。

## 其他查詢參數選項

### showAppName

在狀態徽章中顯示應用程式名稱。

可用值：`true/false`

預設值：`false`

範例：`&showAppName=true`

### revision

顯示應用程式所針對的修訂版本。

它還會將徽章寬度擴展到 192px。

在多個來源的設定中，將顯示第一個定義來源的修訂版本。

可用值：`true/false`

預設值：`false`

範例：`&revision=true`

### keepFullRevision

預設情況下，顯示的修訂版本會被截斷為 7 個字元。

如果長度超過該長度，此參數允許完整顯示它。

它還會將徽章寬度擴展到 400px。

可用值：`true/false`

預設值：`false`

範例：`&keepFullRevision=true`

### width

變更徽章的寬度。

完全取代目前計算的寬度。

可用值：`integer`

預設值：`nil`

範例：`&width=500`
