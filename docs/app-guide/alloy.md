# Grafana Alloy 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 Grafana Alloy 作為日誌與指標收集代理時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Alloy 的具體部署、組態與標準化流程。

### 1.1 部署與架構

- **部署模式**: Grafana Alloy **必須**以 `DaemonSet` 的方式部署在 `monitoring` 命名空間。
- **部署來源**: `apps/alloy/overlays/production` 以 Kustomize 建立 DaemonSet，並透過環境變數（`CLUSTER_NAME`、`LOKI_TENANT`）配置動態值。
- **Namespace 與節點**: DaemonSet 覆蓋所有節點，需確認 Phase 2.5 已套用推薦節點標籤，以便 `prometheus-node-exporter` relabelings 正確解析。
- **目的**: 確保每個 Kubernetes 節點上都有一個 Alloy 實例在運行，負責收集該節點上的日誌與指標。
- **部署方式**: 透過 `gitops/apps/monitoring/alloy.yaml` 由 ArgoCD 進行 GitOps 同步。

### 1.2 組態管理

- **設定檔**: Alloy 的核心設定檔 `config.alloy` **必須**使用 Kustomize 進行管理。
  - **Base 配置**: `apps/alloy/base/config.alloy`
  - **Production Overlay**: `apps/alloy/overlays/production/config.alloy`
  - **最終產物**: Kustomize 會將此檔案生成為一個名為 `alloy-config` 的 `ConfigMap`。
- **動態變數**:
  - **重要**：Grafana Alloy 使用 River 配置語言，**不支持 `locals` 區塊**。
  - 環境特定變數（如 `cluster_name`、`loki_tenant`）**必須**透過 DaemonSet 的環境變數注入：
    - `CLUSTER_NAME`: Kubernetes 叢集名稱
    - `LOKI_TENANT`: Loki 租戶 ID
    - `NODE_SELECTOR`: 節點過濾器（預設: `.*`）
  - 在 `config.alloy` 中使用 `env("CLUSTER_NAME")` 和 `coalesce()` 函數讀取環境變數。
  - 這些值應與 Terraform 和其他平台組態保持一致。
- **掛載**: `alloy-config` ConfigMap **必須**被掛載到 Alloy DaemonSet 的 Pod 中。

### 1.3 日誌收集 (Logs)

- **核心管線 (Pipeline)**:
  1.  **`loki.source.kubernetes`**:
      - **用途**: 發現節點上所有正在運行的 Pods，並從中抓取日誌。
      - **`forward_to`**: **必須**將日誌轉發到後續的處理階段 (relabeling)。
  2.  **`loki.relabel`**:
      - **用途**: 對抓取到的日誌流 (log streams) 進行標籤的修改、添加或刪除。
      - **規則**: 應包含移除過高基數標籤 (如 `pod_template_hash`) 和添加元數據標籤 (如 `cluster`) 的規則。
  3.  **`loki.write`**:
      - **用途**: 將處理過的日誌發送到 Loki。
      - **`endpoint`**: **必須**指向 Loki distributor/gateway 的地址 (`http://loki-gateway.monitoring.svc:80/loki/api/v1/push`)。
      - **`tenant_id`**: **必須**設定為 `locals.loki_tenant` 的值，以確保多租戶隔離。
- **整合**: `config.alloy` 需透過 `loki.write` 將 Logs 推送到 `http://detectviz-loki-gateway.monitoring:3100/loki/api/v1/push`；Grafana 透過 Loki Datasource 讀取，同步完成告警回饋。

### 1.4 指標收集 (Metrics)

- **Prometheus 兼容**: Alloy 可以抓取 Prometheus 格式的指標，並將其遠端寫入 (remote write) 到 Prometheus 兼容的後端 (如 Mimir)。
- **整合**: `config.alloy` 需透過 `exporters.prometheus.remote_write` 將節點 Metrics 寫入 `http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write`，並用 `loki.write` 將 Logs 推送到 `http://detectviz-loki-gateway.monitoring:3100/loki/api/v1/push`；Grafana 透過 Loki Datasource 讀取，同步完成告警回饋。
- **使用場景**: 在 Detectviz 平台中，`kube-prometheus-stack` 中的 Prometheus Server 負責主要的指標抓取。Alloy 主要用於日誌收集，但保留了未來擴展指標收集任務的能力 (例如，收集本地節點上 Prometheus Server 無法直接訪問的目標)。

