## Argo CD 反模式檢查清單
1.  不理解 Argo CD 的宣告式設定 -> 將應用程式 CRD 儲存在 Git 中。
2.  建立動態的 Argo CD 應用程式 -> 使用 Git 作為應用程式配置的單一真實來源。
3.  使用 Argo CD 參數 -> 避免使用參數功能，因為它違反了 GitOps 原則。
4.  在不了解 Helm 的情況下採用 Argo CD -> 在採用 Argo CD 之前，先獨立了解 Helm 的運作方式。
5.  在不了解 Kustomize 的情況下採用 Argo CD -> 在與 Argo CD 整合之前，確保您的 Kustomize 檔案可以獨立運作。
6.  假設開發人員需要了解 Argo CD -> 設計您的 Argo CD 應用程式，以便開發人員可以在沒有 Argo CD 知識的情況下重新建立配置。
7.  在錯誤的抽象層級上對應用程式進行分組 -> 使用應用程式集或 app-of-apps 模式進行適當的應用程式分組。
8.  濫用 Argo CD 的多來源功能 -> 僅在邊緣情境下，並作為最後手段才使用多來源。
9.  不分割不同的 Git 儲存庫 -> 將原始碼、Kubernetes 清單和 Argo CD 應用程式清單分開到不同的 Git 儲存庫中。
10. 停用自動同步和自我修復 -> 為所有系統（包括生產環境）保持自動同步/自我修復啟用。
11. 濫用 targetRevision 欄位 -> 始終在 targetRevision 欄位中使用 HEAD。
12. 誤解容器/git 標籤和 Helm 圖表的不可變性 -> 積極設定生態系統（Git、Helm 儲存庫、成品管理器）以使用不可變的資料。
13. 給予開發人員過多（或完全沒有）權力 -> 使用 Argo CD RBAC 平衡靈活性和安全性，並在沒有 Argo CD 的情況下啟用本地測試。
14. 從 Argo CD/Kubernetes 清單中引用動態資訊 -> 將清單中使用的所有值靜態地儲存在 Git 中。
15. 編寫應用程式而非應用程式集 -> 使用應用程式集來自動化應用程式檔案的建立。
16. 使用 Helm 來打包應用程式而非應用程式集 -> 了解應用程式集如何運作及其功能。
17. 在 Argo CD 應用程式中硬式編碼 Helm 資料 -> 將所有 Helm 資訊儲存在 Helm values 中，與 Argo CD 清單分開。
18. 在 Argo CD 應用程式中硬式編碼 Kustomize 資料 -> 僅將 Kustomize 資訊儲存在與 Argo CD 清單分開的 Kustomize overlays 中。
19. 試圖對應用程式/應用程式集進行版本控制和推廣 -> 推廣 values 或 overlays，而不是應用程式清單本身。
20. 不了解哪些變更已應用於叢集 -> 使用工具或 CI 系統來預覽和比較渲染後的 Kubernetes 清單。
21. 使用臨時叢集而非叢集標籤 -> 使用叢集標籤和應用程式集將應用程式分發到不同的叢集。
22. 試圖使用單一應用程式集來處理所有事情 -> 擁有多個不同的應用程式集，每個都有不同的目的/範圍。
23. 使用 Pre-sync hooks 進行資料庫遷移 -> 使用專為 Kubernetes 打造的資料庫遷移運營商。
24. 將基礎設施應用程式與開發人員工作負載混合 -> 將基礎設施應用程式與開發人員工作負載分開。
25. 濫用 Argo CD finalizers -> 了解 finalizers 的工作原理，並正確地使用它們進行應用程式刪除和遷移。
26. 不了解資源追蹤 -> 了解 Argo CD 如何追蹤和採納 Kubernetes 資源。
27. 建立「active-active」的 Argo CD 安裝 -> 避免 active-active 設定，依靠 Git 和資源追蹤進行災難復原。
28. 用 Argo CD 和膠帶重新發明 Argo Rollouts -> 使用 Argo Rollouts 進行漸進式交付和自動回滾。
29. 用 Argo CD、sync-waves 和膠帶重新發明 Argo Workflows -> 使用 Argo Workflows 處理耗時較長的任務和複雜的流程協調。
30. 濫用 Argo CD 作為完整的 SDLC 平台 -> 使用不同的系統作為開發人員入口網站。