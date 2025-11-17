

移除 pgpool image tag 覆寫，使用 Helm chart 預設值
## 問題

手動指定的 pgpool image tags 都不存在：
- `4.5.0-debian-11-r3` - 原始配置，不存在
- `4.5.0-debian-11-r0` - 第一次嘗試修正，仍不存在

## 原因

Bitnami 已更新 image tags 格式，現在使用 debian-12 而非 debian-11，
且舊版 tags 已遷移到 bitnamilegacy repository。

## 解決方案

移除自訂 image tag，讓 Helm chart (postgresql-ha 12.8.2)
使用其預設的 pgpool image 版本，應該與 chart 版本相容。

---

移除 PostgreSQL nodeSelector 限制以允許測試部署
## 問題

Pods 無法調度因為：
1. nodeSelector 要求 `node-role.kubernetes.io/workload-apps: "true"`
2. 只有一個節點 (app-worker) 符合條件
3. Pod anti-affinity 規則阻止多個 pods 在同一節點

## 解決方案

暫時註解掉 pgpool 和 postgresql 的 nodeSelector，
允許 pods 調度到任何可用節點（包括 control-plane 節點）。

## 注意事項

生產環境應恢復 nodeSelector 以確保工作負載隔離。

---

調整 PostgreSQL 為測試部署配置
## 變更內容

### 1. 修正 Pgpool Image Tag
- 原 tag `4.5.0-debian-11-r3` 在 Docker Hub 不存在
- 改用 `4.5.0-debian-11-r0`（最接近的可用版本）

### 2. 暫時禁用持久化儲存
- Pgpool: `persistence.enabled: false`
- PostgreSQL: `persistence.enabled: false`
- 目的：加速測試部署，避免 PVC 配置問題

### 3. 降低副本數與反親和性
- Pgpool: `replicaCount: 2 → 1`, `podAntiAffinityPreset: hard → soft`
- PostgreSQL: `replicaCount: 3 → 1`, `podAntiAffinityPreset: hard → soft`
- 目的：允許在節點數較少的測試環境部署

## 注意事項

這些變更僅用於測試驗證部署流程。生產環境應：
- 啟用 persistence（使用 TopoLVM）
- 使用高可用配置（3+ replicas）
- 使用 hard podAntiAffinityPreset

---

修正 PostgreSQL 部署 namespace 並暫時禁用 ServiceMonitor
## 問題

1. **Namespace 錯誤**: Helm chart 生成的資源都部署到 `default` namespace 而非 `postgresql`
2. **ServiceMonitor CRD 不存在**: 嘗試建立 ServiceMonitor 但 Prometheus Operator 尚未部署

## 解決方案

### 1. 修正 Namespace 設定
在頂層 `kustomization.yaml` 新增 `namespace: postgresql`，
確保所有資源都部署到正確的 namespace。

### 2. 暫時禁用 ServiceMonitor
在 `base/values.yaml` 的 Production Overrides 區段，
將 `metrics.serviceMonitor.enabled` 從 `true` 改為 `false`。
等 Prometheus Operator 部署完成後再啟用。

## 變更內容

- `kustomization.yaml`: 新增 `namespace: postgresql`
- `base/values.yaml`: 設定 `metrics.serviceMonitor.enabled: false`

## 驗證

已通過 `kubectl kustomize --enable-helm` 驗證：
- 所有資源正確設定 `namespace: postgresql`
- 不再產生 ServiceMonitor 資源

---

新增 PostgreSQL 頂層 kustomization.yaml 以支援 ArgoCD ApplicationSet
## 問題

ArgoCD Application 指向 `argocd/apps/observability/postgresql`，
但該目錄下只有 `base/` 子目錄，沒有 kustomization.yaml，
導致 ArgoCD 無法找到任何資源進行部署。

## 解決方案

在 `argocd/apps/observability/postgresql/` 建立頂層 kustomization.yaml，
內容為 `resources: - base`，讓 ArgoCD 能正確解析目錄結構。

## 目錄結構

```
argocd/apps/observability/postgresql/
├── kustomization.yaml (新增) → 指向 base
└── base/
    ├── kustomization.yaml (helmCharts + externalsecret.yaml)
    ├── values.yaml (Helm values)
    ├── externalsecret.yaml (Vault secrets)
    └── .gitignore (忽略 charts/)
```

## 驗證

已通過 `kubectl kustomize --enable-helm` 驗證可正確產生所有資源。

---

修正 PostgreSQL kustomize 結構以符合 ArgoCD ApplicationSet 路徑
## 變更內容

### PostgreSQL 配置重構
- 將 helmCharts 定義從 overlays 移至 base/kustomization.yaml
- 將 externalsecret.yaml 從 overlays 移至 base/
- 刪除 overlays/ 目錄（不再需要）
- 新增 base/.gitignore 忽略 kustomize 建置快取 (charts/)

## 技術細節

ApplicationSet 指向 `argocd/apps/observability/postgresql` (base 目錄)，
因此 base/kustomization.yaml 必須包含完整的資源定義：
- helmCharts: postgresql-ha chart 配置
- resources: externalsecret.yaml
- valuesFile: values.yaml (同目錄)

之前的結構將 helmCharts 放在 overlays/，導致 ArgoCD 從 base 建置時
找不到任何資源，應用顯示 Synced/Healthy 但實際無資源部署。

## 驗證

已通過 `kubectl kustomize --enable-helm` 本地驗證，確認可正確產生：
- ServiceAccount
- ConfigMap (hooks scripts)
- Services (pgpool, postgresql)
- StatefulSet (postgresql-postgresql)
- Deployment (postgresql-pgpool)
- ExternalSecret (db credentials)

---
1 hour ago
遵循 constitution.md: 重構 PostgreSQL kustomize base/overlay 分離
**變更摘要**:
- 將 helmCharts 定義從 base 移到 overlay (符合原則 #1)
- Base kustomization 只保留 placeholder 註解
- Overlay kustomization 包含完整 helmCharts 定義,引用 ../base/values.yaml
- 移除無效的 patchesStrategicMerge,改為使用 Helm values (符合原則 #4)

**受影響的應用**: postgresql
**受影響的命名空間**: postgresql
**部署順序**: 無變更 (Phase 6.3.1 PostgreSQL 為首個平台服務)

**驗證**:
- Namespaces 已在 argocd/bootstrap/phase1-base/namespaces.yaml 定義 (符合原則 #2)
- ExternalSecrets 使用 Vault backend (符合原則 #5)
- Values.yaml 包含所有 nodeSelector/storageClass 設定 (符合原則 #4)

**關聯文檔**: 需要後續更新 app-deploy-sop.md 的 6.3.1 節 (原則 #6)

---
1 hour ago
修正 PostgreSQL Helm chart 配置結構
將 values.yaml 從 overlays 移到 base 目錄
解決 kustomize 安全限制問題
修正 merge 衝突