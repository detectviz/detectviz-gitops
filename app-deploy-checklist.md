# DetectViz Application Deployment Checklist

**最後更新**: 2025-11-16
**狀態**: Phase 6 配置完成，等待 Vault secrets 初始化後進行部署驗證

---

## 目錄

- [架構重構完成](#架構重構完成)
- [Phase 6: 應用部署](#phase-6-應用部署)
- [Phase 7: 最終驗證](#phase-7-最終驗證)
- [Phase 8: Platform Governance](#phase-8-platform-governance-未來實施)

---

## ✅ 架構重構完成 (2025-11-16)

**Namespace 架構已按 Platform Engineering 原則重構**：

```
# Platform Services (獨立 namespace)
postgresql  → PostgreSQL HA cluster (Platform Service)
keycloak    → Keycloak SSO/Identity Provider (Platform Service)

# Application Layer (獨立 namespace)
grafana     → Grafana UI (visualization + OAuth client)

# Observability Backend (統一 monitoring namespace)
monitoring  → Prometheus + Loki + Tempo + Mimir + Alloy Agent
```

**安全架構優勢**：
- ✅ Vault ACL 按 namespace 細粒度隔離
- ✅ Zero Trust + Least Privilege 合規
- ✅ 符合 CNCF/EKS/Anthos/OpenShift 最佳實踐
- ✅ Attack surface 最小化（namespace 隔離）

**參考文件**：
- `VAULT_PATH_STRUCTURE.md` - Vault secret 路徑規範
- `APP_CONFIG_NOTES.md` - 應用配置依賴關係
- `app-deploy-sop.md` - 部署流程文檔

---

# Phase 6: 應用部署

## 6.0 Vault + ESO

### ClusterSecretStore 配置 ✅

- [x] **ClusterSecretStore 已配置**
  - 文件: `argocd/apps/infrastructure/external-secrets-operator/overlays/cluster-secret-store.yaml`
  - Name: `vault-backend`
  - Vault server: `http://vault.vault.svc.cluster.local:8200`
  - Auth method: Kubernetes
  - ServiceAccount: `external-secrets` (namespace: `external-secrets-system`)

### Vault ACL 隔離設計 ✅

- [x] **Vault Path 結構按 namespace 隔離**
  ```
  secret/postgresql/*     → postgresql namespace only
  secret/keycloak/*       → keycloak namespace only
  secret/grafana/*        → grafana namespace only
  secret/monitoring/*     → monitoring namespace only
  ```

- [x] **ExternalSecret 分布配置**
  - PostgreSQL: `argocd/apps/observability/postgresql/overlays/externalsecret.yaml` (namespace: `postgresql`)
  - Keycloak: `argocd/apps/identity/keycloak/overlays/externalsecret-db.yaml` (namespace: `keycloak`)
  - Grafana Admin: `argocd/apps/observability/grafana/overlays/externalsecret-admin.yaml` (namespace: `grafana`)
  - Grafana DB: `argocd/apps/observability/grafana/overlays/externalsecret-db.yaml` (namespace: `grafana`)
  - Grafana OAuth: `argocd/apps/observability/grafana/overlays/externalsecret-oauth.yaml` (namespace: `grafana`)
  - Minio: `argocd/apps/observability/minio/overlays/externalsecret.yaml` (namespace: `monitoring`)

### 部署前準備 ⚠️

- [ ] **初始化 Vault Secrets** (參考: `VAULT_PATH_STRUCTURE.md`)
  ```bash
  # PostgreSQL secrets
  vault kv put secret/postgresql/admin \
    postgres-password="$(openssl rand -base64 32)" \
    app-password="$(openssl rand -base64 32)" \
    repmgr-password="$(openssl rand -base64 32)"

  # PostgreSQL initdb
  vault kv put secret/postgresql/initdb \
    init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD 'xxx'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"

  # Keycloak secrets
  vault kv put secret/keycloak/database password="$(openssl rand -base64 32)"

  # Grafana secrets
  vault kv put secret/grafana/admin user="admin" password="$(openssl rand -base64 32)"
  vault kv put secret/grafana/database user="grafana" password="$(openssl rand -base64 32)"
  vault kv put secret/grafana/oauth keycloak-client-secret="$(openssl rand -base64 32)"

  # Minio secrets
  vault kv put secret/monitoring/minio root-user="admin" root-password="$(openssl rand -base64 32)"
  ```

---

## 6.1 Alloy Agent (完全取代 node-exporter)

### Alloy DaemonSet ✅

- [x] **Alloy DaemonSet 已部署**
  - 文件: `argocd/apps/observability/overlays/daemonset.yaml`
  - Namespace: `monitoring`
  - Image: `grafana/alloy:v1.1.0`
  - PriorityClass: `system-node-critical`
  - Tolerations: master/control-plane nodes

- [x] **Alloy 配置完整**
  - 文件: `argocd/apps/observability/overlays/config.alloy`
  - ✅ Kubernetes Pods 日誌收集 (`loki.source.kubernetes`)
  - ✅ Systemd Journal 日誌收集 (`loki.source.journal`)
  - ✅ Loki Gateway 整合 (`http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push`)
  - ✅ 環境標籤: `cluster=detectviz-production`, `environment=production`

- [x] **Alloy RBAC 配置**
  - 文件: `argocd/apps/observability/overlays/rbac.yaml`
  - ServiceAccount: `alloy`
  - ClusterRole: 讀取 pods, namespaces, nodes, endpoints
  - ClusterRoleBinding: `alloy` → `alloy` (namespace: monitoring)

- [x] **node-exporter 已移除**
  - 刪除目錄: `argocd/apps/observability/node-exporter/`
  - Prometheus values: `prometheus-node-exporter.enabled: false`
  - 註解: Alloy 的 host_metrics 提供等效功能

### Alloy 功能覆蓋 ✅

| 功能 | node-exporter | Alloy | 狀態 |
|------|--------------|-------|------|
| Host metrics | ✅ | ✅ `local.host_metrics` (未啟用，待補充) | ⚠️ |
| Kubernetes Pods logs | ❌ | ✅ `loki.source.kubernetes` | ✅ |
| Systemd Journal logs | ❌ | ✅ `loki.source.journal` | ✅ |
| OTLP traces | ❌ | ✅ `otelcol.receiver.otlp` (未啟用) | 🔜 |

**待補充**:
- [ ] 在 `config.alloy` 中添加 `prometheus.exporter.unix` 或 `local.host_metrics` 配置

---

## 6.2 Observability Stack

### Prometheus ✅

- [x] **Prometheus 配置完成**
  - 文件: `argocd/apps/observability/prometheus/overlays/values.yaml`
  - Namespace: `monitoring`
  - Replicas: 2 (HA)
  - Retention: 15d
  - StorageClass: `local-path`
  - Storage: 50Gi

- [x] **remoteWrite to Mimir**
  - URL: `http://mimir-distributor.monitoring.svc.cluster.local:8080/api/v1/push`
  - Queue capacity: 20000

- [x] **ServiceMonitor 自動發現**
  - `podMonitorSelectorNilUsesHelmValues: false`
  - `serviceMonitorSelectorNilUsesHelmValues: false`

- [x] **External Labels**
  - `environment: production`
  - `cluster: detectviz-production`

- [x] **Infrastructure Exporters ServiceMonitors**
  - IPMI Exporter (lines 152-183)
  - Proxmox VE Exporter (lines 184-224)
  - ArgoCD Metrics (lines 225-270)

### Alertmanager ✅

- [x] **Alertmanager 配置**
  - Replicas: 3 (HA)
  - StorageClass: `local-path`
  - Storage: 10Gi

### Loki ⚠️

- [x] **Loki 基礎配置**
  - 文件: `argocd/apps/observability/loki/overlays/values.yaml`
  - Namespace: `monitoring`

- [ ] **待檢查: Loki storage 配置**
  - 確認 storage backend (filesystem/s3/minio)
  - 確認 retention policy
  - 確認 chunk/index storage

### Tempo ⚠️

- [x] **Tempo 基礎配置**
  - 文件: `argocd/apps/observability/tempo/overlays/`
  - Namespace: `monitoring`
  - Version: 1.10.0

- [ ] **待檢查: Tempo storage 配置**
  - 確認 storage backend
  - 確認 retention policy
  - 確認 OTLP receiver 配置

### Mimir ⚠️

- [x] **Mimir 基礎配置**
  - 文件: `argocd/apps/observability/mimir/overlays/values.yaml`
  - Namespace: `monitoring`

- [ ] **待檢查: Mimir S3/Minio backend**
  - 確認 Minio 整合
  - 確認 blocks storage 配置
  - 確認 compactor 配置

### Minio ⚠️

- [x] **Minio ExternalSecret 配置**
  - 文件: `argocd/apps/observability/minio/overlays/externalsecret.yaml`
  - Namespace: `monitoring`
  - Vault path: `secret/data/monitoring/minio`

- [ ] **待檢查: Minio 配置**
  - 確認 values.yaml 配置
  - 確認 PVC 配置
  - 確認 bucket 自動創建 (for Loki/Tempo/Mimir)

---

## 6.3 PostgreSQL (Platform Service)

### PostgreSQL HA ✅

- [x] **PostgreSQL HA 配置**
  - 文件: `argocd/apps/observability/postgresql/overlays/values.yaml`
  - Namespace: `postgresql` ✅
  - PostgreSQL replicas: 3 (1 primary + 2 standby)
  - Pgpool replicas: 2
  - Pod anti-affinity: `hard`
  - StorageClass: `topolvm-provisioner`
  - Storage: 10Gi per replica

- [x] **ExternalSecret 配置**
  - Namespace: `postgresql` ✅
  - Vault paths:
    - `secret/data/postgresql/admin/*` (postgres-password, app-password, repmgr-password)
    - `secret/data/postgresql/initdb/*` (init-grafana-sql)

- [x] **Init Script 配置**
  - `initdbScriptsSecret: detectviz-postgresql-initdb`
  - 自動創建 Grafana database

- [x] **ServiceMonitor 配置**
  - Enabled: true
  - Namespace: `monitoring` (跨 namespace 監控)
  - Labels: `prometheus: kube-prometheus-stack`

### 部署後驗證 ⚠️

- [ ] **驗證 PostgreSQL 部署**
  ```bash
  kubectl get pods -n postgresql
  kubectl get pvc -n postgresql
  kubectl get svc -n postgresql

  # 預期結果:
  # postgresql-ha-postgresql-0, 1, 2: Running
  # postgresql-ha-pgpool-0, 1: Running
  ```

- [ ] **驗證 Replication**
  ```bash
  kubectl exec -it postgresql-ha-postgresql-0 -n postgresql -- \
    psql -U postgres -c "SELECT * FROM pg_stat_replication;"
  ```

- [ ] **驗證 Grafana Database**
  ```bash
  kubectl exec -it postgresql-ha-postgresql-0 -n postgresql -- \
    psql -U postgres -c "\l" | grep grafana
  ```

---

## 6.4 Keycloak (Platform Service)

### Keycloak 配置 ✅

- [x] **Keycloak 基礎配置**
  - 文件: `argocd/apps/identity/keycloak/overlays/`
  - Namespace: `keycloak` ✅
  - Chart: bitnami/keycloak 19.2.1

- [x] **ExternalSecret 配置**
  - Namespace: `keycloak` ✅
  - Vault path: `secret/data/keycloak/database/password`

### Keycloak Realm 配置 ⚠️

- [ ] **待補充: Keycloak Realm 配置**
  - Realm name: `detectviz`
  - OAuth2 Client for Grafana:
    - Client ID: `grafana`
    - Client Secret: 對應 Vault path `secret/data/grafana/oauth/keycloak-client-secret`
    - Valid Redirect URIs: `https://grafana.detectviz.internal/*`
    - Roles: `admin`, `editor`, `viewer`

- [ ] **待補充: Realm GitOps 配置**
  - 創建 ConfigMap 包含 realm export JSON
  - 或使用 Keycloak Operator

### 部署後驗證 ⚠️

- [ ] **驗證 Keycloak 部署**
  ```bash
  kubectl get pods -n keycloak
  kubectl get svc -n keycloak
  kubectl get ingress -n keycloak
  ```

- [ ] **驗證 Keycloak UI 訪問**
  ```bash
  curl -k https://keycloak.detectviz.internal
  ```

- [ ] **配置 OAuth2 Client**
  - 手動配置或使用 realm import

---

## 6.5 Grafana (Application Layer)

### Grafana HA ✅

- [x] **Grafana HA 配置**
  - 文件: `argocd/apps/observability/grafana/overlays/values.yaml`
  - Namespace: `grafana` ✅
  - Replicas: 2
  - Resources: 512Mi-1Gi memory, 200m-1000m CPU

- [x] **Pod Anti-Affinity**
  - Prefer different nodes (soft anti-affinity)
  - Topology key: `kubernetes.io/hostname`

- [x] **Pod Disruption Budget**
  - minAvailable: 1

### PostgreSQL Backend ✅

- [x] **Database 配置**
  - Type: `postgres`
  - Host: `postgresql-pgpool.postgresql.svc.cluster.local:5432` ✅
  - Database: `grafana`
  - User: `grafana`
  - Secret: `grafana-database` (from ExternalSecret)

### ExternalSecrets ✅

- [x] **ExternalSecrets 配置**
  - Namespace: `grafana` ✅
  - Admin: `secret/data/grafana/admin/*` (user, password)
  - Database: `secret/data/grafana/database/*` (user, password)
  - OAuth: `secret/data/grafana/oauth/*` (keycloak-client-secret)

### Keycloak OAuth2 整合 ✅

- [x] **OAuth2 配置**
  - Enabled: true
  - Provider: Keycloak
  - Client ID: `grafana`
  - Client Secret: from `grafana-keycloak-oauth` secret
  - Auth URL: `https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/auth`
  - Token URL: `https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/token`
  - API URL: `https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/userinfo`
  - Role mapping: `contains(roles[*], 'admin') && 'Admin' || contains(roles[*], 'editor') && 'Editor' || 'Viewer'`

### Datasources ✅

- [x] **Datasources 配置**
  - Mimir (default): `http://mimir-query-frontend.monitoring.svc.cluster.local:8080/prometheus` ✅
  - Loki: `http://loki-gateway.monitoring.svc.cluster.local:80` ✅
  - Alertmanager: `http://prometheus-alertmanager.monitoring.svc.cluster.local:9093` ✅

### Unified Alerting HA ✅

- [x] **Alerting HA 配置**
  - Enabled: true
  - HA Listen Address: `$(POD_IP):9094`
  - HA Advertise Address: `$(POD_IP):9094`
  - HA Peers: `grafana-alerting.grafana.svc.cluster.local:9094` ✅

- [x] **Headless Service**
  - Name: `grafana-alerting`
  - Namespace: `grafana` ✅
  - Ports: 9094/TCP, 9094/UDP

### ServiceMonitor ✅

- [x] **ServiceMonitor 配置**
  - Namespace: `grafana` ✅
  - Labels: `prometheus: kube-prometheus-stack`
  - Interval: 30s

### Dashboard Provisioning ⚠️

- [ ] **待補充: Dashboard as Code**
  - 創建 ConfigMap 包含 dashboard JSON
  - 使用 `dashboardProviders` 和 `dashboards` values
  - 參考: Grafana Helm chart documentation

### 部署後驗證 ⚠️

- [ ] **驗證 Grafana 部署**
  ```bash
  kubectl get pods -n grafana
  kubectl get svc -n grafana
  kubectl get ingress -n grafana
  ```

- [ ] **驗證 Grafana UI 訪問**
  ```bash
  curl -k https://grafana.detectviz.internal
  ```

- [ ] **驗證 Keycloak SSO 登入**
  - 訪問 Grafana UI
  - 點擊 "Sign in with Keycloak"
  - 測試登入流程

- [ ] **驗證 Datasources**
  - Grafana UI → Configuration → Data Sources
  - Test connection for Mimir, Loki, Alertmanager

- [ ] **驗證跨 Namespace 連接**
  ```bash
  # 從 Grafana pod 測試連接
  kubectl exec -it grafana-0 -n grafana -- \
    wget -O- postgresql-pgpool.postgresql.svc.cluster.local:5432

  kubectl exec -it grafana-0 -n grafana -- \
    wget -O- mimir-query-frontend.monitoring.svc.cluster.local:8080/ready
  ```

---

## 6.6 Namespace 配置完整性

### Helm Chart namespace 移除 ✅

- [x] **所有 Helm Chart 已移除 namespace 硬編碼**
  - PostgreSQL: `argocd/apps/observability/postgresql/base/kustomization.yaml`
  - Keycloak: `argocd/apps/identity/keycloak/base/kustomization.yaml`
  - Grafana: `argocd/apps/observability/grafana/base/kustomization.yaml`
  - Prometheus: `argocd/apps/observability/prometheus/base/kustomization.yaml`
  - Loki: `argocd/apps/observability/loki/base/kustomization.yaml`
  - Tempo: `argocd/apps/observability/tempo/base/kustomization.yaml`
  - Mimir: `argocd/apps/observability/mimir/base/kustomization.yaml`
  - Minio: `argocd/apps/observability/minio/base/kustomization.yaml`

### ApplicationSet 配置 ✅

- [x] **ApplicationSet 配置**
  - 文件: `argocd/appsets/apps-appset.yaml`
  - Generator: Git directories
  - Paths:
    - `argocd/apps/observability/*` → namespace: `{{path.basename}}`
    - `argocd/apps/identity/*` → namespace: `{{path.basename}}`
  - Sync Policy: manual (需手動同步)

- [x] **預期自動生成的 Applications**
  - `postgresql` → namespace: `postgresql`
  - `keycloak` → namespace: `keycloak`
  - `grafana` → namespace: `grafana`
  - `prometheus` → namespace: `prometheus` (⚠️ 應該是 monitoring)
  - `loki` → namespace: `loki` (⚠️ 應該是 monitoring)
  - `tempo` → namespace: `tempo` (⚠️ 應該是 monitoring)
  - `mimir` → namespace: `mimir` (⚠️ 應該是 monitoring)
  - `minio` → namespace: `minio` (⚠️ 應該是 monitoring)
  - `alertmanager` → namespace: `alertmanager` (⚠️ 應該是 monitoring)
  - `node-exporter` → (已刪除)
  - `pgbouncer-hpa` → namespace: `pgbouncer-hpa` (⚠️ 應該是 monitoring 或 postgresql)

**⚠️ 問題發現**: ApplicationSet 使用 `{{path.basename}}` 會為每個目錄創建獨立 namespace，這與期望的架構不符！

### 待修正: ApplicationSet Generator ⚠️

- [ ] **修正 ApplicationSet 以支持統一 monitoring namespace**
  - 方案 A: 將所有 observability 組件移動到 `argocd/apps/observability/monitoring/*` 子目錄
  - 方案 B: 修改 ApplicationSet 使用 list generator 明確指定 namespace mapping
  - 方案 C: 使用兩個 ApplicationSet (observability-appset, platform-appset)

---

# Phase 7: 最終驗證

## 7.1 部署前驗證

### ArgoCD 檢查

- [ ] **檢查 ApplicationSet**
  ```bash
  kubectl get applicationset apps-appset -n argocd
  kubectl describe applicationset apps-appset -n argocd
  ```

- [ ] **檢查自動生成的 Applications**
  ```bash
  kubectl get applications -n argocd | grep -E "postgresql|keycloak|grafana|prometheus|loki|tempo|mimir"
  ```

### Vault Secrets 檢查

- [ ] **驗證 Vault secrets 已初始化**
  ```bash
  # 檢查 PostgreSQL secrets
  vault kv get secret/postgresql/admin
  vault kv get secret/postgresql/initdb

  # 檢查 Keycloak secrets
  vault kv get secret/keycloak/database

  # 檢查 Grafana secrets
  vault kv get secret/grafana/admin
  vault kv get secret/grafana/database
  vault kv get secret/grafana/oauth

  # 檢查 Minio secrets
  vault kv get secret/monitoring/minio
  ```

---

## 7.2 部署驗證

### Namespace 驗證

- [ ] **驗證 Namespace 創建**
  ```bash
  kubectl get namespaces | grep -E "postgresql|keycloak|grafana|monitoring"

  # 預期輸出:
  # postgresql    Active   Xm
  # keycloak      Active   Xm
  # grafana       Active   Xm
  # monitoring    Active   Xm
  ```

### ExternalSecrets 驗證

- [ ] **驗證 ExternalSecrets 同步**
  ```bash
  # PostgreSQL
  kubectl get externalsecrets -n postgresql
  kubectl get secrets -n postgresql | grep detectviz

  # Keycloak
  kubectl get externalsecrets -n keycloak
  kubectl get secrets -n keycloak | grep keycloak

  # Grafana
  kubectl get externalsecrets -n grafana
  kubectl get secrets -n grafana | grep grafana

  # Monitoring
  kubectl get externalsecrets -n monitoring
  kubectl get secrets -n monitoring | grep minio
  ```

### 應用健康狀態

- [ ] **驗證所有 Pods Running**
  ```bash
  # PostgreSQL
  kubectl get pods -n postgresql
  # 預期: postgresql-ha-postgresql-{0,1,2}, postgresql-ha-pgpool-{0,1}

  # Keycloak
  kubectl get pods -n keycloak
  # 預期: keycloak-0

  # Grafana
  kubectl get pods -n grafana
  # 預期: grafana-{0,1}

  # Monitoring
  kubectl get pods -n monitoring
  # 預期: prometheus, alertmanager, loki, tempo, mimir, alloy, minio pods
  ```

### 服務連接驗證

- [ ] **驗證跨 Namespace 服務連接**
  ```bash
  # Grafana → PostgreSQL
  kubectl exec -it grafana-0 -n grafana -- \
    nc -zv postgresql-pgpool.postgresql.svc.cluster.local 5432

  # Grafana → Mimir
  kubectl exec -it grafana-0 -n grafana -- \
    wget -O- http://mimir-query-frontend.monitoring.svc.cluster.local:8080/ready

  # Grafana → Loki
  kubectl exec -it grafana-0 -n grafana -- \
    wget -O- http://loki-gateway.monitoring.svc.cluster.local:80/ready

  # Prometheus → Mimir
  kubectl exec -it prometheus-0 -n monitoring -- \
    wget -O- http://mimir-distributor.monitoring.svc.cluster.local:8080/ready
  ```

### Ingress 驗證

- [ ] **驗證 Ingress 創建**
  ```bash
  kubectl get ingress -A

  # 預期輸出:
  # NAMESPACE   NAME       CLASS   HOSTS
  # grafana     grafana    nginx   grafana.detectviz.internal
  # keycloak    keycloak   nginx   keycloak.detectviz.internal
  # argocd      argocd     nginx   argocd.detectviz.internal
  # monitoring  prometheus nginx   prometheus.detectviz.internal
  ```

- [ ] **驗證 HTTPS 訪問**
  ```bash
  curl -k https://grafana.detectviz.internal
  curl -k https://keycloak.detectviz.internal
  curl -k https://prometheus.detectviz.internal
  ```

### 功能驗證

- [ ] **驗證 Grafana OAuth2 登入**
  1. 訪問 `https://grafana.detectviz.internal`
  2. 點擊 "Sign in with Keycloak"
  3. 輸入 Keycloak 用戶憑證
  4. 驗證成功重定向到 Grafana

- [ ] **驗證 Grafana Datasources**
  1. Grafana UI → Configuration → Data Sources
  2. 測試 Mimir 連接
  3. 測試 Loki 連接
  4. 測試 Alertmanager 連接

- [ ] **驗證 Prometheus Metrics**
  1. 訪問 `https://prometheus.detectviz.internal`
  2. 查詢 `up` metric
  3. 驗證所有 targets 正常

- [ ] **驗證 Loki Logs**
  1. Grafana → Explore → Loki
  2. 查詢: `{namespace="monitoring"}`
  3. 驗證日誌正常收集

---

# Phase 8: Platform Governance (未來實施)

## 8.1 ArgoCD Webhook

- [ ] **GitHub Webhook 配置**
  - GitHub Repo Settings → Webhooks
  - Payload URL: `https://argocd.detectviz.internal/api/webhook`
  - Content type: `application/json`
  - Secret: 存儲於 Vault `secret/argocd/webhook/token`

- [ ] **Webhook Secret 管理**
  - 創建 ExternalSecret 從 Vault 同步
  - ArgoCD ConfigMap 引用 Secret

- [ ] **測試 Webhook**
  ```bash
  git commit -m "test webhook"
  git push
  # 驗證 ArgoCD 自動同步
  ```

---

## 8.2 ArgoCD RBAC

- [ ] **RBAC Policy 配置**
  - 文件: `argocd/apps/infrastructure/argocd/overlays/argocd-rbac-cm.yaml`
  - Roles: Admin, Editor, Viewer
  - Group mapping via Keycloak

- [ ] **Team-based AppProject**
  - 創建 AppProject for different teams
  - RBAC 限制每個 team 的訪問範圍

---

## 8.3 NetworkPolicy

- [ ] **Namespace 隔離 NetworkPolicy**
  - Default deny all ingress/egress
  - 明確允許跨 namespace 服務通信
  - 允許 Prometheus scraping
  - 允許 DNS resolution

---

## 8.4 Infrastructure Exporters

### Proxmox VE Exporter

- [ ] **Proxmox Host systemd service**
  - 安裝 prometheus-pve-exporter
  - 配置 systemd service
  - 暴露 metrics endpoint

### IPMI Exporter

- [ ] **K8s Deployment in monitoring namespace**
  - 創建 Deployment manifest
  - 配置 IPMI 連接
  - ServiceMonitor 配置 (已在 Prometheus values.yaml)

---

## 8.5 Observability Dashboards

- [ ] **Dashboard Provisioning as Code**
  - 創建 dashboard JSON files
  - 使用 ConfigMap 或 GitOps sync
  - Grafana dashboard providers 配置

- [ ] **Folder Structure**
  - Infrastructure dashboards
  - Application dashboards
  - Platform dashboards

---

**狀態總結**:
- ✅ **Phase 6 配置完成**: 所有 manifests 已正確配置
- ⚠️ **待修正**: ApplicationSet generator (monitoring namespace 問題)
- ⚠️ **待補充**: Loki/Tempo/Mimir 詳細配置驗證
- ⚠️ **待補充**: Keycloak Realm 配置
- ⚠️ **待補充**: Grafana Dashboard Provisioning
- 🔜 **下一步**: 初始化 Vault secrets 後開始部署驗證

---

**最後更新**: 2025-11-16
**維護**: 隨配置和部署進度持續更新
