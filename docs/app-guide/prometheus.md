# Prometheus (kube-prometheus-stack) 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 `kube-prometheus-stack` 進行指標監控與告警時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Prometheus 監控堆疊的具體部署、組態與標準化流程。

### 1.1 部署與架構

- **Helm Chart**: `kube-prometheus-stack`
- **佈署來源**: `gitops/apps/monitoring/kube-prometheus-stack.yaml` 以 Helm multi-source 模式讀取 `gitops/values/monitoring/kube-prometheus-stack.yaml`，ArgoCD 需指向實際 Git 倉庫。
- **命名空間**: 所有元件**必須**部署在 `monitoring` 命名空間。
- **內建元件調整**: 停用 chart 內建 Grafana，改用獨立 Grafana Application；啟用 `prometheus-node-exporter` DaemonSet 並確保節點標籤 relabelings 與 Phase 2.5 腳本一致。
- **核心元件**:
  - **Prometheus Operator**: 負責管理 Prometheus Server、Alertmanager 及相關 CRD 的生命週期。
  - **Prometheus Server**: 以 StatefulSet 方式部署，負責指標的抓取、儲存與查詢。
  - **Alertmanager**: 以 StatefulSet 方式部署，負責告警的路由、分組與通知。
  - **`kube-state-metrics`**: 以 Deployment 方式部署，提供 Kubernetes API 物件的狀態指標。
  - **`prometheus-node-exporter`**: 以 DaemonSet 方式部署，在每個節點上收集主機層級的指標。
- **Grafana**: `kube-prometheus-stack` chart 內建的 Grafana **必須停用** (`grafana.enabled: false`)。平台使用獨立部署的 Grafana 實例。

### 1.2 指標收集 (Scraping)

- **抓取機制**: **必須**使用 `ServiceMonitor` 和 `PodMonitor` CRD 來聲明式地定義抓取目標。禁止使用靜態設定 (`static_configs`) 或基於 annotation 的抓取。
- **`ServiceMonitor`**: 用於抓取暴露 metrics 端點的 Kubernetes `Service`。
- **`PodMonitor`**: 用於直接抓取 Pod，適用於沒有對應 `Service` 的場景。
- **標籤選擇器 (Selectors)**:
  - Prometheus Operator 會自動發現與其 `release` 標籤相符的 `ServiceMonitor` 和 `PodMonitor`。
  - 為抓取自訂應用，應設定 `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false`，使 Prometheus 抓取 `monitoring` 命名空間中所有的 `ServiceMonitor`。
  - Detectviz 額外以 `prometheus.prometheusSpec.additionalServiceMonitors` 宣告 `ipmi-exporter` 與 `proxmox-ve-exporter`，統一透過 ServiceMonitor 提供 `params` 與 `relabelings`，避免使用靜態 `additionalScrapeConfigs`。

### 1.3 與 Grafana Mimir 的整合 (長期儲存)

- **遠端寫入 (Remote Write)**:
  - `values` 需設定 `remoteWrite.url` 指向 `mimir-nginx`，並填妥 `environment`、`cluster`、`proxmox` 自訂 labels，以供指標長期儲存。
  - Prometheus Server 收集到的所有指標**必須**透過 `remoteWrite` 功能轉發到 Grafana Mimir 進行長期儲存。
  - `remoteWrite.url` **必須**指向 Mimir 的 gateway/distributor 服務，在平台中為 `http://mimir-nginx.monitoring.svc:80/api/v1/push`。

### 1.4 外部標籤 (External Labels)

- 為了在多叢集或多環境場景中區分指標來源，**必須**設定 `externalLabels`。
- 這些標籤會被附加到所有由該 Prometheus 實例抓取或推送的指標上。
- **標準外部標籤**:
  - `cluster`: 叢集名稱 (e.g., `detectviz-prod`)
  - `environment`: 環境名稱 (e.g., `production`)

### 1.5 Alertmanager 組態

- **高可用 (HA)**: Alertmanager 以 2 個副本的 StatefulSet 部署，並透過 `alertmanager.alertmanagerSpec.cluster.peerAddresses` 進行集群設定，確保告警狀態同步。
- **組態管理**: Alertmanager 的組態 (路由、接收器等) 透過 `AlertmanagerConfig` CRD 進行管理，並由 ArgoCD 進行 GitOps 同步。
- **與 Grafana 的整合**: 平台中獨立部署的 Grafana **必須**將此 Alertmanager 設定為其資料來源，以實現統一的告警管理介面。

