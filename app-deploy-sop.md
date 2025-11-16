# DetectViz GitOps Application Deployment Guide

**基於架構**: `README.md` (4 VM 混合負載模型 + 雙網路架構)
**基於流程**: `infra-deploy-sop.md`

本文件提供完整的部署流程，從 Kubernetes 集群啟動的應用部署到最終驗證的所有步驟。故障排除紀錄在 `app-deploy-troubleshooting.md` 中。

---

## 目錄

- [Phase 6: 應用部署](#phase-6-應用部署)
- [Phase 7: 最終驗證](#phase-7-最終驗證)

## Phase 6: 應用部署

**目標**: 同步觀測性堆疊、身份認證與應用服務

#### 6.0 Secrets 準備 (必須先執行)

**🔐 重要**: 應用部署需要預先創建多個 Kubernetes Secrets,否則部署會失敗。

**執行 Secret 初始化腳本**:

```bash
# 確保連接到正確的集群
kubectl cluster-info

# 執行自動化 Secret 創建腳本
./scripts/bootstrap-app-secrets.sh
```

**腳本會創建以下 Secrets**:

1. **PostgreSQL Secrets** (命名空間: `postgresql`)
   - `detectviz-postgresql-admin` - 管理員密碼
   - `detectviz-pgpool-users` - Pgpool 用戶密碼
   - `detectviz-postgresql-initdb` - 初始化 SQL (創建 Grafana 資料庫)

2. **Grafana Secrets** (命名空間: `grafana`)
   - `grafana-admin` - Grafana 管理員帳號
   - `grafana-database` - PostgreSQL 連接資訊

3. **Keycloak Secrets** (命名空間: `keycloak`) - 可選
   - `keycloak-admin` - Keycloak 管理員帳號
   - `keycloak-database` - PostgreSQL 連接資訊

**手動創建 Secrets (如果腳本無法使用)**:

```bash
# PostgreSQL 管理員密碼
kubectl create secret generic detectviz-postgresql-admin \
  -n postgresql \
  --from-literal=postgres-password='<your-password>' \
  --from-literal=password='<app-password>' \
  --from-literal=repmgr-password='<repmgr-password>'

# Grafana 管理員帳號
kubectl create secret generic grafana-admin \
  -n grafana \
  --from-literal=admin-user='admin' \
  --from-literal=admin-password='<your-password>'

# Grafana 資料庫連接
kubectl create secret generic grafana-database \
  -n grafana \
  --from-literal=GF_DATABASE_TYPE=postgres \
  --from-literal=GF_DATABASE_HOST=postgresql-pgpool.postgresql.svc.cluster.local:5432 \
  --from-literal=GF_DATABASE_NAME=grafana \
  --from-literal=GF_DATABASE_USER=grafana \
  --from-literal=GF_DATABASE_PASSWORD='<grafana-db-password>' \
  --from-literal=GF_DATABASE_SSL_MODE=disable
```

**驗證 Secrets 創建成功**:

```bash
# 檢查 PostgreSQL Secrets
kubectl get secrets -n postgresql | grep detectviz

# 檢查 Grafana Secrets
kubectl get secrets -n grafana | grep grafana

# 預期輸出:
# detectviz-postgresql-admin    Opaque   3      1m
# detectviz-pgpool-users         Opaque   1      1m
# detectviz-postgresql-initdb    Opaque   1      1m
# grafana-admin                  Opaque   2      1m
# grafana-database               Opaque   6      1m
```

**⚠️ 密碼管理注意事項**:

- 腳本會自動生成強隨機密碼並顯示在控制台
- **請妥善保存這些密碼!** 建議使用密碼管理器
- 生產環境建議使用 [External Secrets Operator](https://external-secrets.io/) + Vault 管理 Secrets
- 相關文檔: `docs/app-guide/postgresql.md`, `docs/app-guide/grafana.md`

---

#### 6.1 前置檢查

確認應用層 ApplicationSet 已啟用：

```bash
# 檢查 apps-appset ApplicationSet 是否存在
kubectl get applicationset apps-appset -n argocd

# 檢查應用 Applications 是否已生成
kubectl get applications -n argocd | grep -E "postgresql|keycloak|prometheus|grafana"
```

**預期輸出**: 應該看到以下 Applications（狀態可能為 Unknown 或 OutOfSync）:
- `postgresql` - PostgreSQL HA 資料庫
- `keycloak` - 身份認證與 SSO
- `prometheus` - Prometheus + Alertmanager + Node Exporter
- `loki` - 日誌聚合
- `tempo` - 分散式追蹤
- `mimir` - 長期指標儲存
- `grafana` - 監控可視化
- `alertmanager` - 告警管理
- `node-exporter` - 節點指標收集
- `pgbouncer-hpa` - PostgreSQL 連接池

**如果沒有看到這些 Applications**:
```bash
# 刷新 root application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 等待 30 秒後再次檢查
sleep 30 && kubectl get applications -n argocd
```

---

#### 6.1 應用部署順序說明

**重要**: 應用之間有依賴關係，必須按以下順序部署：

```
階段 1: 基礎服務
  └─ postgresql (資料庫) ← 被 keycloak 和 grafana 依賴

階段 2: 身份認證
  └─ keycloak (SSO/OAuth2) ← 依賴 postgresql，為 grafana 提供 OAuth2

階段 3: 觀測性基礎設施
  ├─ prometheus (指標收集)
  ├─ loki (日誌聚合)
  ├─ tempo (分散式追蹤)
  └─ mimir (長期指標儲存)

階段 4: 可視化
  └─ grafana (監控儀表板) ← 依賴 postgresql (存儲), keycloak (OAuth2), prometheus/loki/tempo/mimir (資料源)

階段 5: 輔助服務
  ├─ alertmanager (告警管理)
  ├─ node-exporter (節點指標)
  └─ pgbouncer-hpa (PostgreSQL 連接池)
```

---

#### 6.2 階段 1: 部署 PostgreSQL (資料庫)

**優先級**: 🔴 最高（被 keycloak 和 grafana 依賴）

```bash
# 選項 1: 通過 ArgoCD UI
# 1. 訪問 https://argocd.detectviz.internal
# 2. 找到 "postgresql" Application
# 3. 點擊 "SYNC" 按鈕
# 4. 等待同步完成

# 選項 2: 通過 kubectl
kubectl patch application postgresql -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=postgresql-ha -n postgresql --timeout=300s

# 驗證 PostgreSQL 部署
kubectl get pods -n postgresql
kubectl get svc -n postgresql
kubectl get pvc -n postgresql
```

**預期結果**:
```
NAME                          READY   STATUS    RESTARTS   AGE
postgresql-ha-pgpool-0        1/1     Running   0          2m
postgresql-ha-postgresql-0    1/1     Running   0          2m
postgresql-ha-postgresql-1    1/1     Running   0          1m
```

**故障排除**:
- 如果 pods 一直 Pending: 檢查 PVC 是否綁定（`kubectl get pvc -n postgresql`）
- 如果 PVC 一直 Pending: 檢查 TopoLVM 是否正常運行（參見 Phase 4.7）

---

#### 6.3 階段 2: 部署 Keycloak (身份認證)

**優先級**: 🟠 高（依賴 postgresql，為 grafana 提供 OAuth2）

```bash
# 同步 keycloak
kubectl patch application keycloak -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s

# 驗證 Keycloak 部署
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get ingress -n keycloak
```

**預期結果**:
```
NAME          READY   STATUS    RESTARTS   AGE
keycloak-0    1/1     Running   0          2m
```

**訪問 Keycloak**:
```bash
# 獲取 admin 密碼（如果配置了 secret）
kubectl get secret keycloak -n keycloak -o jsonpath='{.data.admin-password}' | base64 -d

# 訪問 UI
# URL: https://keycloak.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)
```

**後續配置** (可選，視需求而定):
- 創建 Realm: `detectviz`
- 配置 OAuth2 Client: `grafana`
- 設置用戶和角色

---

#### 6.4 階段 3: 部署觀測性基礎設施

**優先級**: 🟡 中

```bash
# 並行同步觀測性組件（無相互依賴）
kubectl patch application prometheus -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application loki -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application tempo -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

kubectl patch application mimir -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge &

wait  # 等待所有背景任務完成

# 驗證部署
kubectl get pods -n prometheus
kubectl get pods -n loki
kubectl get pods -n tempo
kubectl get pods -n mimir
```

**預期結果** (各命名空間):
```
# Prometheus namespace
prometheus-kube-prometheus-operator-*        1/1     Running
prometheus-kube-state-metrics-*              1/1     Running
prometheus-prometheus-node-exporter-*        1/1     Running (每個節點一個)
alertmanager-*                               1/1     Running
prometheus-*                                 1/1     Running

# Loki namespace
loki-*                                       1/1     Running

# Tempo namespace
tempo-*                                      1/1     Running

# Mimir namespace
mimir-*                                      多個 pods (分散式架構)
```

---

#### 6.5 階段 4: 部署 Grafana (可視化)

**優先級**: 🟢 低（依賴所有前面的服務）

**先決條件確認**:
```bash
# 確認 PostgreSQL 正在運行
kubectl get pods -n postgresql -l app.kubernetes.io/name=postgresql-ha

# 確認 Keycloak 正在運行
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak

# 確認資料源正在運行
kubectl get pods -n prometheus -l app.kubernetes.io/name=prometheus
kubectl get pods -n loki -l app.kubernetes.io/name=loki
kubectl get pods -n tempo -l app.kubernetes.io/name=tempo
kubectl get pods -n mimir -l app.kubernetes.io/name=mimir
```

**部署 Grafana**:
```bash
# 同步 grafana
kubectl patch application grafana -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# 等待部署完成
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n grafana --timeout=300s

# 驗證 Grafana 部署
kubectl get pods -n grafana
kubectl get svc -n grafana
kubectl get ingress -n grafana
```

**訪問 Grafana**:
```bash
# 獲取 admin 密碼
kubectl get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d

# 訪問 UI
# URL: https://grafana.detectviz.internal
# Username: admin
# Password: (上面獲取的密碼)
```

**Grafana 集成配置** (values.yaml 應已配置):
- ✅ **資料庫**: PostgreSQL (用於存儲 dashboards, users, sessions)
- ✅ **OAuth2**: Keycloak (SSO 登入)
- ✅ **資料源**:
  - Prometheus (指標查詢)
  - Loki (日誌查詢)
  - Tempo (追蹤查詢)
  - Mimir (長期指標查詢)

---

#### 6.6 階段 5: 部署輔助服務 (可選)

```bash
# Alertmanager (如果不是 prometheus 的一部分)
kubectl patch application alertmanager -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# Node Exporter (如果不是 prometheus 的一部分)
kubectl patch application node-exporter -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

# PgBouncer (PostgreSQL 連接池)
kubectl patch application pgbouncer-hpa -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge
```

---

#### 6.7 最終驗證

```bash
# 檢查所有應用狀態
kubectl get applications -n argocd

# 檢查所有 pods
kubectl get pods -A | grep -E "postgresql|keycloak|prometheus|loki|tempo|mimir|grafana"

# 檢查所有服務
kubectl get svc -A | grep -E "postgresql|keycloak|prometheus|loki|tempo|mimir|grafana"

# 檢查所有 Ingress
kubectl get ingress -A
```

**預期結果**: 所有 Applications 應該為 `Synced, Healthy`

**服務訪問 URLs**:
- ArgoCD: https://argocd.detectviz.internal
- Keycloak: https://keycloak.detectviz.internal
- Grafana: https://grafana.detectviz.internal
- Prometheus: https://prometheus.detectviz.internal
- Alertmanager: https://alertmanager.detectviz.internal

---

#### 6.8 常見問題處理

**問題 1: Applications 顯示 Unknown 或 OutOfSync**

```bash
# 刷新特定 application
kubectl patch application <app-name> -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 強制同步
kubectl patch application <app-name> -n argocd \
  -p='{"operation":{"sync":{"prune":true,"force":true}}}' --type=merge
```

**問題 2: Helm chart 下載失敗**

確認 ArgoCD 已啟用 Helm 支持：
```bash
kubectl get configmap argocd-cm -n argocd -o yaml | grep "kustomize.buildOptions"
# 應該看到: kustomize.buildOptions: "--enable-helm"
```

**問題 3: PVC 無法綁定**

檢查 TopoLVM 和 StorageClass：
```bash
kubectl get csistoragecapacity -A
kubectl get storageclass topolvm-provisioner
kubectl get pods -n topolvm-system
```

**問題 4: Grafana 無法連接 PostgreSQL**

檢查資料庫服務和密碼：
```bash
kubectl get svc -n postgresql
kubectl get secret -n grafana | grep postgres
kubectl logs -n grafana -l app.kubernetes.io/name=grafana --tail=50
```

---

## Phase 7: 最終驗證

#### 7.1 集群健康檢查

```bash
# 檢查所有節點
kubectl get nodes -o wide

# 檢查所有 Pods
kubectl get pods -A -o wide

# 檢查失敗的 Pods
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# 檢查事件
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

#### 7.2 網路驗證

```bash
# 驗證雙網路配置
./scripts/validate-dual-network.sh

# 檢查 MetalLB IP 池
kubectl get ipaddresspool -n metallb-system

# 檢查 Ingress
kubectl get ingress -A
```

#### 7.3 DNS 驗證

```bash
# 從 VM 測試 DNS
ssh ubuntu@192.168.0.11 'nslookup argocd.detectviz.internal 192.168.0.2'
ssh ubuntu@192.168.0.11 'nslookup master-1.cluster.internal 192.168.0.2'

# 從本機測試 (如果已配置 /etc/hosts)
curl -k https://argocd.detectviz.internal
curl -k https://grafana.detectviz.internal
```

#### 7.4 存取服務 UI

| 服務 | URL | 用途 |
|------|-----|------|
| ArgoCD | https://argocd.detectviz.internal | GitOps 管理 |
| Grafana | https://grafana.detectviz.internal | 監控儀表板 |
| Prometheus | https://prometheus.detectviz.internal | 指標查詢 |
| Loki | https://loki.detectviz.internal | 日誌查詢 |
| Tempo | https://tempo.detectviz.internal | 追蹤查詢 |
| PgAdmin | https://pgadmin.detectviz.internal | 資料庫管理 |

#### 7.5 效能驗證

```bash
# 檢查資源使用情況
kubectl top nodes
kubectl top pods -A

# 檢查儲存
kubectl get pvc -A
kubectl get pv

# 檢查網路策略
kubectl get networkpolicies -A
```