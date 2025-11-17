# DetectViz Platform Constitution

> 依據過去的部署失敗紀錄、近期待辦的修正紀錄與過去架構審查發現的結構性問題，制定下列守則以約束未來的 IaC / GitOps 變更，避免反覆在配置調整上耗費過多心力。

| # | 原則類型 | 關鍵價值 | 不可違背的規範 |
|---|-----------|-----------|------------------|
| 1 | 技術 | 模組化 | **MUST**：所有 Argo CD Application 必須以 Kustomize base/overlay 分離共用與環境設定；禁止在 base 直接引入特定環境 Helm values，避免再度發生 observability apps 共用錯誤設定的問題。 |
| 2 | 技術 | 可維護 | **MUST**：ApplicationSet 生成的每個應用都要明確宣告 `CreateNamespace=true` 或在 bootstrap manifest 中建立命名空間，確保 app-depoly.log 中的 `namespaces not found` 錯誤不再重演。 |
| 3 | 技術 | 可測試 | **MUST**：在提交前執行 `kustomize build --enable-helm` 並檢查 ExternalSecret、Helm values 是否被套用；如遇環境無法下載 Helm，需附上替代驗證證據，避免無效 patch 悄悄混入。 |
| 4 | 技術 | 可維護 | **MUST**：所有 nodeSelector、tolerations、storageClass 需求需直接寫入 Helm `values.yaml` 或正確對應的 Kubernetes manifest，禁止再使用 Flux 專用 patch stub。 |
| 5 | 技術 | 安全 | **MUST**：所有密碼與敏感設定一律經 Vault KV v2 + External Secrets Operator 管理；任何想在 manifest 內嵌密碼的需求都要被拒絕，並回報為 SOP 偏離。 |
| 6 | 文化 | 模組化 | **SHOULD**：變更需同步更新 README、infra-deploy-sop.md、app-deploy-sop.md 等文檔，確保操作流程與代碼一致，避免後續輪班工程師按過期指引操作。 |
| 7 | 文化 | 可維護 | **SHOULD**：PR 描述需標註受影響的應用、命名空間與部署順序調整，以利 AI / 人類 reviewer 快速判斷依賴關係是否被破壞。 |
| 8 | 文化 | 可測試 | **MUST**：app-deploy.log 若指出錯誤，需先追溯 SOP 與 manifest 的落差，寫在修復紀錄中並回饋到 constitution，如本文件，形成可審查的閉環。 |

> 檢查任務時，若需求違反上述憲章（例如要求跳過 Vault、直接修改 base Helm chart、或忽略文檔同步），AI 應主動標記並拒絕，確保 DetectViz 平台維持一致、可預測且可審核的 GitOps 實踐。
