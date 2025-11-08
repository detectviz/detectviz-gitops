# 在 Argo CD UI 中擴展資源

此功能讓使用者能直接從 Argo CD UI 擴展資源。使用者將能夠透過輸入欄位來增加或減少 Deployment 和 StatefulSet 的副本（Pod）數量。此功能旨在提升使用者體驗，特別是對於非技術使用者，無需修改設定檔或使用 kubectl 指令即可進行擴展。

## 使用範例
1. 使用者在任何 Argo CD 應用程式中導覽至 Deployment 或 StatefulSet。
2. 使用者點擊「動作」下拉式選單並選擇「擴展」。
  ![用於擴展的動作按鈕](../assets/scale_resources_1.png)
3. 彈出一個對話框，顯示一個輸入欄位 `輸入動作的參數：擴展`，其中包含目前的 Pod 數量。
4. 使用者透過輸入數字來調整 Pod 數量。
  ![用於擴展的輸入欄位](../assets/scale_resources_2.png)
5. 使用者按下「確定」，資源將相應地進行擴展。
  ![擴展結果](../assets-jp/scale_resources_3.png)

> [!NOTE]
> 此功能僅適用於 `Deployments` 和 `StatefulSets`。

> [!NOTE]
> 如果您使用 HPA（Horizontal Pod Autoscaling）或啟用 Argo CD 自動同步，在擴展動作中變更的副本計數將被覆寫。
> 確保無法輸入無效值（例如，`非數字`字元、`負數`或超出`最大整數限制`的值）。
