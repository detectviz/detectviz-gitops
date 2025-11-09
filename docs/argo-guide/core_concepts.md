# 核心概念

我們假設您熟悉 Git、Docker、Kubernetes、持續交付和 GitOps 的核心概念。
以下是一些 Argo CD 特有的概念。

*   **應用程式 (Application)**：由清單 (manifest) 定義的一組 Kubernetes 資源。這是一個自訂資源定義 (Custom Resource Definition, CRD)。
*   **應用程式來源類型 (Application source type)**：用來建置應用程式的**工具**。
*   **目標狀態 (Target state)**：應用程式的期望狀態，由 Git 儲存庫中的檔案表示。
*   **即時狀態 (Live state)**：該應用程式的即時狀態。部署了哪些 pod 等。
*   **同步狀態 (Sync status)**：即時狀態是否符合目標狀態。已部署的應用程式是否與 Git 中所說的應該有的狀態相同？
*   **同步 (Sync)**：使應用程式移動到其目標狀態的過程。例如，透過將變更應用於 Kubernetes 叢集。
*   **同步操作狀態 (Sync operation status)**：同步是否成功。
*   **重新整理 (Refresh)**：將 Git 中的最新程式碼與即時狀態進行比較。找出有何不同。
*   **健康狀態 (Health)**：應用程式的健康狀況，它是否正常執行？它能否處理請求？
*   **工具 (Tool)**：一個從檔案目錄建立清單的工具。例如，Kustomize。請參閱**應用程式來源類型**。
*   **組態管理工具 (Configuration management tool)**：請參閱**工具**。
*   **組態管理外掛程式 (Configuration management plugin)**：一個自訂工具。