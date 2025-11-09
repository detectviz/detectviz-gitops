# Grafana 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 Grafana 作為統一觀測中心時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Grafana 的具體部署、組態與標準化流程。

### 1.1 部署與架構

- **Helm Chart**: `grafana/grafana`
- **部署來源**: `gitops/apps/monitoring/grafana.yaml` 透過 Helm multi-source 裝載 `gitops/values/monitoring/grafana.yaml`，以獨立 Deployment 管理 HA。
- **命名空間**: Grafana **必須**部署在 `monitoring` 命名空間。
- **部署方式**: 透過 `gitops/apps/monitoring/grafana.yaml` 由 ArgoCD 進行 GitOps 同步，並使用 `gitops/values/monitoring/grafana.yaml` 進行組態覆寫。
- **值檔要求**: 維持 `replicas: 2`、設定 `GF_UNIFIED_ALERTING_HA_*`、Alertmanager/Mimir/Loki Datasource URL 與 `scripts/bootstrap-monitoring-secrets.sh` 產生的 Secret 名稱一致。
- **高可用 (HA)**:
  - Grafana **必須**以至少 2 個副本的 Deployment 方式部署 (`replicas: 2`)。
  - **必須**啟用 Unified Alerting 的高可用模式，透過環境變數設定 Gossip 協議進行狀態同步：
    - `GF_UNIFIED_ALERTING_HA_LISTEN_ADDRESS`: `0.0.0.0:9094`
    - `GF_UNIFIED_ALERTING_HA_PEERS`: `grafana-ha-headless:9094`
- **後端資料庫**:
  - **必須**使用外部 PostgreSQL 資料庫來儲存儀表板、使用者、權限等狀態資料。
  - 資料庫連線資訊透過 `grafana-database` Secret 注入，該 Secret 由 `scripts/bootstrap-monitoring-secrets.sh` 腳本管理。
  - **資料庫連線**: 使用 PostgreSQL HA（`detectviz-postgresql-admin`、`detectviz-postgresql-initdb` Secret）與 `storageClass: detectviz-nvme`，確保儀表板及 LLM 插件資料持久化。
- **網路曝露**: 透過 Nginx Ingress 將外部網域 `detectviz.com` 代理至 `app.detectviz.internal`，Grafana Service 維持 ClusterIP。

### 1.2 資料來源 (Data Sources)

- **自動化配置**: 所有核心資料來源**必須**透過 `values.yaml` 中的 `datasources` 欄位進行聲明式配置，由 Grafana Operator 或 Sidecar 自動建立。
- **標準資料來源**:
  1.  **Mimir (Prometheus)**:
      - **類型**: `prometheus`
      - **URL**: `http://mimir-nginx.monitoring.svc:80/prometheus`
      - **用途**: 指標的查詢與視覺化。
  2.  **Loki**:
      - **類型**: `loki`
      - **URL**: `http://loki-gateway.monitoring.svc:80`
      - **用途**: 日誌的查詢與視覺化。
  3.  **Alertmanager**:
      - **類型**: `alertmanager`
      - **URL**: `http://kube-prometheus-stack-alertmanager.monitoring.svc:9093`
      - **用途**: 整合 Alertmanager，讓 Grafana Unified Alerting 可以將告警路由至 Alertmanager 進行處理。
- **認證**: 資料來源的認證資訊 (如使用者、密碼) **必須**儲存在 Kubernetes Secrets 中，並在 `datasources` 定義中引用。
- **整合與資料流**: `datasources.yaml` 需同時註冊 `mimir`（`http://detectviz-mimir-query-frontend.monitoring:80`）、`loki`（`http://detectviz-loki-gateway.monitoring:3100`）、`alertmanager`（`http://kube-prometheus-stack-alertmanager.monitoring:9093`）供 Grafana 拉取指標/日誌/告警，並透過 Unified Alerting Webhook 回傳確認狀態；`plugins.detectviz-llm` 需設定 `ollama` Gateway `http://ollama.monitoring:11434` 與 `chromadb` API `http://chromadb.monitoring:8000` 供 LLM 與向量檢索使用。

### 1.3 告警 (Alerting)

- **Unified Alerting**: **必須**使用 Grafana 8.0+ 的 Unified Alerting 介面來管理所有告警規則。
- **告警路由**:
  - Grafana 產生的告警**必須**設定為發送到內建的 Alertmanager 資料來源。
  - 由 Alertmanager 負責後續的告警去重、分組、抑制和通知。
- **Provisioning**: 告警規則可以透過 `AlertRule` CRD (若使用 Grafana Operator) 或 ConfigMap 掛載的方式進行 GitOps 管理。

### 1.4 LLM 插件整合

