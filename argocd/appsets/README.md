# ApplicationSets

這個目錄包含了 DetectViz 平台的 ArgoCD ApplicationSets，用於自動發現和部署應用程式。

## ApplicationSets 總覽

| 文件 | 用途 | 目標 Repo | 命名空間 | 同步波 |
|-----|------|-----------|----------|--------|
| `argocd-bootstrap-app.yaml` | ArgoCD 引導應用 | detectviz-gitops | argocd | -10 |
| `appset.yaml` | 基礎設施應用 | detectviz-gitops | 各應用命名空間 | 0 |
| `observability-appset.yaml` | 可觀測性應用 | detectviz-apps | observability | 2 |
| `data-appset.yaml` | 數據應用 | detectviz-apps | data | 2 |
| `detectviz-appset.yaml` | DetectViz 應用 | detectviz-apps | detectviz | 2 |

## 詳細說明

### argocd-bootstrap-app.yaml
- **用途**: 安裝和配置 ArgoCD 本身
- **特殊性**: 這是整個 GitOps 系統的入口點，需要在其他所有應用之前部署
- **包含**: ArgoCD HA 安裝 + 配置補丁

### appset.yaml
- **用途**: 管理 detectviz-gitops repo 中的所有基礎設施應用
- **範圍**: 除了 ArgoCD 外的所有基礎設施應用
- **自動發現**: `apps/*/overlays` (排除 `apps/argocd/overlays`)

### observability-appset.yaml / data-appset.yaml / detectviz-appset.yaml
- **用途**: 管理 detectviz-apps repo 中的業務應用
- **目標**: 分別部署到不同的命名空間以實現邏輯隔離
- **自動發現**: 各自目錄下的 `*/overlays`

## 部署順序

1. **ArgoCD Bootstrap** (sync-wave: -10): 安裝 ArgoCD
2. **Infrastructure Apps** (sync-wave: 0): 部署基礎設施應用
3. **Business Apps** (sync-wave: 2): 部署業務應用

## 新增應用

### 基礎設施應用 (detectviz-gitops)
```bash
# 1. 在 apps/ 下創建應用目錄
mkdir apps/new-infra-app/{base,overlays}

# 2. appset.yaml 會自動發現並部署
```

### 業務應用 (detectviz-apps)
```bash
# 1. 在 detectviz-apps repo 的適當目錄下創建應用
# 例如: observability/new-app/{base,overlays}

# 2. 對應的 ApplicationSet 會自動發現並部署
# observability-appset.yaml -> observability 命名空間
# data-appset.yaml -> data 命名空間
# detectviz-appset.yaml -> detectviz 命名空間
```

## 故障排除

- **應用沒有自動部署**: 檢查應用目錄結構是否包含 `overlays/` 子目錄
- **命名空間問題**: 確保 ApplicationSet 的 namespace 模板正確
- **權限問題**: 檢查 ArgoCD AppProjects 的資源允許清單
