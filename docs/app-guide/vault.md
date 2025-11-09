# Vault 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 HashiCorp Vault 進行集中式密鑰管理時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述 Detectviz 平台 Vault 的具體部署、組態與標準化整合流程。

### 1.1 部署與安裝

- **佈署方式**: 透過 `gitops/apps/vault.yaml` 安裝官方 Helm chart，需確認 Service 類型、TLS 端點及 Secrets 管理策略符合外部存取需求。
- **流程依賴**: Phase 4 完成 Vault StatefulSet 佈署後，Phase 5 以 Vault CLI 進行初始化與 Kubernetes Auth 啟用，再進入 Phase 6 由平台元件讀取密鑰。
- **命名空間**: Vault **必須**部署在 `vault` 命名空間中。
- **部署方式**: 透過 `gitops/apps/vault.yaml` 由 ArgoCD 進行 GitOps 同步，使用官方 Helm Chart 進行部署。
- **儲存**: 確保 `detectviz-nvme` StorageClass 已建立並在 Vault values 中對應，確保高 I/O 密碼儲存使用 NVMe。
- **後端儲存**: Vault 使用整合式的 Raft 儲存後端 (Integrated Storage)，以 StatefulSet 方式部署，資料持久化於 `detectviz-nvme` StorageClass。
- **高可用 (HA)**: 部署為 3 副本的 StatefulSet，以確保 Raft 儲存後端的法定人數 (quorum) 與高可用性。
- **秘密同步**: GitOps 需預先提供 `SealedSecret` 或 Vault 匯出物（如 PostgreSQL 憑證），避免 Helm 同步時產生明文敏感資訊。

### 1.2 初始化與解封 (Unsealing)

- **初始化**: 首次部署後，**必須**手動執行 `vault operator init` 進行初始化。
  - **Key Shares**: `5`
  - **Key Threshold**: `3`
  - 初始化產生的 Unseal Keys 與 Initial Root Token **必須**安全地儲存在外部密碼管理器中，**嚴禁**存放在 Git 儲存庫或任何不安全的地方。
- **解封**:
  - **手動解封**: 每個 Vault Pod 在啟動或重啟後都需要手動解封。需提供 3 把 Unseal Keys。
  - **自動解封 (Auto-unseal)**: 在生產環境中，強烈建議設定自動解封機制 (如 Transit Secrets Engine)，以簡化維運。

### 1.3 Kubernetes 認證 (Kubernetes Auth Method)

平台中的應用程式**必須**使用 Kubernetes Auth Method 來向 Vault 進行認證。

- **啟用路徑**: 認證後端啟用在 `auth/kubernetes` 路徑。
- **組態**:
  - `token_reviewer_jwt`: **必須**設定為 Vault ServiceAccount 的 JWT。
  - `kubernetes_host`: 指向叢集內部的 Kubernetes API Server (`https://kubernetes.default.svc:443`)。
  - `kubernetes_ca_cert`: 使用 Vault Pod 內的 ServiceAccount CA 憑證。
- **角色 (Roles)**:
  - 每個需要存取 Vault 的應用都應定義一個專屬的 `Role`。
  - `Role` 將 Vault Policies 綁定到 Kubernetes 的 `ServiceAccount`。
  - 範例 (`grafana-role`):
    ```bash
    vault write auth/kubernetes/role/grafana \
        bound_service_account_names=grafana \
        bound_service_account_namespaces=monitoring \
        policies=grafana-policy \
        ttl=24h
    ```

### 1.4 Secret Engines

- **KV Secrets Engine - Version 2 (kv-v2)**:
  - **用途**: 用於儲存靜態密鑰，如資料庫密碼、API 金鑰等。
  - **版本控制**: kv-v2 提供密鑰的版本控制與銷毀 (destroy/undelete) 功能，為平台預設使用的引擎。
- **Database Secrets Engine**:
  - **用途**: 為 PostgreSQL 等資料庫動態生成有時效性的帳號密碼。
  - **整合**: 應設定此引擎來管理 `grafana` 和其他平台應用的資料庫憑證。

### 1.5 應用整合模式

應用程式從 Vault 讀取密鑰主要使用以下模式：

