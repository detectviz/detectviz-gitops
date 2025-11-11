# 產生器

產生器負責產生**參數**，然後這些參數會被渲染到 ApplicationSet 資源的 `template:` 欄位中。有關產生器如何與範本協同工作以建立 Argo CD 應用程式的範例，請參閱[簡介](index.md)。

產生器主要基於它們用來產生範本參數的資料來源。例如：清單產生器從**文字清單**中提供一組參數，叢集產生器使用 **Argo CD 叢集清單**作為來源，Git 產生器使用來自 **Git 儲存庫**的檔案/目錄，等等。

截至本文撰寫時，共有九種產生器：

- [清單產生器](Generators-List.md)：清單產生器可讓您根據任何所選鍵/值元素對的固定清單，將 Argo CD 應用程式鎖定到叢集。
- [叢集產生器](Generators-Cluster.md)：叢集產生器可讓您根據 Argo CD 中定義（並由其管理）的叢集清單，將 Argo CD 應用程式鎖定到叢集（包括自動回應 Argo CD 的叢集新增/移除事件）。
- [Git 產生器](Generators-Git.md)：Git 產生器可讓您根據 Git 儲存庫中的檔案或 Git 儲存庫的目錄結構來建立應用程式。
- [矩陣產生器](Generators-Matrix.md)：矩陣產生器可用於結合兩個獨立產生器的產生參數。
- [合併產生器](Generators-Merge.md)：合併產生器可用於合併兩個或多個產生器的產生參數。額外的產生器可以覆寫基礎產生器的值。
- [SCM 提供者產生器](Generators-SCM-Provider.md)：SCM 提供者產生器使用 SCM 提供者（例如 GitHub）的 API 來自動發現組織內的儲存庫。
- [拉取請求產生器](Generators-Pull-Request.md)：拉取請求產生器使用 SCMaaS 提供者（例如 GitHub）的 API 來自動發現儲存庫中開啟的拉取請求。
- [叢集決策資源產生器](Generators-Cluster-Decision-Resource.md)：叢集決策資源產生器用於與 Kubernetes 自訂資源介面，這些資源使用自訂資源特定的邏輯來決定要部署到哪組 Argo CD 叢集。
- [插件產生器](Generators-Plugin.md)：插件產生器發出 RPC HTTP 請求以提供參數。

所有產生器都可以使用[後置選擇器](Generators-Post-Selector.md)進行篩選

如果您是產生器的新手，請從**清單**和**叢集**產生器開始。對於更進階的用例，請參閱上面其餘產生器的文件。
