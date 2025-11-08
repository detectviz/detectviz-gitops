# Bootstrap

這個目錄包含了 DetectViz 平台的引導配置，在 ArgoCD 應用安裝之後、業務應用之前部署。

## 目錄結構

```
bootstrap/
├── argocd-projects.yaml         # ArgoCD AppProjects (單獨管理)
├── cluster-resources/           # 其他集群級別資源
│   ├── namespaces.yaml          # Namespace 資源
│   ├── cluster-issuer.yaml      # cert-manager ClusterIssuer
│   ├── rollouts-extension.yaml  # Argo Rollouts 擴展
│   └── kustomization.yaml
├── kustomization.yaml
└── README.md
```

## 部署順序

1. **ArgoCD Core** (`-10`): 安裝 ArgoCD 應用 + 創建集群資源
2. **Infrastructure** (`0`): 部署基礎設施應用
3. **Business Apps** (`2`): 部署業務應用

## 資源分類

### ArgoCD 專案 (argocd-projects.yaml)
- **platform-bootstrap**: 管理 ApplicationSets 和 AppProjects
- **detectviz**: 管理業務應用部署

### 集群級別資源 (cluster-resources/)

#### 命名空間 (namespaces.yaml)
- `monitoring`: 可觀測性應用
- `detectviz`: 業務應用
- `vault`: 密鑰管理
- `argocd`: ArgoCD 系統
- `external-secrets-system`: 外部密鑰管理

#### 證書管理 (cluster-issuer.yaml)
- `selfsigned-issuer`: 自簽名 ClusterIssuer
- `argocd-server-tls`: ArgoCD TLS 證書

#### 擴展 (rollouts-extension.yaml)
- `argo-rollouts`: Argo Rollouts 擴展

## 管理方式

這些集群資源由 `argocd-bootstrap` Application 通過多來源配置同時部署：

```yaml
sources:
  # 安裝 ArgoCD 應用
  - path: apps/argocd/overlays
  # 創建集群資源和專案
  - path: bootstrap/cluster-resources
```

這樣確保了所有必要的集群資源在 ArgoCD 完全運行前就緒。
