# 應用配置優化分析報告

基於 docs/app-guide 指南與當前配置的對比分析

---

## 📊 發現的配置差異

### 1. 命名空間配置差異 ⚠️

**指南要求 vs 當前配置**:

| 應用 | 指南要求 | 當前配置 | 狀態 |
|------|----------|----------|------|
| PostgreSQL | `detectviz` | `postgresql` | ⚠️ 不一致 |
| Grafana | `monitoring` | `grafana` | ⚠️ 不一致 |
| Prometheus | `monitoring` | `prometheus` | ⚠️ 不一致 |
| Loki | `monitoring` | `loki` | ⚠️ 不一致 |
| Mimir | `monitoring` | `mimir` | ⚠️ 不一致 |
| Alertmanager | `monitoring` | `alertmanager` | ⚠️ 不一致 |

**影響**:
- 服務發現 URL 不一致（如 `mimir-nginx.monitoring.svc` vs `mimir-nginx.mimir.svc`）
- 網路策略和 RBAC 配置需要調整
- 跨命名空間的服務通訊增加複雜度

**建議**:
```
選項 A: 統一使用 `monitoring` 命名空間（推薦）
- 優點: 符合指南，簡化管理
- 缺點: 需要大幅修改配置

選項 B: 保持當前命名空間，更新指南
- 優點: 配置改動最小
- 缺點: 與文檔不一致
```

---

### 2. StorageClass 配置缺失 🔴

**指南要求**:
- **PostgreSQL**: `detectviz-nvme`（高 I/O 性能）
- **Loki/Mimir**: `detectviz-sata`（長期存儲）
- **Prometheus**: `detectviz-sata`（推薦）

**當前狀態**: ❌ base 配置中未指定任何 StorageClass

**影響**:
- 將使用集群預設 StorageClass（可能是 `topolvm-provisioner`）
- 無法實現存儲分層（NVMe vs SATA）
- 可能導致性能不佳或存儲成本過高

**建議修復**:
```yaml
# postgresql/overlays/values.yaml 應添加
postgresql:
  persistence:
    storageClass: "detectviz-nvme"  # 或 topolvm-provisioner

pgpool:
  persistence:
    storageClass: "detectviz-nvme"

# loki/overlays/values.yaml 應添加
loki:
  persistence:
    storageClass: "detectviz-sata"  # 或 topolvm-provisioner

# mimir/overlays/values.yaml 應添加
mimir:
  persistence:
    storageClass: "detectviz-sata"  # 或 topolvm-provisioner
```

---

### 3. 高可用性配置缺失 🟠

**指南要求**:

| 組件 | 必需副本數 | 當前配置 | 狀態 |
|------|-----------|----------|------|
| PostgreSQL | 3（1主2備）+ Pgpool 2副本 | 未指定 | ⚠️ 缺失 |
| Grafana | 2 + HA Alerting | 未指定 | ⚠️ 缺失 |
| Prometheus | 2 | 未指定 | ⚠️ 缺失 |
| Alertmanager | 2-3 | 未指定 | ⚠️ 缺失 |
| Loki 關鍵組件 | 2 | 未指定 | ⚠️ 缺失 |
| Mimir 關鍵組件 | 2 | 未指定 | ⚠️ 缺失 |

**建議修復**:
```yaml
# postgresql/overlays/values.yaml
postgresql:
  replicaCount: 3
  podAntiAffinityPreset: hard

pgpool:
  replicaCount: 2
  podAntiAffinityPreset: hard

# grafana/overlays/values.yaml
replicas: 2
env:
  - name: GF_UNIFIED_ALERTING_HA_LISTEN_ADDRESS
    value: "0.0.0.0:9094"
  - name: GF_UNIFIED_ALERTING_HA_PEERS
    value: "grafana-ha-headless:9094"

# prometheus/overlays/values.yaml
prometheus:
  prometheusSpec:
    replicas: 2

alertmanager:
  alertmanagerSpec:
    replicas: 3

# loki/overlays/values.yaml
ingester:
  replicas: 2
distributor:
  replicas: 2
querier:
  replicas: 2

# mimir/overlays/values.yaml
ingester:
  replicas: 2
distributor:
  replicas: 2
querier:
  replicas: 2
```

---

### 4. 關鍵集成配置缺失 🔴

#### 4.1 Prometheus → Mimir Remote Write

**指南要求**:
```yaml
prometheus:
  prometheusSpec:
    externalLabels:
      environment: production
      cluster: detectviz-production
    
    remoteWrite:
      - url: http://mimir-nginx.monitoring.svc:80/api/v1/push
        remoteTimeout: 30s
        queueConfig:
          capacity: 20000
          maxSamplesPerSend: 1000
          maxShards: 200
```

**當前狀態**: ❌ overlays/values.yaml 中已有配置，但需要確認 URL

#### 4.2 Grafana 資料源配置

**指南要求**:
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Mimir
        type: prometheus
        url: http://mimir-nginx.monitoring.svc:80/prometheus
        isDefault: true
      
      - name: Loki
        type: loki
        url: http://loki-gateway.monitoring.svc:80
      
      - name: Alertmanager
        type: alertmanager
        url: http://kube-prometheus-stack-alertmanager.monitoring.svc:9093
```

**當前狀態**: ❌ base 配置中未包含，需要在 overlays 中添加

#### 4.3 Grafana OAuth2 配置

**指南要求**: 整合 Keycloak 進行 SSO 認證

**當前狀態**: ❌ 未配置

**建議配置**:
```yaml
# grafana/overlays/values.yaml
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: Keycloak
    allow_sign_up: true
    client_id: grafana
    client_secret: $__file{/etc/secrets/oauth_secret}
    scopes: openid profile email
    auth_url: https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/auth
    token_url: https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/token
    api_url: https://keycloak.detectviz.internal/realms/detectviz/protocol/openid-connect/userinfo
