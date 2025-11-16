# 整體部署流程完整性檢查

- [Phase 6: 應用部署](#phase-6-應用部署)
- [Phase 7: 最終驗證](#phase-7-最終驗證)

# 架構圖

```
Phase 1–5: Infra Bootstrap
Phase 6: Observability
 ├─ Prometheus
 ├─ Mimir
 ├─ Loki
 ├─ Tempo
 ├─ PostgreSQL
 ├─ Grafana
 └─ Alloy Agent (every K8s Node)   ← 新增

Phase 7: Final Verification

Phase 8: Platform Governance
 ├─ RBAC
 ├─ Webhook
 ├─ SSO
 ├─ Vault ESO Policies
 └─ Infra Exporters
```


# Alloy 可以完全取代 node-exporter，修改 Phase 6.1

* 直接產生 Alloy DaemonSet YAML（符合你 monitoring namespace）

* 整合 Prometheus remoteWrite → Mimir
* 整合 Loki → Gateway
* 整合 Tempo → OTLP
* 更新 ApplicationSet 結構
* 把 Node Exporter、Promtail 相關設定全部抽掉

Grafana 官方文件明確：  
Alloy 內建 host_metrics：

```hcl
local.host_metrics "system" {
  scrape_interval = "15s"
}
```

產出的 metrics = **100% Prometheus Node Exporter 等效內容**

1. Metric（主機指標）

Alloy 內建：

```hcl
local.host_metrics "system" {
  scrape_interval = "15s"
}
```


2. Alloy 提供 log pipelines：

```hcl
loki.source.file "varlogs" {
  paths = ["/var/log/*.log"]
}

loki.process "label" {
  forward_to = [loki.write.loki.receiver]
  stage {
json {}
  }
}

loki.write "loki" {
  endpoint {
url = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
  }
}
```

3. Alloy 支援三種 trace pipeline：

  1. OTel Trace ingestion
  2. Tempo native ingestion
  3. OTel transform + batch + export


  範例：

  ```hcl
  otelcol.receiver.otlp "otlp" {
    http {}
    grpc {}
  }

  otelcol.exporter.otlp "tempo" {
    endpoint = "tempo.monitoring.svc:4317"
  }

  otelcol.pipeline.traces "default" {
    receivers = [otelcol.receiver.otlp.otlp]
    exporters = [otelcol.exporter.otlp.tempo]
  }
  ```
# 6.0 Vault + ESO

- [ ] ESO SecretStore 與 ClusterSecretStore 分類：
  - [ ] keycloak namespace 對應 keycloak store
  - [ ] grafana namespace 對應 grafana store
  - [ ] monitoring namespace 對應 monitoring store


# 6. Observability Stack（Prom/Loki/Tempo/Mimir）

- [ ] Prometheus remoteWrite
- [ ] Loki chunkstore 正確設定
- [ ] Tempo hint 配置完成
- [ ] Grafana datasources 已生成
- [ ] StorageClass 依 namespace 正確分流
- [ ] Namespace 需統一：

```
monitoring: prometheus/mimir/loki/tempo
postgresql: postgresql
keycloak: keycloak
grafana: grafana
```

- [ ] Grafana datasource URL 正確性
全部指向 `monitoring.svc.cluster.local`  
必須更新為真實 namespace

- [ ] PostgreSQL（Pgpool + primary/replica）
- [ ] Keycloak realm export/import（GitOps-friendly）
- [ ] Grafana OAuth client configuration
- [ ] Grafana Dashboard Provisioning／Folder As Code
- [ ] Minio（若要給 Mimir blocks storage）
- [ ] Mimir S3 backend config

### Phase 8: Platform Governance（平台治理）
- [ ] Argo CD Webhook（GitHub → ArgoCD）設定
- [ ] Argo CD Webhook Secret → Vault / ESO 管理
- [ ] Argo CD RBAC Policy（Admin / Editor / Viewer）
- [ ] Argo CD Single Sign-On（Keycloak, Dex）
- [ ] Team-based AppProject + Roles
- [ ] GitOps Security Hardening（SSH, Token Rotation）
- [ ] NetworkPolicy
- [ ] DNS records 需正式定稿
- [ ] Observability dashboards as code
- [ ] overlays/base 結構
- [ ] 具體應用 manifest 完整化


- [ ] 在 GitHub Repo 設定 https://argocd.detectviz.internal/api/webhook
- [ ] 測試 push → ArgoCD 是否自動同步



### 建議做法

1. **在 Vault 建立 Secret**

```
vault kv put argocd/webhook token=<github_webhook_secret>
```

2. **在 argocd namespace 使用 ESO 生成 Secret**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: argocd-webhook-secret
  namespace: argocd
spec:
  refreshInterval: 1h
  secretStoreRef:
name: detectviz-vault
kind: SecretStore
  target:
name: argocd-webhook
creationPolicy: Owner
  data:
- secretKey: token
  remoteRef:
    key: argocd/webhook
    property: token
```

- [ ] Argo CD values.yaml 中引用此 Secret


### Argo CD RBAC Policy（Admin / Editor / Viewer）

你應修改：

```
argocd/apps/infrastructure/argocd/overlays/argocd-cm.yaml
argocd/apps/infrastructure/argocd/overlays/argocd-rbac-cm.yaml
```

示例：

```yaml
# argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
g, admin@example.com, role:admin
g, dev@example.com,   role:editor
g, viewer@example.com, role:viewer

  scopes: "[email]"
```

### RBAC 角色

- [ ] **Admin**：修改 App、Repo、Project
- [ ] **Editor**：只能同步 App、不能動專案
- [ ] **Viewer**：只讀


你也可以添加 Team-Based AppProject：

```
argocd/projects/team-a.yaml
argocd/projects/team-b.yaml
```


### 新增：Infrastructure Exporters
- prometheus-pve-exporter (Proxmox Host)
- prometheus-ipmi-exporter (K8s Deployment)

```
- [ ] PVE Exporter：直接跑在 Proxmox host（systemd service）

- [ ] IPMI Exporter：以 Deployment 方式放在 K8s（monitoring namespace）

Prometheus Scrape Config 可統一在 Prometheus Helm Values 中 patch path `/monitoring/prometheus/overlays/scrape-config.yaml`。