- **Vault Agent Sidecar Injector**:
  - **建議模式**: 這是平台**建議**的標準整合模式。
  - **原理**: 透過 Kubernetes Admission Webhook 自動為 Pod 注入一個 Vault Agent Sidecar 容器。
  - **功能**: Agent 負責向 Vault 認證、渲染模板並將密鑰寫入共享的 memory volume 中，應用程式只需從檔案系統讀取即可。
  - **啟用方式**: 在 Deployment/StatefulSet 的 `annotations` 中加入：
    ```yaml
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: 'true'
        vault.hashicorp.com/role: 'grafana' # 對應 Kubernetes Auth Role
        vault.hashicorp.com/agent-inject-secret-database-config.txt: 'secret/data/database/config'
    ```
- **Vault CSI Provider**:
  - **替代模式**: 可用於不適合 Sidecar 模式的場景。
  - **原理**: 透過 CSI (Container Storage Interface) 將 Vault 中的密鑰掛載為 Pod 中的 Volume。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Vault 進行密鑰管理時應遵循的最佳實踐。

### 2.1 策略 (Policies)

- **最小權限原則**: Policy **必須**遵循最小權限原則。只授予應用程式或使用者讀取/寫入其絕對需要的路徑。
- **路徑區隔**: 不同應用、不同環境的密鑰應存放在不同的路徑下，並透過 Policy 進行嚴格隔離。
  - **範例路徑**: `secret/data/detectviz/prod/grafana`
- **拒絕策略 (Deny Policies)**: 預設情況下，所有路徑都是隱式拒絕的。明確的 `deny` 規則應謹慎使用，因為它會覆寫 `allow` 規則。

### 2.2 安全性

- **Root Token 嚴格控管**:
  - **僅用於初始設定**: Initial Root Token **只應**用於 Vault 的初始設定 (如設定認證後端、Policies)。
  - **立即撤銷**: 初始設定完成後，應立即建立一個具備管理權限的管理員帳號，並撤銷 (revoke) Initial Root Token。
- **稽核 (Auditing)**:
  - **啟用稽核設備**: **必須**為 Vault 啟用至少一個稽核設備 (Audit Device)，將所有請求與回應記錄到檔案或 Syslog 中。這對於安全事件追蹤至關重要。
- **TLS Everywhere**:
  - Vault Client 與 Server 之間、以及 Vault 節點之間的通訊**必須**使用 TLS 加密。在生產環境中，應使用由受信任的 CA (如 cert-manager) 簽發的憑證。

### 2.3 維運 (Operations)

- **備份與恢復**:
  - **定期快照**: 定期使用 `vault operator raft snapshot save` 命令為 Raft 後端建立快照，並將快照檔案安全地備份到外部儲存。
  - **災難恢復演練**: 定期演練使用快照進行恢復的流程 (`vault operator raft snapshot restore`)，確保備份的有效性。
- **升級策略**:
  - 遵循官方文件指引，採用滾動升級的方式，一次升級一個 Pod。
  - 在升級前務必先建立快照備份。
- **監控**:
  - **Prometheus Metrics**: 啟用 Vault 的 `/v1/sys/metrics` 端點，並設定 Prometheus `ServiceMonitor` 來抓取 Vault 的遙測數據，監控其健康狀態、延遲與認證速率。

### 2.4 Seal/Unseal 流程管理

- **安全儲存 Unseal Keys**: Unseal Keys 應分散給多位授權的管理員保管，不應由單一個人持有全部的 Keys。
- **自動化考量**: 雖然 `deployment.md` 中描述了手動解封流程，但在長期維運中，應規劃導入基於雲端 KMS 或硬體安全模組 (HSM) 的自動解封方案，以提高可用性並減少手動操作。

### 2.5 應用整合最佳實踐

- **Grafana 與 Vault Provider**：在 `grafana.ini` 補齊 `vault` 區塊的 `url`、`token`、`namespace` 等設定，可將 Alerting、資料庫與外掛密鑰改由 Vault 供應，並支援 Token 自動續約。
- **Vault Transit 加密**：使用 Vault Transit 加密 Grafana 資料庫敏感欄位，需於 Vault 啟用 transit engine、建立 key，並在 Grafana 設定 `token`、`url` 等欄位。
- **Vault Agent Annotations**：為 Grafana Mimir、Grafana Alloy 等工作負載預留 Vault Agent annotations，使 TLS 憑證與秘密可由 Vault Agent 側車掛載至 `/vault/secrets`。
- **Alloy Vault 整合**：Alloy 對 Vault 的遠端抓取需設定 `remote.vault` `server`、`auth.*`，支援 Kubernetes、AppRole、Token 等多種驗證；可於 values 中使用 `auth.kubernetes` 以叢集 ServiceAccount 自動換取 Vault Token。
