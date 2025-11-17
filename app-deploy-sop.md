# DetectViz GitOps Application Deployment Guide

**基於架構**: `README.md` (4 VM 混合負載模型 + 雙網路架構)
**基於流程**: `infra-deploy-sop.md`
**詳細配置**: `app-deploy-checklist.md`

本文件提供完整的應用部署流程，從 Vault Secrets 初始化到最終驗證的所有步驟。

**架構原則**: Platform Engineering - 按 namespace 隔離 (Platform Services → Application Layer → Observability Backend)

---

## 目錄

- [Phase 6: 應用部署](#phase-6-應用部署)
  - [6.0 Vault Secrets 初始化](#60-vault-secrets-初始化必須先執行)
  - [6.1 前置檢查](#61-前置檢查)
  - [6.2 部署順序說明](#62-部署順序說明)
  - [6.3 Platform Services](#63-platform-services)
  - [6.4 Observability Backend](#64-observability-backend)
  - [6.5 Application Layer](#65-application-layer)
  - [6.6 部署驗證](#66-部署驗證)
- [Phase 7: 最終驗證](#phase-7-最終驗證)

---

## Phase 6: 應用部署

**目標**: 部署 Platform Services、Observability Stack、Application Layer

**前置條件**:
- ✅ Phase 0-4 完成（基礎設施已部署）
- ✅ Phase 5 完成（Vault 已初始化並解封）
- ✅ ExternalSecrets Operator 已運行
- ✅ ClusterSecretStore `vault-backend` 已配置

---

### 6.0 Vault Secrets 初始化（必須先執行）

**🔐 重要**: 本項目使用 **Vault + ExternalSecrets Operator (ESO)** 管理所有應用 Secrets。

#### Vault Secret 路徑結構

```
secret/
├── postgresql/          → PostgreSQL namespace
│   ├── admin/          # postgres-password, app-password, repmgr-password
│   └── initdb/         # init-grafana-sql
├── keycloak/           → Keycloak namespace
│   └── database/       # password
├── grafana/            → Grafana namespace
│   ├── admin/          # user, password
│   ├── database/       # user, password
│   └── oauth/          # keycloak-client-secret
└── monitoring/         → Monitoring namespace
    └── minio/          # root-user, root-password, mimir-access-key, mimir-secret-key
```

**參考文檔**: `VAULT_PATH_STRUCTURE.md`, `app-deploy-checklist.md` (Phase 6.0, lines 79-105)

---

#### 方式 1: 使用驗證腳本（推薦）

```bash
# 執行 Vault secrets 初始化和驗證
./scripts/validate-pre-deployment.sh

# 腳本會自動:
# 1. 檢查 Vault 連接和狀態
# 2. 生成並儲存所有必需的 secrets
# 3. 驗證 ExternalSecrets 同步狀態
# 4. 顯示密碼清單（請妥善保存）
```

---

#### 方式 2: 手動創建 Vault Secrets

```bash
# 設置 Vault 環境變量
export VAULT_ADDR='http://vault.vault.svc.cluster.local:8200'
export VAULT_TOKEN='<root-token>'  # 從 Phase 5 vault-keys.json 獲取

# 1. PostgreSQL Secrets
vault kv put secret/postgresql/admin \
  postgres-password="$(openssl rand -base64 32)" \
  app-password="$(openssl rand -base64 32)" \
  repmgr-password="$(openssl rand -base64 32)"

vault kv put secret/postgresql/initdb \
  init-grafana-sql="CREATE DATABASE grafana; CREATE USER grafana WITH PASSWORD 'CHANGE_THIS'; GRANT ALL PRIVILEGES ON DATABASE grafana TO grafana;"

# 2. Keycloak Secrets
vault kv put secret/keycloak/database \
  password="$(openssl rand -base64 32)"

# 3. Grafana Secrets
vault kv put secret/grafana/admin \
  user="admin" \
  password="$(openssl rand -base64 32)"

# ⚠️ 重要: grafana database password 必須與 initdb SQL 一致
vault kv put secret/grafana/database \
  user="grafana" \
  password="CHANGE_THIS"  # 與上面 initdb SQL 的密碼相同

vault kv put secret/grafana/oauth \
  keycloak-client-secret="$(openssl rand -base64 32)"

# 4. Minio Secrets (for Mimir)
vault kv put secret/monitoring/minio \
  root-user="admin" \
  root-password="$(openssl rand -base64 32)" \
  mimir-access-key="mimir" \
  mimir-secret-key="$(openssl rand -base64 32)"
```

---

#### 驗證 Vault Secrets

```bash
# 檢查 Vault secrets 是否創建成功
vault kv get secret/postgresql/admin
vault kv get secret/postgresql/initdb
vault kv get secret/keycloak/database
vault kv get secret/grafana/admin
vault kv get secret/grafana/database
vault kv get secret/grafana/oauth
vault kv get secret/monitoring/minio

# 預期: 所有路徑都應該返回對應的鍵值
```

---

#### 驗證 ExternalSecrets 同步

```bash
# 檢查 ExternalSecrets 狀態
kubectl get externalsecrets -A

# 預期輸出示例:
# NAMESPACE    NAME                        STORE           STATUS         AGE
# postgresql   detectviz-postgresql-admin  vault-backend   SecretSynced   1m
# keycloak     keycloak-db-creds          vault-backend   SecretSynced   1m
# grafana      grafana-admin              vault-backend   SecretSynced   1m
# monitoring   minio-credentials          vault-backend   SecretSynced   1m

# 驗證 Kubernetes Secrets 已創建
kubectl get secrets -n postgresql | grep detectviz
kubectl get secrets -n keycloak | grep keycloak
kubectl get secrets -n grafana | grep grafana
kubectl get secrets -n monitoring | grep minio

# 預期: 每個 namespace 都應該有對應的 secrets
```

**⚠️ 重要提醒**:
- 妥善保存 Vault Root Token（來自 Phase 5 `vault-keys.json`）
- 妥善保存生成的所有密碼（建議使用 Bitwarden / 1Password）
- Grafana database password 必須與 PostgreSQL initdb SQL 中的密碼完全一致
- 如果 ExternalSecrets 狀態為 `SecretSyncedError`，檢查 Vault 路徑和 ClusterSecretStore 配置

---

### 6.1 前置檢查

確認應用層 ApplicationSet 已啟用：

```bash
# 檢查 apps-appset ApplicationSet
kubectl get applicationset apps-appset -n argocd

# 檢查應用 Applications 是否已生成
kubectl get applications -n argocd | grep -E "postgresql|keycloak|prometheus|grafana|loki|tempo|mimir|minio|alloy|alertmanager"
```

**預期輸出**: 應該看到以下 Applications（狀態可能為 Unknown 或 OutOfSync）:

**Platform Services**:
- `postgresql` - PostgreSQL HA 資料庫 (namespace: postgresql)
- `keycloak` - 身份認證與 SSO (namespace: keycloak)

**Application Layer**:
- `grafana` - 監控可視化 (namespace: grafana)

**Observability Backend**:
- `prometheus` - 指標收集 (namespace: monitoring)
- `loki` - 日誌聚合 (namespace: monitoring)
- `tempo` - 分散式追蹤 (namespace: monitoring)
- `mimir` - 長期指標儲存 (namespace: monitoring)
- `minio` - S3 物件儲存 (namespace: monitoring)
- `alloy` - 統一收集代理 (namespace: monitoring)
- `alertmanager` - 告警管理 (namespace: monitoring)

**如果沒有看到這些 Applications**:
```bash
# 刷新 root application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 等待 30 秒後再次檢查
sleep 30 && kubectl get applications -n argocd
```

---

### 6.2 部署順序說明

**重要**: 應用之間有依賴關係，必須按以下順序部署：

```
階段 1: Platform Services (獨立 namespace)
  └─ postgresql (namespace: postgresql)
       ├─ HA 3 replicas + Pgpool 2 replicas
       └─ 被 keycloak 和 grafana 依賴

  └─ keycloak (namespace: keycloak)
       ├─ 依賴 postgresql
       └─ 提供 OAuth2 for grafana/argocd

階段 2: Observability Backend (統一 monitoring namespace)
  ├─ minio (S3 storage)
  │    └─ 被 mimir 依賴
  │
  ├─ prometheus (2 replicas, 15天 retention)
  │    └─ remoteWrite to mimir
  │
  ├─ loki (TSDB, 30天 retention, 2 replicas)
  ├─ tempo (OTLP receivers, 30天 retention, 2 replicas)
  ├─ mimir (S3/Minio backend, HA 2 replicas)
  ├─ alloy (DaemonSet, 取代 node-exporter)
  │    ├─ host metrics → prometheus
  │    ├─ pod logs → loki
  │    └─ systemd logs → loki
  │
  └─ alertmanager (3 replicas)

階段 3: Application Layer (獨立 namespace)
  └─ grafana (namespace: grafana, HA 2 replicas)
       ├─ 依賴 postgresql (存儲)
       ├─ 依賴 keycloak (OAuth2)
       └─ 依賴 mimir/loki/tempo (資料源)
```

---

### 6.3 Platform Services

#### 6.3.1 部署 PostgreSQL

**優先級**: 🔴 最高（被 keycloak 和 grafana 依賴）
**Namespace**: `postgresql`
**配置**: HA 3 replicas, Pgpool 2 replicas, 10Gi storage per replica

```bash
# 同步 PostgreSQL
kubectl patch application postgresql -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成（最多 5 分鐘）
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql-ha -n postgresql --timeout=300s

# 驗證部署
kubectl get pods -n postgresql
kubectl get svc -n postgresql
kubectl get pvc -n postgresql
```

**預期結果**:
```
NAME                          READY   STATUS    RESTARTS   AGE
postgresql-ha-postgresql-0    1/1     Running   0          2m
postgresql-ha-postgresql-1    1/1     Running   0          2m
postgresql-ha-postgresql-2    1/1     Running   0          1m
postgresql-ha-pgpool-0        1/1     Running   0          2m
postgresql-ha-pgpool-1        1/1     Running   0          2m
```

**驗證 Replication**:
```bash
kubectl exec -it postgresql-ha-postgresql-0 -n postgresql -- \
  psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# 預期: 應該看到 2 個 standby 節點的 replication 狀態
```

**驗證 Grafana Database**:
```bash
kubectl exec -it postgresql-ha-postgresql-0 -n postgresql -- \
  psql -U postgres -c "\l" | grep grafana

# 預期: grafana | grafana | UTF8
```

**故障排除**:
- Pods 一直 Pending: 檢查 PVC 綁定狀態 `kubectl get pvc -n postgresql`
- PVC 一直 Pending: 檢查 TopoLVM `kubectl get pods -n topolvm-system`
- Replication 失敗: 檢查 logs `kubectl logs postgresql-ha-postgresql-1 -n postgresql`

---

#### 6.3.2 部署 Keycloak

**優先級**: 🟠 高（依賴 postgresql，為 grafana 提供 OAuth2）
**Namespace**: `keycloak`
**配置**: 2 replicas, External PostgreSQL, Realm auto-import

```bash
# 同步 Keycloak
kubectl patch application keycloak -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# 驗證部署
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
```

**預期結果**:
```
NAME         READY   STATUS    RESTARTS   AGE
keycloak-0   1/1     Running   0          3m
keycloak-1   1/1     Running   0          2m
```

**訪問 Keycloak UI**:
```bash
# 獲取 admin 密碼（如果使用 Vault）
kubectl get secret keycloak-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d

# 訪問 UI
# URL: https://keycloak.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)
```

**驗證 Realm 自動導入**:
```bash
# 檢查 keycloak-config-cli 日誌
kubectl logs -n keycloak keycloak-0 -c keycloak-config-cli

# 預期輸出:
# "Realm 'detectviz' created/updated successfully"
# "Client 'grafana' created/updated"
# "Client 'argocd' created/updated"
```

**手動驗證 Realm 配置** (可選):
1. 登入 Keycloak Admin Console
2. 選擇 Realm: `detectviz`
3. 檢查 Clients:
   - `grafana` - Valid Redirect URIs: `https://grafana.detectviz.internal/*`, `https://grafana.detectviz.com/*`
   - `argocd` - Valid Redirect URIs: `https://argocd.detectviz.internal/auth/callback`
4. 檢查 Roles: `admin`, `editor`, `viewer`
5. 檢查 Users: `admin@detectviz.com` (default password: `changeme`)

---

### 6.4 Observability Backend

**Namespace**: `monitoring` (所有 Observability 元件統一在此 namespace)

#### 6.4.1 部署 Minio (S3 Storage)

**優先級**: 🟡 高（被 Mimir 依賴）
**配置**: Standalone 1 replica, 100Gi storage, Auto-create buckets

```bash
# 同步 Minio
kubectl patch application minio -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=minio -n monitoring --timeout=300s

# 驗證部署
kubectl get pods -n monitoring -l app.kubernetes.io/name=minio
kubectl get svc -n monitoring -l app.kubernetes.io/name=minio
```

**預期結果**:
```
NAME      READY   STATUS    RESTARTS   AGE
minio-0   1/1     Running   0          2m
```

**驗證 Buckets 創建**:
```bash
# 獲取 Minio root password
kubectl get secret minio-root-credentials -n monitoring -o jsonpath='{.data.root-password}' | base64 -d

# Port-forward Minio Console (可選)
kubectl port-forward svc/minio 9001:9001 -n monitoring

# 訪問 http://localhost:9001
# 檢查 Buckets: mimir-blocks, mimir-ruler, mimir-alertmanager
```

---

#### 6.4.2 並行部署 Observability Stack

```bash
# 並行同步所有 Observability 元件（無相互依賴，可同時部署）
kubectl patch application prometheus -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application loki -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application tempo -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application mimir -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application alloy -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application alertmanager -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

wait  # 等待所有背景任務完成

# 檢查部署狀態
kubectl get pods -n monitoring -w
# Ctrl+C 停止 watch
```

**預期結果** (monitoring namespace):
```
NAME                                     READY   STATUS    RESTARTS   AGE
prometheus-kube-prometheus-operator-*    1/1     Running   0          3m
prometheus-prometheus-0                  2/2     Running   0          2m
prometheus-prometheus-1                  2/2     Running   0          2m
alertmanager-prometheus-alertmanager-0   2/2     Running   0          2m
alertmanager-prometheus-alertmanager-1   2/2     Running   0          2m
alertmanager-prometheus-alertmanager-2   2/2     Running   0          2m

loki-distributor-*                       1/1     Running   0          2m
loki-ingester-0                          1/1     Running   0          2m
loki-ingester-1                          1/1     Running   0          2m
loki-querier-*                           1/1     Running   0          2m
loki-query-frontend-*                    1/1     Running   0          2m
loki-gateway-*                           1/1     Running   0          2m

tempo-0                                  1/1     Running   0          2m
tempo-1                                  1/1     Running   0          2m

mimir-distributor-*                      1/1     Running   0          3m
mimir-ingester-0                         1/1     Running   0          3m
mimir-ingester-1                         1/1     Running   0          3m
mimir-querier-*                          1/1     Running   0          3m
mimir-query-frontend-*                   1/1     Running   0          3m
mimir-compactor-*                        1/1     Running   0          3m

alloy-*                                  1/1     Running   0          2m  # DaemonSet, 每個節點一個
```

---

#### 6.4.3 驗證 Observability Stack

**Prometheus 驗證**:
```bash
# 檢查 Prometheus targets
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090

# 訪問 http://localhost:9090/targets
# 驗證所有 ServiceMonitors 正常

# 驗證 remoteWrite to Mimir
# 在 Prometheus UI 執行查詢: up
# 應該看到所有監控目標
```

**Loki 驗證**:
```bash
# 檢查 Loki 日誌收集
kubectl port-forward svc/loki-gateway -n monitoring 3100:80

# 使用 logcli 查詢 (或在 Grafana Explore)
curl "http://localhost:3100/loki/api/v1/query_range?query={namespace=\"monitoring\"}"

# 應該看到日誌條目
```

**Tempo 驗證**:
```bash
# 檢查 OTLP receivers
kubectl get svc -n monitoring | grep tempo

# 預期:
# tempo             ClusterIP   10.x.x.x   <none>   4318/TCP,4317/TCP   3m
# HTTP: 4318, gRPC: 4317
```

**Mimir 驗證**:
```bash
# 檢查 Mimir 連接 Minio
kubectl logs -n monitoring deployment/mimir-distributor | grep -i "minio\|s3"

# 應該看到成功連接 Minio S3 的日誌
```

**Alloy 驗證**:
```bash
# 檢查 Alloy DaemonSet
kubectl get daemonset alloy -n monitoring

# 檢查 Alloy 配置
kubectl get configmap alloy-config -n monitoring -o yaml

# 驗證 host metrics 收集
# 在 Prometheus 查詢: node_cpu_seconds_total
# 應該看到每個節點的 CPU metrics (job="node-exporter")
```

---

### 6.5 Application Layer

#### 6.5.1 部署 Grafana

**優先級**: 🟢 中（依賴所有前面的服務）
**Namespace**: `grafana`
**配置**: HA 2 replicas, PostgreSQL backend, Keycloak OAuth2, 預配置 Datasources + Dashboards

**先決條件確認**:
```bash
# 確認 PostgreSQL 正在運行
kubectl get pods -n postgresql -l app.kubernetes.io/name=postgresql-ha | grep Running

# 確認 Keycloak 正在運行
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak | grep Running

# 確認資料源正在運行
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus | grep Running
kubectl get pods -n monitoring | grep loki | grep Running
kubectl get pods -n monitoring | grep tempo | grep Running
kubectl get pods -n monitoring | grep mimir | grep Running
```

**部署 Grafana**:
```bash
# 同步 Grafana
kubectl patch application grafana -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n grafana --timeout=300s

# 驗證部署
kubectl get pods -n grafana
kubectl get svc -n grafana
kubectl get ingress -n grafana
```

**預期結果**:
```
NAME        READY   STATUS    RESTARTS   AGE
grafana-0   1/1     Running   0          2m
grafana-1   1/1     Running   0          2m
```

**訪問 Grafana UI**:
```bash
# 獲取 admin 密碼
kubectl get secret grafana-admin -n grafana -o jsonpath='{.data.password}' | base64 -d

# 訪問 UI
# URL: https://grafana.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)

# 或使用 Keycloak SSO
# 點擊 "Sign in with Keycloak"
```

**驗證 Grafana 整合**:

1. **資料庫驗證**:
```bash
# 檢查 Grafana 是否使用 PostgreSQL
kubectl logs -n grafana grafana-0 | grep -i "database"

# 預期: "Database: postgres" 或 "Connected to database"
```

2. **Datasources 驗證**:
   - 登入 Grafana UI
   - Configuration → Data Sources
   - 驗證以下 datasources 存在且狀態為 OK:
     - **Mimir** (default) - `http://mimir-query-frontend.monitoring.svc.cluster.local:8080/prometheus`
     - **Loki** - `http://loki-gateway.monitoring.svc.cluster.local:80`
     - **Tempo** - `http://tempo.monitoring.svc.cluster.local:3100`
     - **Alertmanager** - `http://prometheus-alertmanager.monitoring.svc.cluster.local:9093`

3. **Dashboard Provisioning 驗證**:
   - Dashboards → Browse
   - 驗證 3 個 folders 存在:
     - **Platform** (包含 kubernetes-cluster-overview)
     - **Infrastructure**
     - **Applications**
   - 打開 `Kubernetes Cluster Overview` dashboard
   - 驗證 6 個 panels 正常顯示數據:
     - Total Nodes
     - Unhealthy Nodes
     - Total Pods
     - Unhealthy Pods
     - CPU Usage by Node
     - Memory Usage by Node

4. **Keycloak OAuth2 驗證**:
   - 登出 Grafana
   - 點擊 "Sign in with Keycloak"
   - 使用 Keycloak 用戶登入: `admin@detectviz.com` / `changeme`
   - 驗證成功登入並顯示正確的 role (Admin)

5. **Unified Alerting HA 驗證**:
```bash
# 檢查 Grafana Alerting headless service
kubectl get svc grafana-alerting -n grafana

# 預期: ClusterIP None (headless service)

# 檢查 Grafana 日誌
kubectl logs -n grafana grafana-0 | grep -i "alerting\|ha"

# 預期: "HA mode enabled" 或類似訊息
```

---

### 6.6 部署驗證

#### 6.6.1 檢查所有 Applications

```bash
# 檢查所有應用狀態
kubectl get applications -n argocd

# 預期: 所有 Applications 應該為 Synced, Healthy
```

**預期輸出示例**:
```
NAME           SYNC STATUS   HEALTH STATUS
postgresql     Synced        Healthy
keycloak       Synced        Healthy
prometheus     Synced        Healthy
loki           Synced        Healthy
tempo          Synced        Healthy
mimir          Synced        Healthy
minio          Synced        Healthy
alloy          Synced        Healthy
alertmanager   Synced        Healthy
grafana        Synced        Healthy
```

---

#### 6.6.2 檢查所有 Pods

```bash
# 檢查所有應用 Pods
kubectl get pods -n postgresql
kubectl get pods -n keycloak
kubectl get pods -n grafana
kubectl get pods -n monitoring

# 或一次性檢查
kubectl get pods -A | grep -E "postgresql|keycloak|grafana|prometheus|loki|tempo|mimir|minio|alloy|alertmanager"
```

---

#### 6.6.3 檢查 Services 和 Ingress

```bash
# 檢查所有服務
kubectl get svc -A | grep -E "postgresql|keycloak|grafana|prometheus|loki|tempo|mimir"

# 檢查所有 Ingress
kubectl get ingress -A
```

**預期 Ingress 輸出**:
```
NAMESPACE   NAME         CLASS   HOSTS
grafana     grafana      nginx   grafana.detectviz.internal
keycloak    keycloak     nginx   keycloak.detectviz.internal
monitoring  prometheus   nginx   prometheus.detectviz.internal
```

---

#### 6.6.4 服務訪問 URLs

| 服務 | URL | 用途 | 憑證來源 |
|------|-----|------|----------|
| ArgoCD | https://argocd.detectviz.internal | GitOps 管理 | `kubectl get secret argocd-initial-admin-secret -n argocd` |
| Keycloak | https://keycloak.detectviz.internal | SSO 管理 | Vault `secret/keycloak/admin` |
| Grafana | https://grafana.detectviz.internal | 監控儀表板 | Vault `secret/grafana/admin` 或 Keycloak SSO |
| Prometheus | https://prometheus.detectviz.internal | 指標查詢 | 無需認證（內網） |

---

#### 6.6.5 驗證跨 Namespace 連接

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

# Prometheus → Mimir (remoteWrite)
kubectl exec -it prometheus-prometheus-0 -n monitoring -c prometheus -- \
  wget -O- http://mimir-distributor.monitoring.svc.cluster.local:8080/ready

# 預期: 所有連接都應該成功
```

---

#### 6.6.6 常見問題處理

**問題 1: Applications 顯示 Unknown 或 OutOfSync**

```bash
# 刷新特定 application
kubectl patch application <app-name> -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 強制同步
kubectl patch application <app-name> -n argocd \
  -p='{"operation":{"sync":{"prune":true,"force":true}}}' --type=merge
```

**問題 2: ExternalSecrets 無法同步**

```bash
# 檢查 ClusterSecretStore
kubectl get clustersecretstore vault-backend -o yaml

# 檢查 ExternalSecrets Operator logs
kubectl logs -n external-secrets-system deployment/external-secrets -f

# 檢查特定 ExternalSecret
kubectl describe externalsecret <name> -n <namespace>

# 常見原因:
# - Vault 未運行或已 sealed
# - ClusterSecretStore 認證失敗
# - Vault 路徑不存在或拼寫錯誤
```

**問題 3: Helm chart 下載失敗**

```bash
# 確認 ArgoCD 已啟用 Helm 支持
kubectl get configmap argocd-cm -n argocd -o yaml | grep "kustomize.buildOptions"

# 應該看到: kustomize.buildOptions: "--enable-helm"
```

**問題 4: PVC 無法綁定**

```bash
# 檢查 TopoLVM
kubectl get pods -n topolvm-system
kubectl get csistoragecapacity -A
kubectl get storageclass topolvm-provisioner

# 檢查 PVC 詳情
kubectl describe pvc <pvc-name> -n <namespace>
```

**問題 5: Grafana 無法連接 PostgreSQL**

```bash
# 檢查 PostgreSQL 服務
kubectl get svc -n postgresql

# 檢查 Grafana database secret
kubectl get secret grafana-database -n grafana -o yaml

# 檢查 Grafana logs
kubectl logs -n grafana grafana-0 | grep -i "database\|postgres"

# 驗證密碼一致性
# 1. 檢查 Vault secret/postgresql/initdb 的 SQL
# 2. 檢查 Vault secret/grafana/database 的 password
# 3. 確保兩者一致
```

**問題 6: Keycloak Realm 未自動導入**

```bash
# 檢查 keycloak-config-cli logs
kubectl logs -n keycloak keycloak-0 -c keycloak-config-cli

# 檢查 realm ConfigMap
kubectl get configmap keycloak-realm-detectviz -n keycloak -o yaml

# 手動觸發 realm 導入（刪除 pod 重啟）
kubectl delete pod keycloak-0 -n keycloak
```

---

## Phase 7: 最終驗證

### 7.1 集群健康檢查

```bash
# 檢查所有節點
kubectl get nodes -o wide

# 預期: 所有節點 Ready
# master-1, master-2, master-3, app-worker

# 檢查所有 Pods
kubectl get pods -A -o wide

# 檢查失敗的 Pods
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# 預期: 無輸出（或僅 Completed jobs）

# 檢查最近事件
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

---

### 7.2 網路驗證

```bash
# 檢查 MetalLB IP 池
kubectl get ipaddresspool -n metallb-system

# 預期: default-pool (192.168.0.200-220)

# 檢查 Ingress
kubectl get ingress -A

# 檢查 cert-manager certificates
kubectl get certificate -A

# 預期: 所有 certificates Ready=True
```

---

### 7.3 DNS 驗證

```bash
# 從集群內測試 DNS
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nslookup grafana.detectviz.internal

# 從外部測試（如果配置了 DNS 或 /etc/hosts）
curl -k https://argocd.detectviz.internal
curl -k https://grafana.detectviz.internal
curl -k https://keycloak.detectviz.internal
```

---

### 7.4 Observability 功能驗證

#### Metrics 查詢（Prometheus / Mimir）

登入 Grafana → Explore → 選擇 Mimir datasource

測試查詢:
```promql
# 檢查所有節點
up{job="node-exporter"}

# 檢查 Kubernetes Pods
up{job="kubernetes-pods"}

# 檢查 CPU 使用率
rate(node_cpu_seconds_total{mode!="idle"}[5m])

# 檢查記憶體使用
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
```

---

#### Logs 查詢（Loki）

登入 Grafana → Explore → 選擇 Loki datasource

測試查詢:
```logql
# 查看 monitoring namespace 日誌
{namespace="monitoring"}

# 查看 Grafana 日誌
{namespace="grafana", app="grafana"}

# 錯誤日誌
{namespace="monitoring"} |= "error" or "Error" or "ERROR"

# systemd journal logs（來自 Alloy）
{job="systemd-journal"}
```

---

#### Traces 查詢（Tempo）

登入 Grafana → Explore → 選擇 Tempo datasource

如果有應用發送 traces 到 Tempo OTLP endpoint (4318/4317)，可以:
- Search traces by service name
- View trace timeline
- Analyze span details

**測試 OTLP endpoint**:
```bash
# 檢查 Tempo OTLP service
kubectl get svc tempo -n monitoring

# 預期:
# PORT(S): 4318/TCP (HTTP), 4317/TCP (gRPC)
```

---

### 7.5 資源使用情況

```bash
# 檢查節點資源使用
kubectl top nodes

# 檢查 Pods 資源使用
kubectl top pods -A | sort -k3 -r | head -20

# 檢查儲存使用
kubectl get pvc -A
kubectl get pv

# 預期 PV/PVC 狀態: Bound
```

---

### 7.6 部署完成檢查清單

- [ ] ✅ Vault secrets 已初始化並同步
- [ ] ✅ 所有 ExternalSecrets 狀態為 SecretSynced
- [ ] ✅ 所有 ArgoCD Applications 為 Synced + Healthy
- [ ] ✅ 所有 Pods 為 Running 或 Completed
- [ ] ✅ PostgreSQL HA 正常運行（3 replicas + 2 pgpool）
- [ ] ✅ Keycloak 正常運行，Realm `detectviz` 已導入
- [ ] ✅ Grafana 正常運行，可透過 Keycloak SSO 登入
- [ ] ✅ Grafana Datasources 全部 OK (Mimir, Loki, Tempo, Alertmanager)
- [ ] ✅ Grafana Dashboards 已 provisioned（3 folders）
- [ ] ✅ Prometheus 正常收集 metrics 並 remoteWrite 到 Mimir
- [ ] ✅ Loki 正常收集 logs (via Alloy)
- [ ] ✅ Tempo OTLP receivers 正常運行
- [ ] ✅ Alloy DaemonSet 在所有節點運行
- [ ] ✅ Mimir 連接 Minio S3 storage
- [ ] ✅ 所有 Ingress 可正常訪問
- [ ] ✅ 跨 Namespace 服務連接正常

---

**部署完成！** 🎉

下一步:
- **Phase 6.7**: ArgoCD Keycloak SSO 整合 (參考 `docs/app-guide/sso-domain-migration-plan.md`)
- **Phase 6.8**: Grafana 域名遷移到 `detectviz.com`
- **Phase 8**: Platform Governance (NetworkPolicy, RBAC, Infrastructure Exporters)

**文檔參考**:
- 詳細配置: `app-deploy-checklist.md`
- Vault 路徑規範: `VAULT_PATH_STRUCTURE.md`
- 應用配置說明: `APP_CONFIG_NOTES.md`
- SSO 遷移計劃: `docs/app-guide/sso-domain-migration-plan.md`
- Dashboard 管理: `argocd/apps/observability/grafana/overlays/dashboards/README.md`
