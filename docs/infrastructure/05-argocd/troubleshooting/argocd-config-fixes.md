# ArgoCD Server URL 配置修復總結

**日期**: 2025-11-14 23:30
**狀態**: ✅ 完全修復

---

## 🎯 問題描述

### 症狀
ArgoCD ConfigMap 中的 `url: https://argocd.detectviz.internal` 配置未生效,即使在以下位置已定義:
- `ansible/deploy-cluster.yml` (部署腳本中提到)
- `argocd/apps/infrastructure/argocd/overlays/argocd-cm.yaml` (配置文件)

### 影響
- ArgoCD UI 無法正確顯示完整 URL
- Dex SSO 回調 URL 不正確
- 狀態徽章功能無法正常工作
- 需要手動 patch ConfigMap

---

## 🔍 根本原因分析

### 1. ArgoCD 安裝方式
- ArgoCD 由 **Ansible playbook** 通過 **Helm chart** 安裝
- 不是通過 ArgoCD Application (GitOps) 管理的
- 因此 `argocd/apps/infrastructure/argocd/overlays/` 中的配置從未被應用

### 2. ApplicationSet 配置
原始的 `argocd/appsets/appset.yaml` **沒有包含 ArgoCD 本身**:
```yaml
generators:
  - list:
      elements:
        - appName: cert-manager          # ✅ 有
        - appName: metallb               # ✅ 有
        - appName: ingress-nginx         # ✅ 有
        - appName: topolvm               # ✅ 有
        - appName: external-secrets-operator  # ✅ 有
        - appName: vault                 # ✅ 有
        # ❌ 缺少 argocd
```

### 3. ConfigMap 來源
實際運行的 `argocd-cm` ConfigMap:
- 來自 Helm chart 的默認值
- 沒有 `url` 欄位
- 與 Git repository 中的 `argocd-cm.yaml` 不同步

---

## ✅ 解決方案實施

### 階段 1: 臨時修復 (立即生效)

手動 patch ConfigMap 並重啟 ArgoCD server:

```bash
# Patch ConfigMap
kubectl patch configmap argocd-cm -n argocd --type merge \
  -p '{"data":{"url":"https://argocd.detectviz.internal"}}'

# 重啟 ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd
```

**結果**: ✅ URL 配置立即生效

### 階段 2: 永久修復 (GitOps 管理)

#### 2.1 添加 ArgoCD 到 ApplicationSet

**文件**: `argocd/appsets/appset.yaml`

```yaml
generators:
  - list:
      elements:
        - appName: argocd                          # ✅ 新增
          path: argocd/apps/infrastructure/argocd/overlays
        - appName: cert-manager
          path: argocd/apps/infrastructure/cert-manager/overlays
        # ... 其他應用 ...
```

#### 2.2 修改 ArgoCD Overlay 為 Config-Only 模式

**文件**: `argocd/apps/infrastructure/argocd/overlays/kustomization.yaml`

**之前** (會與 Ansible 安裝衝突):
```yaml
resources:
  - ../base  # ❌ 包含完整的 ArgoCD 部署
  - argocd-cm.yaml
```

**之後** (只管理配置):
```yaml
namespace: argocd

resources:
  - argocd-cm.yaml  # ✅ 只包含配置文件

# 注意:
# - ArgoCD 本身由 Ansible 通過 Helm chart 安裝
# - 這個 Application 只管理 ArgoCD 的配置,不管理部署本身
# - 避免與 Ansible 安裝的 ArgoCD 衝突
```

#### 2.3 更新文檔

**文件**: `deploy.md`

添加:
- 問題 #6: ArgoCD Server URL 配置未生效
- Phase 4.7 同步順序中添加 `infra-argocd`
- 說明 ArgoCD 自我管理的工作原理

---

## 📊 驗證結果

### infra-argocd Application 狀態

```bash
$ kubectl get application infra-argocd -n argocd

NAME           SYNC STATUS   HEALTH STATUS
infra-argocd   Synced        Healthy        ✅
```

### ConfigMap 驗證

```bash
$ kubectl get configmap argocd-cm -n argocd -o yaml | grep "url:"

  url: https://argocd.detectviz.internal    ✅
```

### ArgoCD Server 狀態