- **插件**: `grafana-llm-app`
- **連線**: **必須**在 Grafana UI (Connections -> LLM) 中設定一個 OpenAI-compatible 連線，其端點指向平台內部的 Ollama 服務。
- **URL**: `http://ollama.detectviz.svc:11434`
- **用途**: 該整合用於實現告警事件摘要、日誌分析與自動化建議生成等 AIOps 功能。

### 1.5 安全與管理

- **管理員帳號**:
  - 管理員帳號與密碼**必須**透過 `grafana-admin` Secret 進行管理，該 Secret 由 `scripts/bootstrap-monitoring-secrets.sh` 腳本建立。
  - **禁止**在 `values.yaml` 中使用明文的 `adminPassword`。
- **Ingress**: Grafana 應透過 Ingress 暴露服務，並在生產環境中啟用 TLS。
- **`GF_SERVER_DOMAIN`**: **必須**設定此環境變數，以確保郵件通知中的連結正確。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Grafana 時應遵循的最佳實踐。

### 2.1 儀表板管理 (Dashboard Management)

- **GitOps for Dashboards (Provisioning)**:
  - **強烈建議**將所有儀表板的 JSON 檔案存放在 Git 儲存庫中，並透過 Grafana 的 Provisioning 機制 (掛載為 ConfigMap) 自動載入。
  - 這能確保儀表板的版本控制、程式碼審查與災難恢復。
- **資料夾與權限**:
  - 使用資料夾來組織相關的儀表板。
  - 結合 Grafana 的權限管理 (Teams/Roles)，對不同資料夾設定精細的存取控制。
- **變數 (Variables)**:
  - 善用儀表板變數 (例如 `$cluster`, `$namespace`, `$pod`) 來建立可互動、可複用的動態儀表板。
  - 變數的查詢應盡量高效，避免使用高基數的 `label_values()` 查詢。
- **啟用 Alerting HA**: 於 `grafana.ini` 的 `[unified_alerting]` 設定 `ha_listen_address=${POD_IP}:9094`、`ha_peers=grafana-alerting.grafana:9094` 並開放 TCP/UDP 9094，確保多實例不重複通知。
- **Kubernetes HA 配置**: 在 Kubernetes 上配置頭服務 (Headless Service) 提供 Pod IP 給 `ha_peers`，Deployment Container 需宣告 `gossip-tcp`、`gossip-udp` 埠。
- **Vault 整合**: 依 `integrate-with-hashicorp-vault` 指南於 `grafana.ini` 宣告 `url`、`token`、`auth_method`，可讓 Alertmanager、資料來源等設定直接讀取 Vault；若需加密 Grafana Database Secrets，啟用 Vault Transit Provider，確保 `token` 為可續約服務 Token，降低密鑰外洩風險。

### 2.2 效能優化

- **查詢優化**:
  - 避免在儀表板中放置大量、複雜或時間範圍過長的 PromQL/LogQL 查詢。
  - 優先使用錄製規則 (Recording Rules) 預先計算複雜查詢。
  - 使用 `rate()` 或 `increase()` 等對計數器 (Counter) 類型指標進行計算的函數，而不是直接查詢原始值。
- **儀表板渲染**:
  - 避免在單一儀表板上放置過多的面板 (Panels)。
  - 對於不需頻繁更新的面板，可以調整其更新頻率。

### 2.3 安全性

- **SSO/OAuth**: 在生產環境中，**強烈建議**整合 SSO (如 LDAP, OAuth, SAML) 進行使用者認證，而不是依賴內建的使用者管理。
- **API 金鑰**:
  - 使用 API 金鑰時，應遵循最小權限原則，僅授予其所需的操作權限 (Viewer, Editor, Admin)。
  - 為不同的自動化任務建立專屬的 API 金鑰。
- **Public Dashboards**: 謹慎使用儀表板的公開分享功能，確保不會意外洩漏敏感的內部監控數據。

### 2.4 可觀測性即程式碼 (Observability as Code)

- **Terraform Provider**:
  - 對於需要透過 API 進行複雜管理的場景 (如自動建立資料夾、團隊、資料來源)，可以使用 Grafana 的 Terraform Provider 來將這些資源納入 IaC 管理。
- **Grafana Operator**:
  - 考慮使用 Grafana Operator，它可以讓您透過 `Dashboard`, `DataSource`, `AlertRule` 等 CRD 來管理 Grafana 資源，更完美地融入 GitOps 生態。

### 2.5 使用者體驗

- **一致的標籤**: 確保所有資料來源的指標都使用一致的標籤 (如 `cluster`, `namespace`, `app`)，這樣可以在儀表板中輕鬆實現跨資料來源的關聯與下鑽 (drill-down)。
- **Annotations**: 使用 Annotations 功能在圖表上標記重要事件，如部署、告警觸發等，有助於快速關聯問題。