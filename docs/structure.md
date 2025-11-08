# 專案結構與組織架構

## 頂層目錄結構

```
detectviz-gitops/
├── terraform/          # 基礎設施即程式碼 (VM 建立)
├── ansible/            # 配置管理 (Kubernetes 部署)
├── bootstrap/          # 集群級別引導資源
├── apps/              # 基礎設施應用定義
├── appsets/           # ApplicationSet 配置
├── scripts/           # 自動化腳本與驗證工具
├── docs/              # 文件與指南
└── .kiro/             # Kiro AI 助手配置
```

## 核心目錄說明

### terraform/ - 基礎設施層
負責 Proxmox VM 的宣告式建立與管理
```
terraform/
├── main.tf                    # VM 資源定義
├── variables.tf               # 變數定義與驗證
├── outputs.tf                 # Ansible inventory 輸出
├── terraform.tfvars.example   # 配置範本
├── terraform.tfvars           # 實際配置 (gitignored)
└── docs/                      # Terraform 相關文件
```

### ansible/ - 配置管理層
負責 VM 配置與 Kubernetes 集群初始化
```
ansible/
├── deploy-cluster.yml         # 主要部署 playbook
├── install-ingress.yml        # Ingress 安裝 playbook
├── inventory.ini              # 主機清單
├── ansible.cfg                # Ansible 配置
├── group_vars/all.yml         # 全域變數
├── roles/                     # Ansible 角色
│   ├── common/               # 系統準備
│   ├── master/               # 控制平面初始化
│   └── worker/               # Worker 節點加入
└── kubeconfig/               # 自動產生的 kubeconfig
```

### bootstrap/ - 集群引導層
管理集群級別的基礎資源
```
bootstrap/
├── argocd-projects.yaml       # ArgoCD AppProject 定義
├── cluster-resources/         # 集群級別資源
│   ├── namespaces.yaml       # 命名空間定義
│   ├── cluster-issuer.yaml   # TLS 證書簽發器
│   ├── argocd-ingress.yaml   # ArgoCD 入口配置
│   └── rollouts-extension.yaml # Argo Rollouts 擴展
└── kustomization.yaml         # Kustomize 配置
```

### apps/ - 應用定義層
使用 Kustomize base/overlays 模式管理基礎設施應用
```
apps/
├── argocd/                    # ArgoCD 自身配置
│   ├── base/                 # 基礎配置
│   └── overlays/             # 環境特定配置
├── vault/                     # Vault 秘密管理
├── cert-manager/              # TLS 證書管理
├── external-secrets-operator/ # 秘密同步
├── metallb/                   # 負載均衡器
├── topolvm/                   # 本地儲存
└── kube-vip/                  # 控制平面 VIP
```

### appsets/ - ApplicationSet 層
管理 App-of-Apps 模式的應用集合
```
appsets/
├── argocd-bootstrap-app.yaml  # ArgoCD 自身引導
├── appset.yaml                # 基礎設施應用集合
├── observability-appset.yaml  # 可觀測性應用 (disabled)
├── data-appset.yaml           # 資料層應用 (disabled)
└── detectviz-appset.yaml      # DetectViz 業務應用 (disabled)
```

### scripts/ - 自動化工具層
提供部署、驗證與維護腳本
```
scripts/
├── validation-check.sh        # 多階段驗證腳本
├── health-check.sh           # 集群健康檢查
├── install-argocd.sh         # ArgoCD 安裝腳本
├── setup-vault-secrets.sh    # Vault 初始化腳本
├── setup-argocd-ssh.sh       # ArgoCD SSH 認證設定
├── test-cluster-dns.sh       # DNS 功能測試
├── test-pod-recovery.sh      # Pod 恢復測試
└── cluster-cleanup.sh        # 集群清理工具
```

## 配置模式與慣例

### Kustomize 結構模式
所有應用遵循標準的 base/overlays 結構：
```
apps/<app-name>/
├── base/
│   ├── kustomization.yaml    # 基礎資源定義
│   └── *.yaml               # 基礎 Kubernetes 資源
└── overlays/
    ├── kustomization.yaml    # 環境特定配置
    ├── values.yaml          # Helm values (如適用)
    └── *-patch.yaml         # 配置補丁
```

### 標籤與註解慣例
所有資源使用統一的標籤體系：
```yaml
labels:
  app.kubernetes.io/name: <app-name>
  app.kubernetes.io/part-of: detectviz-gitops
  app.kubernetes.io/managed-by: kustomize
  app.kubernetes.io/component: <component-type>
  environment: production
  cluster: detectviz-production

annotations:
  argocd.argoproj.io/sync-wave: "<wave-number>"
```

### 同步波次 (Sync Waves) 順序
ArgoCD 應用按以下順序部署：
- `-9`: 集群級別資源 (bootstrap/)
- `-2`: ArgoCD 自身配置
- `0`: ApplicationSet 定義
- `1`: 網路與儲存基礎設施
- `2`: 安全與秘密管理
- `3`: 應用支援服務

### 命名慣例
- **檔案名稱**: 使用 kebab-case (例: `argocd-bootstrap-app.yaml`)
- **資源名稱**: 使用 kebab-case (例: `external-secrets-operator`)
- **命名空間**: 使用應用名稱或功能分組
- **ConfigMap/Secret**: 使用 `<app>-config` 或 `<app>-secret` 格式

### 目錄權責劃分
- **terraform/**: 只管理 VM 生命週期，不涉及 Kubernetes 配置
- **ansible/**: 只負責 OS 配置與 Kubernetes 集群初始化
- **bootstrap/**: 只包含集群級別資源，不包含應用
- **apps/**: 只包含基礎設施應用，不包含業務應用
- **appsets/**: 只定義 ApplicationSet，不包含具體應用配置

### 配置檔案管理
- **敏感資訊**: 使用 `.example` 範本，實際檔案加入 `.gitignore`
- **環境變數**: 統一在 `group_vars/all.yml` 或 `terraform.tfvars` 管理
- **版本固定**: 所有外部依賴明確指定版本號
- **文件同步**: README 與實際配置保持一致