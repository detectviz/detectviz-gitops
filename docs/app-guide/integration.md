# 平台整合與資料流規格

本文檔定義了 Detectviz 平台中各技術棧之間的整合方式、資料流動與最佳實踐。

---

## 1. 平台整合架構

本節詳述 Detectviz 平台各技術棧之間的整合模式與資料流動路徑。

### 1.1 IaC 與虛擬化整合

- **Terraform → Proxmox**：`terraform/terraform.tfvars` 必須提供 `proxmox_api_token_id`、`proxmox_api_token_secret` 與對應儲存池，並指向 `https://192.168.0.2:8006/api2/json` 以套用 VM 建置；套用後需在 Proxmox 驗證 `vmid` 與節點 `pve` 對應狀態。
- **Ansible → Proxmox**：Terraform 產出 `ansible/inventory.ini` 後，需覆寫登入帳號與私鑰，使用 Proxmox 所啟動的 VM 作為 Ansible 目標節點，並依參考文件安裝 `kubernetes.core` / `community.kubernetes` collection 完成 kubeadm 初始化。
- **Kubernetes → Proxmox**：Phase 2.5 套用節點標籤時，`detectviz.io/proxmox-host` 必須對應 Proxmox Host ID，以便監控 relabeling 與 VM 層健康度關聯。

### 1.2 GitOps 與應用同步

- **ArgoCD → GitOps 倉庫**：`gitops/app-of-apps.yaml` 與 `gitops/apps/*.yaml` 必須指向實際 Git 倉庫 `repoURL` 與 `targetRevision`；ArgoCD 以 App-of-Apps 模式同步平台服務，確保監控、資料庫、Vault、Ollama 等物件依順序部署。

### 1.3 叢集部署與節點管理

- **Kubernetes → Proxmox（節點配置）**：Terraform 預設的 `master_ips`、`worker_ips` 與 `worker_hostnames` 須與 README 拓撲一致，使叢集節點能對應 Proxmox VM 與 DNS 紀錄，避免 Node/Service 網段衝突。

---

## 2. 監控與告警鏈路

### 2.1 Alertmanager ↔ Grafana

Grafana 必須在 `gitops/values/monitoring/grafana.yaml` 中設定 Alertmanager Data Source 與 `GF_UNIFIED_ALERTING_HA_*` 參數，確保雙向同步告警狀態與靜默。

### 2.2 Prometheus → Mimir ← Grafana

`gitops/values/monitoring/kube-prometheus-stack.yaml` 的 `remoteWrite.url` 指向 `mimir-nginx`，Grafana 設定對應 Mimir Data Source，提供長期指標查詢。

### 2.3 日誌與指標收集

- **指標資料流**：`ServiceMonitor` 需涵蓋 `prometheus-pve-exporter`（Proxmox 節點）與 `prometheus-node-exporter`（三主兩從節點），指標先由 Prometheus 收集再透過 Remote Write 送至 Mimir；Grafana Datasource 指向 Mimir Query Frontend 供視覺化與告警。
- **日誌資料流**：節點與應用日誌經由 Alloy `loki.write` 推送到 `detectviz-loki-gateway`，Grafana 透過 Loki Datasource 讀取，同步完成告警回饋。

---

## 3. 資料庫與儲存整合

### 3.1 PostgreSQL ↔ ChromaDB ↔ Ollama

- **PostgreSQL**：提供結構化資料儲存，供 Grafana 等應用使用。
- **ChromaDB**：提供向量資料庫服務，專為 AI 應用設計，支援向量檢索與語意搜索。
- **整合方式**：Ollama 模型可透過 ChromaDB 進行向量嵌入與檢索，實現智慧問答與內容生成。

### 3.2 Vault 安全整合

- **密鑰管理**：Vault 負責集中管理所有敏感資訊，包括資料庫密碼、API 金鑰、TLS 憑證。
- **動態注入**：應用程式透過 Vault Agent Injector 或 CSI Provider 動態取得憑證，避免明碼儲存。

---

## 4. AI 與 LLM 整合

### 4.1 Grafana LLM Plugin ↔ Ollama ↔ ChromaDB

- **Grafana LLM Plugin**：提供介面讓使用者與 AI 模型互動。
- **Ollama**：運行本地 LLM 模型，提供推論服務。
- **ChromaDB**：儲存向量化的知識庫，支援上下文檢索增強生成（RAG）。

### 4.2 事件分析與自動化

- **Prometheus + Loki**：收集系統指標與日誌。
- **AI 驅動分析**：透過 LLM 分析異常事件，提供根因分析與修復建議。
- **閉環回饋**：AI 分析結果可觸發自動化修復流程。

---

## 5. 最佳實踐指南

### 5.1 Terraform 整合最佳實踐

- Terraform 建議在 Proxmox 以專用角色 `terraform-prov@pve` 運作，並透過 API Token 或 Vault 管理敏感資訊。

### 5.2 Ansible 整合最佳實踐

- Ansible 執行前需先依參考文件安裝 Collections，並鎖定 `control_plane_endpoint`、`kubernetes_version` 等參數，確保節點初始化與 kubeadm 設定一致。

### 5.3 節點標籤整合

- 節點標籤應使用 `scripts/render-node-labels.sh` 輸出與 K8s Recommended Labels 一致的鍵值，並確保 `detectviz.io/proxmox-host` 與 Proxmox Host ID 同步。

### 5.4 ArgoCD 倉庫管理

- ArgoCD 倉庫與 GitOps 應保持單一真實來源，針對 Helm multi-source 應用（Grafana、Mimir、Loki）需統一於 `gitops/values/monitoring/` 管理覆寫值，避免分散設定。