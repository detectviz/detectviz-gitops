# 應用配置注意事項

**創建日期**: 2025-11-15 00:22
**目的**: 記錄應用配置的重要依賴和集成點

---

## 🔗 應用依賴關係

### 數據庫依賴

#### PostgreSQL (基礎服務)
```
postgresql
    ├── keycloak (使用 postgresql 存儲用戶數據)
    └── grafana (使用 postgresql 存儲 dashboard 和配置)
```

**部署優先級**: 🔴 最高 (必須首先部署)

**配置要點**:
- HA 模式 (參考: `keep/references/bitnami-postgresql-ha/`)
- 持久化存儲 (使用 TopoLVM)
- 資料庫和用戶創建:
  - `keycloak` 資料庫
  - `grafana` 資料庫

#### Pgpool 映像版本鎖定
- `argocd/apps/observability/postgresql/overlays/production/kustomization.yaml` 將 Helm Chart 版本固定在 `bitnami/postgresql-ha` `12.8.2`，由 Chart 預設決定 Pgpool 映像，禁止再在 base values 覆寫 `image.tag`。【F:argocd/apps/observability/postgresql/overlays/production/kustomization.yaml†L1-L15】
- 透過 `curl -s https://raw.githubusercontent.com/bitnami/charts/main/bitnami/postgresql-ha/Chart.yaml | grep -n pgpool` 可驗證該版本對應 `docker.io/bitnami/pgpool:4.6.3-debian-12-r0`，確保供應的 tag 為官方已發布版本。【29a028†L1-L9】
- 若需測試不同 Pgpool 版本，請於 `overlays/test` 或新的臨時 overlay 加上 `valuesFile` 覆寫，完成 `kustomize build --enable-helm` 驗證後再提交，避免影響生產部署的重現性。

### 身份認證依賴

#### Keycloak (SSO/OAuth2 Provider)
```
keycloak
    └── grafana (OAuth2 認證)
```

**部署優先級**: 🟠 高 (在 postgresql 之後,grafana 之前)

**配置要點**:
- 連接 postgresql 資料庫
- 配置 realm 和 client
- 為 Grafana 創建 OAuth2 client:
  - Client ID: `grafana`
  - Client Secret: (存儲在 Vault)
  - Redirect URLs: `https://grafana.detectviz.internal/login/generic_oauth`

**Grafana 集成配置**:
```yaml
# grafana values.yaml
grafana:
  auth:
    generic_oauth:
      enabled: true
      name: Keycloak
      client_id: grafana
      client_secret: ${KEYCLOAK_CLIENT_SECRET}  # 從 Vault 獲取
      scopes: openid email profile
      auth_url: https://keycloak.detectviz.internal/realms/{realm}/protocol/openid-connect/auth
      token_url: https://keycloak.detectviz.internal/realms/{realm}/protocol/openid-connect/token
      api_url: https://keycloak.detectviz.internal/realms/{realm}/protocol/openid-connect/userinfo
      role_attribute_path: contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'
```

### 數據源依賴

#### Grafana (可視化平台)
```
grafana
    ├── postgresql (儲存)
    ├── keycloak (OAuth2 認證)
    ├── prometheus (指標數據源)
    ├── loki (日誌數據源)
    ├── tempo (追蹤數據源)
    └── mimir (長期指標數據源)
```

**部署優先級**: 🟢 低 (最後部署,等待所有依賴就緒)

**配置要點**:
- 預配置數據源 (provisioning):
  ```yaml
  datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus.prometheus.svc:9090
    - name: Loki
      type: loki
      url: http://loki.loki.svc:3100
    - name: Tempo
      type: tempo
      url: http://tempo.tempo.svc:3200
    - name: Mimir
      type: prometheus
      url: http://mimir.mimir.svc:9009
  ```

---

## 📋 部署順序

### Phase 6.1: 基礎服務 (數據庫和認證)

1. **postgresql** 🔴
   - 創建 HA cluster
   - 初始化資料庫:
     - `keycloak`
     - `grafana`
   - 驗證: pods Running, databases created

2. **keycloak** 🟠
   - 連接 postgresql
   - 創建 realm
   - 配置 Grafana OAuth2 client
   - 驗證: 可訪問 Keycloak UI

### Phase 6.2: 觀測性堆疊 (數據收集)

3. **prometheus** 🟡
   - 配置 ServiceMonitors
   - 抓取基礎設施指標
   - 驗證: 指標可查詢

4. **loki** 🟡
   - 配置 log aggregation
   - 集成 Alloy (日誌收集 agent)
   - 驗證: 日誌可查詢

5. **tempo** 🟡
   - 配置追蹤收集
   - 驗證: traces 可查詢

6. **mimir** 🟡
   - 配置長期指標存儲
   - 連接 prometheus
   - 驗證: 指標寫入和查詢

### Phase 6.3: 可視化平台

7. **grafana** 🟢
   - 連接 postgresql
   - 配置 Keycloak OAuth2
   - 預配置所有數據源
   - 導入 dashboards
   - 驗證: 可通過 Keycloak 登入,所有數據源正常

---

## 🔐 Secrets 管理

### 使用 External Secrets + Vault

