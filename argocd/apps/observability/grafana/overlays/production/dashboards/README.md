# Grafana Dashboards

這個目錄包含 Grafana dashboard JSON 定義，通過 GitOps 方式管理。

## 目錄結構

```
dashboards/
├── README.md                           # 本文件
├── kubernetes-cluster-overview.json    # Kubernetes 集群概覽 dashboard
└── (未來添加更多 dashboards...)
```

## 當前 Dashboards

### 1. Kubernetes Cluster Overview
- **文件**: `kubernetes-cluster-overview.json`
- **UID**: `kubernetes-cluster-overview`
- **文件夾**: Infrastructure
- **描述**: Kubernetes 集群整體健康狀態和資源使用情況
- **面板**:
  - Total Nodes (節點總數)
  - Unhealthy Nodes (異常節點數)
  - Total Pods (Pod 總數)
  - Unhealthy Pods (異常 Pod 數)
  - CPU Usage by Node (節點 CPU 使用率)
  - Memory Usage by Node (節點記憶體使用率)
- **數據源**: Mimir (Prometheus)
- **刷新間隔**: 默認 (可配置)

## 添加新 Dashboard

### 方法 1: 從 Grafana UI 導出

1. **在 Grafana UI 創建 Dashboard**:
   - 訪問 Grafana → Dashboards → New Dashboard
   - 設計你的 dashboard
   - 設置 UID (確保唯一性)

2. **導出 JSON**:
   - 點擊 Dashboard Settings (齒輪圖標)
   - 選擇 "JSON Model"
   - 複製完整 JSON
   - 確保移除 `id` 字段 (設為 `null`)

3. **保存到 Git**:
   ```bash
   # 創建新文件
   cat > /path/to/dashboards/my-dashboard.json <<'EOF'
   {
     "annotations": { ... },
     "editable": true,
     "id": null,  // 重要: 設為 null
     "uid": "my-dashboard",  // 唯一 ID
     "title": "My Dashboard",
     ...
   }
   EOF
   ```

4. **更新 ConfigMap**:
   - 編輯 `../dashboard-configmap.yaml`
   - 添加新的 JSON 到 `data` 字段:
   ```yaml
   data:
     kubernetes-cluster-overview.json: |-
       { ... }
     my-dashboard.json: |-
       { ... }
   ```

5. **提交並同步**:
   ```bash
   git add argocd/apps/observability/grafana/overlays/
   git commit -m "Add new Grafana dashboard: My Dashboard"
   git push
   argocd app sync grafana
   ```

### 方法 2: 從 Grafana 官方 Dashboard 庫導入

1. **訪問** [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

2. **選擇 Dashboard**:
   - 例如: [Node Exporter Full](https://grafana.com/grafana/dashboards/1860)

3. **下載 JSON**:
   - 點擊 "Download JSON"

4. **修改 JSON**:
   ```bash
   # 修改 datasource 引用
   sed -i 's/"datasource": "Prometheus"/"datasource": {"type": "prometheus", "uid": "Mimir"}/g' dashboard.json

   # 移除 id (設為 null)
   jq '.id = null' dashboard.json > dashboard-fixed.json
   ```

5. **添加到 ConfigMap** (同上)

### 方法 3: 使用 Jsonnet (進階)

如果需要動態生成 dashboards，可使用 [Grafonnet](https://github.com/grafana/grafonnet):

```jsonnet
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local singlestat = grafana.singlestat;
local graphPanel = grafana.graphPanel;

dashboard.new(
  'My Dashboard',
  schemaVersion=16,
  tags=['kubernetes'],
)
.addPanel(
  singlestat.new(
    'Total Nodes',
    datasource='Mimir',
    sparklineShow=true,
  )
  .addTarget(
    prometheus.target(
      'count(kube_node_info)',
    )
  ), gridPos={x: 0, y: 0, w: 6, h: 4}
)
```

## Dashboard 文件夾組織

Dashboard 通過 `dashboard-provider.yaml` 自動分類到文件夾:

- **Platform**: 平台級 dashboards (系統整體視圖)
- **Infrastructure**: 基礎設施 dashboards (節點、存儲、網路)
- **Applications**: 應用級 dashboards (應用性能監控)

在 dashboard JSON 中設置文件夾:
```json
{
  "tags": ["kubernetes", "infrastructure"],
  ...
}
```

## 最佳實踐

1. **設置唯一 UID**:
   - 使用描述性 UID: `kubernetes-cluster-overview`
   - 避免衝突: 檢查現有 dashboards

2. **使用正確的數據源**:
   - Prometheus 指標 → `Mimir`
   - 日誌 → `Loki`
   - Traces → `Tempo`

3. **添加標籤**:
   ```json
   "tags": ["kubernetes", "monitoring", "infrastructure"]
   ```

4. **設置合理的刷新間隔**:
   ```json
   "refresh": "30s",
   "time": {
     "from": "now-1h",
     "to": "now"
   }
   ```

5. **使用變量 (Variables)**:
   ```json
   "templating": {
     "list": [
       {
         "name": "namespace",
         "type": "query",
         "datasource": "Mimir",
         "query": "label_values(kube_pod_info, namespace)"
       }
     ]
   }
   ```

6. **移除敏感資訊**:
   - 移除 `id` 字段
   - 移除用戶特定設置
   - 使用通用 datasource UIDs

## 驗證 Dashboard

### 本地驗證 JSON

```bash
# 驗證 JSON 格式
jq '.' kubernetes-cluster-overview.json

# 檢查必要字段
jq '.uid, .title, .tags' kubernetes-cluster-overview.json
```

### 部署後驗證

```bash
# 檢查 ConfigMap 是否創建
kubectl get configmap grafana-dashboards-infrastructure -n grafana

# 檢查 dashboard 是否載入
kubectl logs -n grafana deployment/grafana | grep "Provisioning dashboard"

# 在 Grafana UI 驗證
# 訪問: https://grafana.detectviz.internal/dashboards
```

## 故障排除

### Dashboard 未出現

1. **檢查 ConfigMap**:
   ```bash
   kubectl describe configmap grafana-dashboards-infrastructure -n grafana
   ```

2. **檢查 Grafana 日誌**:
   ```bash
   kubectl logs -n grafana deployment/grafana | grep -i dashboard
   ```

3. **重啟 Grafana**:
   ```bash
   kubectl rollout restart deployment/grafana -n grafana
   ```

### Dashboard 顯示錯誤

1. **檢查數據源**:
   - 確保 `Mimir`, `Loki` 數據源已配置
   - 驗證數據源 UID 正確

2. **檢查 Prometheus 查詢**:
   - 在 Grafana Explore 測試查詢
   - 檢查 metric 名稱和 labels

3. **檢查權限**:
   - 確保 Grafana 有權限訪問數據源
   - 檢查 NetworkPolicy (如果啟用)

## 參考資源

- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/best-practices-for-creating-dashboards/)
- [Grafana JSON Model](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/)
- [Grafonnet Library](https://github.com/grafana/grafonnet)
- [Community Dashboards](https://grafana.com/grafana/dashboards/)
- [PromQL Basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
