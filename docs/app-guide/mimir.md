# Grafana Mimir 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 Grafana Mimir 進行指標長期儲存時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Mimir 的具體部署、組態與標準化流程。

### 1.1 部署與架構

- **Helm Chart**: `grafana/mimir-distributed`
- **部署方式**:
  - **Mimir**: `gitops/apps/monitoring/mimir.yaml` 搭配 `gitops/values/monitoring/mimir.yaml`，維持 Helm multi-source 結構與 ArgoCD 同步。
- **命名空間**: 所有元件**必須**部署在 `monitoring` 命名空間。
- **部署方式**: 透過 ArgoCD 進行 GitOps 同步，並使用 `gitops/values/monitoring/` 目錄下的 `mimir.yaml` 進行組態覆寫。
- **架構**:
  - 採用**分散式 (distributed)** 架構，將讀取、寫入、後端等不同職責拆分為獨立的微服務元件 (e.g., ingester, distributor, querier)。
  - **Gateway**: `mimir-nginx` 作為所有 API 請求的統一入口點。

### 1.2 高可用性 (HA)

- **副本數**: 所有關鍵的 stateful 元件 (如 `ingester`, `distributor`, `querier`) **必須**以至少 2 個副本部署 (`replicas: 2`)，以確保服務在節點故障時的可用性。
- **Mimir Replica 與儲存**: 設定 `replicas: 2`（Distributor/Ingester/Store Gateway 等組件）並指向 `storageClass: detectviz-sata` 以使用 SATA 備份池承載長期指標。
- **服務發現與集群**:
  - **必須**使用 `memberlist` 來進行 ingester 之間的 gossip 協議和服務發現。
  - `memberlist.join_members` **必須**設定為指向 headless service，例如 `[mimir-ingester-headless.monitoring.svc.cluster.local:7946]`。

### 1.3 儲存 (Storage)

- **後端儲存 (Backend Storage)**:
  - Mimir 的長期資料 (TSDB blocks) **必須**儲存在基於檔案系統 (`filesystem`) 的後端。
  - **Provisioner**: 這些資料的 PVC **必須**使用 `detectviz-sata` StorageClass。
  - **Host Path**: `detectviz-sata` 對應到 Proxmox 節點上的 `/mnt/sata-backup` 目錄，將長期儲存與高效能的 NVMe 磁碟隔離。
- **本地快取 (Caching)**:
  - 建議為 `querier`, `store-gateway` 等元件啟用本地檔案系統快取，以加速查詢效能。這些快取可以存放在 Pod 的 `emptyDir` 中。

### 1.4 資料接收 (Ingestion)

- **網路**: 透過 `mimir-nginx` 暴露 Remote Write URL，Prometheus 及其他客戶端須指向該 LoadBalancer/ClusterIP。
- **整合**: 接收來自 kube-prometheus-stack Prometheus 的 Remote Write 流量，需在 `mimir.yaml` 開啟 `ingester.ingestion_rate` 限制，並確認 Grafana Datasource 指向 `http://detectviz-mimir-query-frontend.monitoring:80`；與 Vault `detectviz-mimir-tls` Secret 對應 Remote Write 憑證。
- Mimir **必須**作為 Prometheus Server 的唯一 `remoteWrite` 端點。
- 所有來自 Prometheus 的指標都應包含 `cluster` 和 `environment` 等 `externalLabels`，以便在 Mimir 中進行多叢集區隔。
- **租戶 (Tenant)**: 預設使用 `anonymous` 租戶。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Mimir 時應遵循的最佳實踐。

### 2.1 查詢效能優化

- **限定時間範圍**: 在 Grafana 或 API 中查詢時，務必指定明確且合理的時間範圍。避免對過長的時間範圍進行無限制的查詢。
- **Mimir - 錄製規則與聯邦**:
  - 將常用的、複雜的查詢製作成 Prometheus 的錄製規則，Mimir 會自動從遠端寫入的指標中繼承這些優化。
  - **Mimir 安裝前置條件**: 安裝前需符合 Kubernetes 1.29+、Helm 3.8+、具備預設 StorageClass 及 DNS 服務；若部署於受限環境，需禁用內建 MinIO 並改用外部儲存。建議在專用 namespace 內安裝並使用 `helm repo add grafana https://grafana.github.io/helm-charts`、`helm install mimir grafana/mimir-distributed` 方式測試後，再導入 GitOps。
  - **KEDA/HPA 自動擴容**: 導入 KEDA/HPA autoscaling 時，依官方建議先啟用 `preserveReplicas: true`，待 HPA 接手後再移除，並在非生產環境演練。
  - **Vault TLS 憑證注入**: 若需 Vault Agent 注入 TLS 憑證，應在各組件（如 `ingester`, `gateway`）加上 `vault.hashicorp.com/agent-inject-secret-*` 與 `agent-inject-template-*` annotations，並確認 Vault 先行啟動。

### 2.2 儲存管理

- **保留策略 (Retention Policy)**:
  - **必須**為 Mimir 設定合理的資料保留策略 (`retention_period`)，例如 `30d` (30天)。
  - 過長的保留期會導致儲存成本和查詢延遲的增加。
- **Compactor**:
  - Mimir 包含 `compactor` 元件，負責將小的 TSDB blocks 合併為更大的、索引更優化的塊。
  - **必須**確保 `compactor` 正常運行，這是維持查詢效能和降低儲存空間佔用的關鍵。
- **監控儲存用量**:
  - 監控 PVC 的磁碟使用率，並設定告警，以防止因磁碟空間耗盡導致的資料寫入失敗。

### 2.3 可觀測性

- **監控 Mimir 自身**:
  - Mimir 的所有元件都會暴露 Prometheus 格式的指標。
  - **必須**設定 `ServiceMonitor` 來抓取這些指標，並使用官方提供的 Grafana 儀表板來監控其內部狀態 (如請求延遲、錯誤率、隊列長度、ingester 記憶體使用率等)。
- **關鍵告警**:
  - **Ingester Rollout**: 監控 ingester 的滾動更新是否健康。
  - **High Write Error Rate**: 監控寫入路徑的錯誤率。
  - **Query Timeout/Error Rate**: 監控查詢路徑的超時或錯誤率。
  - **Compactor Health**: 監控 compactor 是否卡住或失敗。

### 2.4 安全性

- **租戶隔離 (Multi-tenancy)**:
  - Mimir 內建了多租戶支援。即使在單一叢集環境中，也建議為不同的環境或應用設定不同的租戶 ID。
  - 這為未來的擴展提供了靈活性，並能在邏輯上隔離資料。
- **Gateway 認證**:
  - 在需要對外暴露 Mimir API 的場景中，**必須**在 Gateway 層 (Nginx) 設定認證機制，如 Basic Auth 或 OAuth2。