所有敏感配置應存儲在 Vault 中,通過 External Secrets Operator 同步到 Kubernetes:

```yaml
# Example: grafana-keycloak-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-keycloak-oauth
  namespace: grafana
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: grafana-keycloak-oauth
    creationPolicy: Owner
  data:
    - secretKey: client-secret
      remoteRef:
        key: observability/grafana/keycloak
        property: client_secret
```

### Vault Path 結構
```
secret/
├── infrastructure/
│   ├── postgresql/
│   │   ├── admin-password
│   │   └── replication-password
│   └── keycloak/
│       └── admin-password
└── observability/
    └── grafana/
        └── keycloak/
            └── client_secret
```

---

## 🌐 Ingress 配置

### 應用 Ingress 端點

```yaml
# keycloak
keycloak.detectviz.internal -> keycloak-service:80

# grafana
grafana.detectviz.internal -> grafana-service:80

# prometheus (可選,通過 Grafana 訪問)
prometheus.detectviz.internal -> prometheus-service:9090
```

**TLS 證書**: 由 cert-manager 自動管理 (使用 selfsigned-issuer)

---

## ⚙️ 資源配置建議

### PostgreSQL HA
```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 250m
  limits:
    memory: 512Mi
    cpu: 500m

persistence:
  size: 10Gi
  storageClass: topolvm-provisioner

replication:
  enabled: true
  replicas: 2
```

### Keycloak
```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 1000m

persistence:
  size: 1Gi
  storageClass: topolvm-provisioner
```

### Grafana
```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

persistence:
  size: 5Gi
  storageClass: topolvm-provisioner
```

### Prometheus
```yaml
resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 1000m

persistence:
  size: 20Gi
  storageClass: topolvm-provisioner
  retention: 15d
```

### Loki
```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

persistence:
  size: 20Gi
  storageClass: topolvm-provisioner
  retention: 7d
```

### Tempo
```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

persistence:
  size: 10Gi
  storageClass: topolvm-provisioner
  retention: 7d
```

### Mimir
```yaml
resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 1000m

persistence:
  size: 50Gi
  storageClass: topolvm-provisioner
  retention: 90d  # 長期存儲
```

---

## 📝 配置檢查清單

### PostgreSQL 部署前
- [ ] TopoLVM StorageClass 正常
- [ ] PV 空間充足 (至少 15Gi)
- [ ] 網絡策略允許跨 namespace 訪問

### Keycloak 部署前
- [ ] PostgreSQL 已就緒
- [ ] `keycloak` 資料庫已創建
- [ ] Admin 密碼存儲在 Vault
- [ ] Ingress 配置正確

### Grafana 部署前
- [ ] PostgreSQL 已就緒
- [ ] Keycloak 已就緒
- [ ] Keycloak OAuth2 client 已配置
- [ ] Client Secret 存儲在 Vault
- [ ] 所有數據源 (Prometheus/Loki/Tempo/Mimir) 已就緒

---

## 🐛 常見問題

### 1. Grafana 無法連接 Keycloak
**症狀**: OAuth2 登入失敗
**檢查**:
```bash
# 檢查 Keycloak 服務
kubectl get svc -n keycloak
# 檢查 Grafana logs
kubectl logs -n grafana -l app=grafana --tail=50
# 檢查 Keycloak client 配置
```

### 2. PostgreSQL 連接失敗
**症狀**: Keycloak/Grafana 無法啟動
**檢查**:
```bash
# 檢查 PostgreSQL pods
kubectl get pods -n postgresql
# 檢查資料庫是否創建
kubectl exec -it postgresql-0 -n postgresql -- psql -U postgres -c "\l"
# 檢查 secrets
kubectl get secret -n keycloak
```

### 3. 數據源無法連接
**症狀**: Grafana 無法查詢數據
**檢查**:
```bash
# 檢查服務端點
kubectl get endpoints -n prometheus prometheus
kubectl get endpoints -n loki loki
# 測試網絡連通性
kubectl run -it --rm debug --image=nicolaka/netshoot -n grafana -- curl http://prometheus.prometheus.svc:9090/-/healthy
```

---

## 📚 參考資源

### Helm Charts
- PostgreSQL HA: https://github.com/bitnami/charts/tree/main/bitnami/postgresql-ha
- Keycloak: https://github.com/bitnami/charts/tree/main/bitnami/keycloak
- Grafana: https://github.com/grafana/helm-charts/tree/main/charts/grafana
- Prometheus: https://github.com/prometheus-community/helm-charts
- Loki: https://github.com/grafana/loki/tree/main/production/helm
- Tempo: https://github.com/grafana/helm-charts/tree/main/charts/tempo
- Mimir: https://github.com/grafana/mimir/tree/main/operations/helm

### 本地參考
- `keep/references/bitnami-postgresql-ha/`
- `keep/references/grafana/`
- `keep/references/prometheus-helm/`
- `keep/references/loki/`
- `keep/references/mimir/`

### 配置示例
- 基礎設施層: `argocd/apps/infrastructure/` (結構參考)
- Overlay patches: `argocd/apps/observability/*/overlays/`

---

**最後更新**: 2025-11-15 00:22
**維護**: 隨著配置完成持續更新此文檔