```

#### 4.4 PostgreSQL 密碼管理

**指南要求**: 必須使用 Secrets，禁止明文密碼

**需要創建的 Secrets**:
- `detectviz-postgresql-admin`: 管理員密碼
- `detectviz-pgpool-users`: Pgpool 密碼文件
- `detectviz-postgresql-initdb`: 初始化 SQL 腳本

**當前狀態**: ⚠️ overlays 已引用，但需要確保 Secret 存在

---

### 5. 監控和指標配置缺失 🟡

**指南要求**:

1. **PostgreSQL**: 必須啟用 `metrics.serviceMonitor: true`
2. **所有組件**: 必須配置 ServiceMonitor 供 Prometheus 抓取
3. **Prometheus**: 必須停用內建 Grafana (`grafana.enabled: false`)

**建議配置**:
```yaml
# postgresql/overlays/values.yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: postgresql  # 或 monitoring
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus-stack

# prometheus/overlays/values.yaml
grafana:
  enabled: false  # 必須停用，使用獨立 Grafana

prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false  # 自動發現所有 ServiceMonitor
    podMonitorSelectorNilUsesHelmValues: false
```

---

## 🎯 優先級建議

### 🔴 高優先級（影響功能）

1. **配置 StorageClass**
   - 影響: 存儲性能和成本
   - 建議: 在 overlays/values.yaml 中為所有持久化組件指定 StorageClass

2. **配置 Grafana 資料源**
   - 影響: Grafana 無法查詢指標和日誌
   - 建議: 在 grafana/overlays/values.yaml 中添加完整的資料源配置

3. **確保 PostgreSQL Secrets 存在**
   - 影響: PostgreSQL 無法啟動
   - 建議: 創建部署前置腳本生成必要的 Secrets

### 🟠 中優先級（影響可用性）

4. **配置高可用性副本數**
   - 影響: 單點故障風險
   - 建議: 在 overlays/values.yaml 中設置合理的副本數

5. **配置 Grafana OAuth2**
   - 影響: 安全性和用戶體驗
   - 建議: 整合 Keycloak SSO

6. **驗證 Prometheus → Mimir Remote Write**
   - 影響: 長期指標存儲
   - 建議: 確認 overlays 中的 URL 正確

### 🟡 低優先級（影響一致性）

7. **統一命名空間**
   - 影響: 配置一致性
   - 建議: 評估是否統一使用 `monitoring` 命名空間

8. **啟用 ServiceMonitor**
   - 影響: 組件自身的可觀測性
   - 建議: 為所有組件配置 ServiceMonitor

---

## 📋 推薦的優化步驟

### Step 1: 更新 overlays/values.yaml（不破壞現有配置）

對於每個應用，在 overlays/values.yaml 中添加缺失的關鍵配置：
- StorageClass
- 副本數
- 資源限制
- ServiceMonitor

### Step 2: 自動化 Vault Secrets（取代手動腳本）

使用 `scripts/vault-setup-observability.sh` 直接將 PostgreSQL/Grafana/Keycloak/Minio 密碼寫入 `secret/<namespace>/...`，然後執行 `scripts/validate-pre-deployment.sh` 驗證 ExternalSecret 狀態，避免再以 `kubectl create secret` 產生一次性憑證。

### Step 3: 更新 deploy.md Phase 6

添加前置步驟：
- Phase 6.0: Secret 準備
- Phase 6.1: 驗證 StorageClass
- Phase 6.2: 檢查集成配置

### Step 4: 創建驗證腳本

創建 `scripts/verify-app-configs.sh`:
- 檢查 StorageClass 是否存在
- 檢查 Secrets 是否已創建
- 驗證服務 URL 可達性

---

## 🔧 建議的配置文件結構

```
argocd/apps/observability/
├── postgresql/
│   ├── base/
│   │   └── kustomization.yaml  # ✅ 已創建，使用 Helm chart
│   └── overlays/
│       ├── kustomization.yaml
│       ├── values.yaml  # ⚠️ 需要補充 StorageClass, replicas, metrics
│       └── secrets/  # 🆕 建議新增
│           └── kustomization.yaml
│
├── grafana/
│   ├── base/
│   │   └── kustomization.yaml  # ✅ 已創建
│   └── overlays/
│       ├── kustomization.yaml
│       ├── values.yaml  # ⚠️ 需要補充 datasources, OAuth2, HA
│       └── datasources/  # 🆕 建議新增
│           └── datasources.yaml
│
└── prometheus/
    ├── base/
    │   └── kustomization.yaml  # ✅ 已創建
    └── overlays/
        ├── kustomization.yaml
        ├── values.yaml  # ⚠️ 需要補充 remoteWrite, externalLabels
        └── servicemonitors/  # 🆕 建議新增（Proxmox, IPMI）
```

---

## 💡 關鍵洞察

1. **當前 base 配置是最小化的**：只定義了 Helm chart 和版本，這是好的做法
2. **overlays 才是配置的主要位置**：所有環境特定的配置應該在 overlays 中
3. **指南反映了生產級配置**：包含 HA、監控、安全性等最佳實踐
4. **命名空間差異可能是設計選擇**：需要評估是統一還是保持隔離

---

**報告生成時間**: 2025-11-14
**配置版本**: Phase 6 - 初始部署
**下一步**: 根據優先級逐步優化 overlays 配置