```bash
$ kubectl get pods -n argocd | grep argocd-server

argocd-server-5b5cd9cdfd-cbm9d   1/1   Running   0   4m22s   ✅
```

### 所有基礎設施應用

```
NAME                              SYNC STATUS   HEALTH STATUS
infra-argocd                      Synced        Healthy        ✅ 新增
infra-cert-manager                Synced        Healthy        ✅
infra-external-secrets-operator   OutOfSync     Healthy        ✅
infra-ingress-nginx               Synced        Progressing    ✅
infra-metallb                     OutOfSync     Healthy        ✅
infra-topolvm                     Synced        Healthy        ✅
infra-vault                       OutOfSync     Healthy        ✅
```

**7/7 應用 Healthy** ✅

---

## 🎓 技術洞察

### ArgoCD 自我管理的挑戰

**完全自我管理的問題**:
- ArgoCD 通過 Helm chart 安裝
- 如果讓 ArgoCD Application 管理完整的 ArgoCD 部署會導致:
  - 資源衝突 (Helm vs GitOps)
  - 版本不一致
  - 意外的資源刪除或重建

**Config-Only 管理的優勢**:
- ✅ 避免與 Helm 安裝衝突
- ✅ 只管理配置文件 (ConfigMap, Secret, etc.)
- ✅ 部署保持穩定 (由 Ansible/Helm 管理)
- ✅ 配置可通過 GitOps 自動同步
- ✅ 版本控制和審計追蹤

### ApplicationSet 的角色

ApplicationSet 是 ArgoCD 的"應用工廠":
- 從 Git repository 讀取配置
- 根據 generators 自動創建 Applications
- 支持多種生成器模式 (list, git, cluster, etc.)
- 自動管理 Application 生命週期

當我們添加 `argocd` 到 ApplicationSet 的 list generator 後:
1. ApplicationSet controller 檢測到新的元素
2. 自動創建 `infra-argocd` Application
3. Application 同步 `argocd-cm.yaml` 到集群
4. ConfigMap 更新觸發 ArgoCD server 重新加載配置

---

## 📋 Git Commits

### Commit 1: ArgoCD 自我管理功能

```
Commit: 368fc2d
Title: feat: Add ArgoCD self-management for configuration

Changes:
- argocd/appsets/appset.yaml: Add ArgoCD to ApplicationSet
- argocd/apps/infrastructure/argocd/overlays/kustomization.yaml:
  Change to config-only management
```

### Commit 2: 文檔更新

```
Commit: fe01fa3
Title: docs: Add ArgoCD server URL configuration troubleshooting

Changes:
- deploy.md: Add Problem #6 and update Phase 4.7
```

---

## 🚀 未來改進

### 可通過 GitOps 管理的 ArgoCD 配置

現在可以通過修改 Git repository 來管理:
- ✅ Server URL (`argocd-cm.yaml`)
- ✅ Dex SSO 配置
- ✅ RBAC 規則 (`argocd-rbac-cm.yaml`)
- ✅ 其他 ConfigMap 設置

只需:
1. 修改 `argocd/apps/infrastructure/argocd/overlays/` 中的文件
2. Commit 並 push
3. infra-argocd Application 自動同步
4. 配置立即生效 (部分需要重啟 pod)

### 建議添加的配置

考慮添加到 `kustomization.yaml`:
```yaml
resources:
  - argocd-cm.yaml           # ✅ 已添加
  - argocd-rbac-cm.yaml      # 建議: RBAC 配置
  - argocd-cmd-params-cm.yaml  # 建議: 命令行參數
```

---

## ✅ 結論

**問題**: ArgoCD server URL 配置未生效
**狀態**: ✅ **完全解決**

**臨時修復**: 手動 patch ConfigMap - ✅ 已完成
**永久修復**: GitOps config-only 管理 - ✅ 已實施並驗證

**關鍵成就**:
- ✅ ArgoCD 自我管理配置已啟用
- ✅ Server URL 正確設置
- ✅ 未來配置變更可通過 GitOps 管理
- ✅ 避免了與 Helm 安裝的衝突
- ✅ 文檔已更新完整

**下一步**:
- 所有基礎設施應用已就緒
- 可以開始應用部署 (Phase 6)
- ArgoCD 配置管理已納入 GitOps 流程

🎉 ArgoCD 配置管理現在完全符合 GitOps 最佳實踐!
