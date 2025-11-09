# PostgreSQL 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 PostgreSQL 作為結構化資料儲存時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 PostgreSQL 的具體部署、組態與標準化流程。

### 1.1 PostgreSQL

- **Helm Chart**: `bitnami/postgresql-ha`
- **命名空間**: `detectviz`
- **部署方式**: 透過 `gitops/apps/postgresql.yaml` 由 ArgoCD 進行 GitOps 同步。
- **架構**:
  - **PostgreSQL**: 以 `StatefulSet` 部署，**必須**包含 1 個主節點 (Primary) 和 2 個備節點 (Read Replicas)，共 3 個副本 (`postgresql.replicaCount: 3`)。
  - **Pgpool**: 作為連線池與負載均衡器，以 `Deployment` 部署，**必須**包含 2 個副本 (`pgpool.replicaCount: 2`)。
- **儲存 (Storage)**:
  - **StorageClass**: **必須**使用 `detectviz-nvme`，確保高 I/O 效能。
  - **持久化**: 每個 PostgreSQL 副本都將掛載獨立的 PVC。
- **密碼管理**:
  - **嚴禁**在 `values.yaml` 中使用明文密碼。
  - 所有密碼**必須**透過預先建立的 Kubernetes Secrets 進行管理：
    - `detectviz-postgresql-admin`: 儲存 PostgreSQL 管理員與使用者密碼。
    - `detectviz-pgpool-users`: 儲存 Pgpool 使用的密碼檔案 (`pgpool_passwd`)。
  - 初始資料庫與使用者 (如 Grafana 所需) 應透過 `detectviz-postgresql-initdb` Secret 中的初始化 SQL 腳本建立。
- **可觀測性**:
  - **必須**啟用 `metrics.serviceMonitor: true`，以便 kube-prometheus-stack 可以自動發現並抓取 PostgreSQL 的指標。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在 Kubernetes 環境中管理 PostgreSQL 時應遵循的最佳實踐。

### 2.1 備份與恢復 (Backup & Recovery)

- **PostgreSQL**:
  - **強烈建議**部署一個備份工具 (如 `pgBackRest` 或 `Velero`) 來執行定期的物理或邏輯備份。
  - **備份策略**:
    - **每日**執行一次全量備份 (Full Backup)。
    - **持續**進行 WAL (Write-Ahead Log) 歸檔，以實現時間點恢復 (Point-in-Time Recovery, PITR)。
  - **備份儲存**: 備份檔案應儲存在叢集外部的對象儲存 (Object Storage) 或 NFS 中。
- **恢復演練**: 應定期進行恢復演練，以確保備份的有效性與恢復流程的順暢。

### 2.2 資源管理

- **設定 Requests and Limits**:
  - 資料庫是對資源 (特別是 Memory 和 I/O) 非常敏感的應用。
  - **必須**為 PostgreSQL 的 Pod 設定明確的 CPU 和 Memory `requests` 與 `limits`。
  - **QoS Class**: 建議將 `requests` 和 `limits` 設定為相等的值，使 Pod 獲得 `Guaranteed` 的 QoS 等級，確保其在節點資源緊張時不會被優先驅逐。
- **記憶體配置**:
  - **PostgreSQL**: 應根據負載仔細調整 `postgresql.conf` 中的 `shared_buffers` 和 `work_mem` 等參數，以優化記憶體使用。

### 2.3 連線管理

- **PostgreSQL**:
  - 所有應用程式**必須**透過 Pgpool 的 `Service` (`<release-name>-pgpool`) 連線到 PostgreSQL 叢集，而不應直接連線到主節點或備節點。
  - Pgpool 負責處理連線池、負載均衡 (將讀請求路由到備節點) 和自動故障轉移。
- **應用程式端**:
  - 應用程式應使用合理的連線池大小，避免開啟過多閒置連線，耗盡資料庫資源。

### 2.4 安全性

- **網路策略 (NetworkPolicy)**:
  - **必須**使用 NetworkPolicy 限制對資料庫的存取。
  - 只有 `layer: web` 和 `layer: llm` 的 Pod 才被允許連線到 `layer: data` 的 PostgreSQL。
- **TLS 加密**:
  - 在生產環境中，**強烈建議**啟用 PostgreSQL 的 TLS 功能，對客戶端與伺服器之間、以及主備節點之間的複製流量進行加密。
- **資料庫權限**:
  - 遵循最小權限原則。為每個應用建立專屬的資料庫使用者，並僅授予其存取所需資料庫和表的權限。

### 2.5 升級與維護

- **PostgreSQL**:
  - **版本升級**: PostgreSQL 的主版本升級通常需要停機和 `pg_upgrade` 操作，應謹慎規劃。
  - **次版本升級**: 次版本升級 (e.g., 14.1 -> 14.2) 通常是滾動更新 Pgpool 和 PostgreSQL 副本即可。
- **監控**:
  - 除了 `ServiceMonitor` 提供的基礎指標外，還應關注關鍵的資料庫指標，如：
    - 查詢延遲 (Query Latency)
    - 交易吞吐量 (Transaction Throughput)
    - 索引命中率 (Index Hit Rate)
    - 複寫延遲 (Replication Lag)
  - 為這些關鍵指標設定告警。