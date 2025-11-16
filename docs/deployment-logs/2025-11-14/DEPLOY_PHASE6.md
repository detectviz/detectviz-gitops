
## 架構說明：Observability Stack (Phase 6 架構變更)

### 🔄 統一命名空間架構

**所有 Observability 組件統一部署在 `monitoring` namespace**：

- Grafana (可視化前端)
- Prometheus (短期 TSDB + 指標收集)
- Mimir (長期 TSDB，Prometheus remote write 目標)
- Loki (日誌聚合)
- Tempo (分散式追蹤)
- PostgreSQL (Grafana 後端資料庫)
- Minio (Mimir 的 S3 object storage)

### 📦 StorageClass 分配策略

| 服務 | StorageClass | 節點 | 容量 |
|------|-------------|------|------|
| PostgreSQL | topolvm-provisioner | app-worker | 10Gi |
| Grafana | topolvm-provisioner | app-worker | 10Gi |
| Minio | topolvm-provisioner | app-worker | 100Gi |
| Prometheus | local-path | master-1 | 50Gi |
| Loki | local-path | master-3 | 30Gi |
| **Mimir** | **S3 (Minio)** | **-** | **-** |

### 🔥 Mimir 架構變更 (Critical Fix)

**從 Filesystem 改為 S3 Backend**：

```yaml
# ✅ 新配置
blocks_storage:
  backend: s3
  s3:
    endpoint: minio.monitoring.svc.cluster.local:9000
    bucket_name: mimir-blocks
persistentVolume:
  enabled: false  # 使用 S3
```

**優點**：可擴展儲存、Compactor 正常運作、無數據丟失風險

### 🔗 服務 URL (所有組件在 monitoring namespace)

```
Mimir: http://mimir-distributor.monitoring.svc.cluster.local:8080
Loki: http://loki-gateway.monitoring.svc.cluster.local:80
PostgreSQL: postgresql-pgpool.monitoring.svc.cluster.local:5432
Minio: minio.monitoring.svc.cluster.local:9000
```

### 🔐 新增 Secrets

執行 `./scripts/bootstrap-app-secrets.sh` 新增：
- `minio-root-credentials`
- `minio-mimir-user`
- `grafana-keycloak-oauth`