### 1.6 Proxmox Exporter 整合

- **Exporter 部署**: `prometheus-pve-exporter` 以 Python 應用形式直接部署在 Proxmox 主機上，並以 Systemd 服務運行。
- **Prometheus 抓取設定**:
  - 補齊 `placeholders.proxmox*`，確保 Prometheus 抓取 `prometheus-pve-exporter` 指標。
  - **必須**建立一個 `Service` + `Endpoints`（位於 `gitops/components/monitoring/proxmox-ve-exporter/`）並對應的 `additionalServiceMonitors[proxmox-ve-exporter]`，透過 annotation `detectviz.io/proxmox-target` 將實際目標寫入 `__param_target`。
  - `ServiceMonitor` 應包含 `jobLabel`，例如 `proxmox-ve`。
- **指標標籤**: 抓取到的 Proxmox 指標應包含能識別底層主機的標籤，如 `proxmox_host_id`。
- **指標資料流**: `ServiceMonitor` 需涵蓋 `prometheus-pve-exporter`（Proxmox 節點）與 `prometheus-node-exporter`（三主兩從節點），指標先由 Prometheus 收集再透過 Remote Write 送至 Mimir；Grafana Datasource 指向 Mimir Query Frontend 供視覺化與告警。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 `kube-prometheus-stack` 時應遵循的最佳實踐。

- **版本要求**: 依官方建議至少使用 Kubernetes 1.19+、Helm 3+，並透過 `helm show values oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack` 取得完整可覆寫參數。

### 2.1 資源管理

- **Prometheus 資源設定**:
  - Prometheus Server 是資源密集型應用。**必須**為其 Pod 設定合理的 CPU 和 Memory `requests` 與 `limits`。
  - `requests.memory` 應根據預期的指標基數 (cardinality) 和時間序列數量進行估算。
  - 建議啟用 `persistentVolume` 並使用 `detectviz-sata` StorageClass，以避免因 Pod 重啟導致短期指標資料遺失。
- **`node-exporter`**: 應設定 `hostNetwork: true` 和 `hostPID: true` 以收集更準確的網路與進程指標。
- **CRD 管理**: Chart 建立多個 CRD，不會自動清除；升級時須先手動更新 CRD，再執行 `helm upgrade`，並注意 major version 變更。若需移除部署後的 CRD，需顯式執行 `kubectl delete crd ...`，保持叢集乾淨。

### 2.2 PrometheusRule 管理

- **告警規則 (Alerting Rules)**:
  - **必須**使用 `PrometheusRule` CRD 來定義告警規則。
  - 規則應包含清晰的 `summary` 和 `description`，並善用 `labels` 和 `annotations` 來傳遞告警的嚴重性 (`severity`)、相關儀表板連結等附加資訊。
- **錄製規則 (Recording Rules)**:
  - 對於複雜或查詢成本高的 PromQL，應使用錄製規則預先計算結果，並存為新的時間序列。
  - 這能顯著提升儀表板查詢效能並降低 Prometheus Server 負載。

### 2.3 指標基數 (Cardinality) 管理

- **避免高基數標籤**: 在 `relabelings` 或應用程式本身的指標中，避免使用具有無限或極多可能值的標籤 (如 user ID, request ID, timestamp)，這會導致時間序列爆炸，耗盡 Prometheus 記憶體。
- **定期審查**: 定期使用 `tsdb analyze` 工具或 Grafana 相關儀表板審查指標的基數，找出並優化高基數指標。

### 2.4 可靠性與擴展性

- **聯邦 (Federation)**: 在超大規模部署中，可以考慮使用 Prometheus 聯邦來分層匯總指標。一個全域的 Prometheus Server 從多個子叢集的 Prometheus Server 中抓取匯總後的指標。
- **Thanos/Cortex/Mimir**: 對於需要長期儲存、全域查詢視圖和高可用性的場景，整合 Mimir (如本平台所做) 是標準的最佳實踐。這將指標儲存的負擔從 Prometheus Server 轉移到可水平擴展的後端。

### 2.5 監控目標的最佳實踐

- **Exporters**: 盡可能使用官方或社群維護的 Exporter。
- **自訂應用**: 開發自訂應用時，應引入 Prometheus Client Library，並遵循官方的最佳實踐來暴露指標，例如提供 `_count`, `_sum`, `_bucket` 等標準後綴。
- **`up` 指標**: 善用 `up` 指標 (`up{job="<job_name>"}`) 來監控抓取目標本身是否健康。這是最基礎也最重要的告警之一。