# Grafana Loki 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 Grafana Loki 進行日誌聚合時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Loki 的具體部署、組態與標準化流程。

### 1.1 部署與架構

- **Helm Chart**: `grafana/loki-distributed`
- **部署方式**:
  - **Loki**: `gitops/apps/monitoring/loki.yaml` 搭配 `gitops/values/monitoring/loki.yaml`，以 Helm multi-source 管理覆寫值並透過 ArgoCD 同步。
- **命名空間**: 所有元件**必須**部署在 `monitoring` 命名空間。
- **部署方式**: 透過 ArgoCD 進行 GitOps 同步，並使用 `gitops/values/monitoring/` 目錄下的 `loki.yaml` 進行組態覆寫。
- **架構**:
  - 採用**分散式 (distributed)** 架構，將讀取、寫入、後端等不同職責拆分為獨立的微服務元件 (e.g., ingester, distributor, querier)。
  - **Gateway**: `loki-gateway` 作為所有 API 請求的統一入口點。

### 1.2 高可用性 (HA)

- **副本數**: 所有關鍵的 stateful 元件 (如 `ingester`, `distributor`, `querier`) **必須**以至少 2 個副本部署 (`replicas: 2`)，以確保服務在節點故障時的可用性。
- **Loki Replica 與儲存**: 各 Stateful 元件維持 `replicas: 2`，並使用 `storageClass: detectviz-sata` 將長期日誌存放於 SATA 備份池。
- **服務發現與集群**:
  - **必須**使用 `memberlist` 來進行 ingester 之間的 gossip 協議和服務發現。
  - `memberlist.join_members` **必須**設定為指向 headless service，例如 `[mimir-ingester-headless.monitoring.svc.cluster.local:7946]`。

### 1.3 儲存 (Storage)

- **後端儲存 (Backend Storage)**:
  - Loki 的長期資料 (chunks) **必須**儲存在基於檔案系統 (`filesystem`) 的後端。
  - **Provisioner**: 這些資料的 PVC **必須**使用 `detectviz-sata` StorageClass。
  - **Host Path**: `detectviz-sata` 對應到 Proxmox 節點上的 `/mnt/sata-backup` 目錄，將長期儲存與高效能的 NVMe 磁碟隔離。
- **本地快取 (Caching)**:
  - 建議為 `querier`, `store-gateway` 等元件啟用本地檔案系統快取，以加速查詢效能。這些快取可以存放在 Pod 的 `emptyDir` 中。

### 1.4 資料接收 (Ingestion)

- **整合**: Loki 透過 `loki-gateway` 接收 Alloy `loki.write` 推送的節點與應用日誌，需驗證 `tenant ID` 與 Alloy `locals.loki_tenant` 一致，Grafana Datasource 指向同一 Gateway 以供查詢與警示關聯。
- **入口**: 保留多租戶 `tenant ID`（與 Alloy `locals.loki_tenant` 相符），支援平台與 AI 插件以標籤隔離日誌。
- **日誌收集代理**: **必須**使用 Grafana Alloy 作為日誌收集代理。Alloy 以 DaemonSet 形式部署在每個節點上。
- **Alloy 組態**: Alloy 負責從 Pods (stdout/stderr) 和 systemd journal 收集日誌，並將其轉發到 Loki 的 distributor。
- **租戶 (Tenant)**: 所有日誌**必須**被分配一個租戶 ID (e.g., `detectviz-prod`)，該 ID 在 Alloy 的設定 (`loki.write`) 中進行配置。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Loki 時應遵循的最佳實踐。

### 2.1 查詢效能優化

- **限定時間範圍**: 在 Grafana 或 API 中查詢時，務必指定明確且合理的時間範圍。避免對過長的時間範圍進行無限制的查詢。
- **Loki - 標籤選擇器 (Label Selectors)**:
  - **先標籤，後過濾**: Loki 的查詢效能高度依賴於標籤。查詢的第一步應盡可能使用標籤選擇器 (`{app="grafana", namespace="monitoring"}`) 來縮小日誌流的範圍。
  - **避免高基數標籤**: 與 Prometheus 類似，**嚴禁**在 Loki 的日誌標籤中使用高基數的值 (如 `traceID`, `userID`)。這些資訊應作為日誌行的一部分，而不是標籤。
  - **使用過濾表達式**: 對日誌內容的全文搜索應使用過濾表達式 (`|= "error"`, `|~ "status=5.."`), 這樣查詢引擎只需在第一步篩選出的日誌流中進行搜索。
  - **日誌標籤設計**: 設計日誌標籤時僅索引必要 metadata（如租戶、服務、環境），降低查詢成本並符合 Loki 以 label 查詢的原則。若需擴充規模，可依簡單可擴展模式拆分讀寫路徑，確保在 Kubernetes 上能獨立擴容。多租戶部署時需在 Agent（Grafana Alloy/Promtail）設定 `tenant ID`，確保日誌隔離並搭配 Grafana 進行跨資料源關聯。

### 2.2 儲存管理

- **保留策略 (Retention Policy)**:
  - **必須**為 Loki 設定合理的資料保留策略 (`retention_period`)，例如 `30d` (30天)。
  - 過長的保留期會導致儲存成本和查詢延遲的增加。
- **Compactor**:
  - Loki 包含 `compactor` 元件，負責將小的 chunks 合併為更大的、索引更優化的塊。
  - **必須**確保 `compactor` 正常運行，這是維持查詢效能和降低儲存空間佔用的關鍵。
- **監控儲存用量**:
  - 監控 PVC 的磁碟使用率，並設定告警，以防止因磁碟空間耗盡導致的資料寫入失敗。

### 2.3 可觀測性

- **監控 Loki 自身**:
  - Loki 的所有元件都會暴露 Prometheus 格式的指標。
  - **必須**設定 `ServiceMonitor` 來抓取這些指標，並使用官方提供的 Grafana 儀表板來監控其內部狀態 (如請求延遲、錯誤率、隊列長度、ingester 記憶體使用率等)。
- **關鍵告警**:
  - **Ingester Rollout**: 監控 ingester 的滾動更新是否健康。
  - **High Write Error Rate**: 監控寫入路徑的錯誤率。
  - **Query Timeout/Error Rate**: 監控查詢路徑的超時或錯誤率。
  - **Compactor Health**: 監控 compactor 是否卡住或失敗。

### 2.4 安全性

- **租戶隔離 (Multi-tenancy)**:
  - Loki 內建了多租戶支援。即使在單一叢集環境中，也建議為不同的環境或應用設定不同的租戶 ID。
  - 這為未來的擴展提供了靈活性，並能在邏輯上隔離資料。
- **Gateway 認證**:
  - 在需要對外暴露 Loki API 的場景中，**必須**在 Gateway 層 (Nginx) 設定認證機制，如 Basic Auth 或 OAuth2。