### 1.5 權限 (Permissions)

- **ServiceAccount**: Alloy 的 DaemonSet **必須**使用一個專屬的 `ServiceAccount`。
- **ClusterRole**: 該 `ServiceAccount` **必須**綁定到一個 `ClusterRole`，授予其訪問 Kubernetes API 所需的最小權限，主要包括：
  - `list` 和 `watch` `pods`, `nodes`, `services`。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Grafana Alloy 時應遵循的最佳實踐。

### 2.1 組態與管線 (Configuration & Pipelines)

- **模組化與可讀性**:
  - `config.alloy` 應編寫清晰的註解，並將不同功能的區塊 (如日誌收集、指標收集) 分隔開。
  - 對於複雜的管線，可以將 `relabel` 規則拆分成多個 `loki.relabel` 元件，形成一個處理鏈，每個元件只負責一項單純的任務。
- **除錯模式 (Debugging)**:
  - Alloy 提供了一個內建的 UI，用於視覺化管線、檢查元件狀態和除錯。
  - 在開發或排查問題時，可以透過 `kubectl port-forward` 訪問 Alloy Pod 的 `12345` 端口來使用此 UI。
- **版本控制**: 將 `config.alloy` 納入 GitOps 管理，確保所有變更都經過審查且可追蹤。
- **遙測設定**: 若不需匿名遙測，可在啟動參數加入 `--disable-reporting`（Kustomize 可透過 env 或 args 設定），以符合法規或內部政策。
- **Vault 整合**: 透過 `remote.vault` 元件與 Vault 整合時，需指定 `server`、適當的 `auth.*`（如 `auth.kubernetes`）以及 `client_options`，以自動抓取憑證並暴露為 Alloy Secret。

### 2.2 效能與資源管理

- **資源限制**:
  - 作為 DaemonSet，Alloy 在每個節點上都會運行。**必須**為其容器設定合理的 CPU 和 Memory `requests` 與 `limits`，以防止其過度消耗節點資源。
  - **資源請求建議**: 在 Grafana Mimir 安裝流程中，官方建議於專屬 namespace 建立 Alloy 並配置 `resources.requests`、`limits`，確保收集器穩定運作。
- **避免高基數標籤**:
  - 日誌標籤是 Loki 效能的關鍵。在 `loki.relabel` 階段，**必須**積極地移除所有潛在的高基數標籤 (例如 `controller-revision-hash`, `pod-template-hash`)。
  - 只保留用於索引和查詢的關鍵標籤，如 `namespace`, `app`, `component`, `job`。
- **本地儲存 (WAL)**:
  - `loki.write` 元件使用 WAL (Write-Ahead Log) 來緩存日誌，以防止在發送到 Loki 失敗時丟失數據。
  - 應確保為 Alloy Pod 配置的 `persistentVolume` (或 `hostPath`) 有足夠的空間來儲存 WAL 檔案。

### 2.3 安全性

- **最小權限**: 如平台規格所述，授予 Alloy ServiceAccount 的 `ClusterRole` 應嚴格遵守最小權限原則。
- **Secrets 管理**:
  - 如果 Alloy 需要向受保護的端點 (如需要認證的 Loki) 發送數據，**必須**使用 Kubernetes Secrets 來儲存認證資訊 (如使用者、密碼、Token)。
  - 在 `loki.write` 組態中，透過 `http_client_config` 區塊引用這些 Secrets。

### 2.4 可觀測性

- **監控 Alloy 自身**:
  - Alloy 元件會暴露自身的 Prometheus 指標。**必須**設定一個 `PodMonitor` 來抓取這些指標。
  - 使用 Grafana 儀表板監控 Alloy 的健康狀態，例如日誌處理速率、發送到 Loki 的成功/失敗次數、緩存大小等。
- **日誌級別**:
  - 預設情況下，Alloy 的日誌級別應設為 `info`。
  - 在排查問題時，可以臨時調整為 `debug` 以獲取更詳細的資訊。