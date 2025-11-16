# DetectViz Platform - 快速開始指南

## 🎉 部署完成狀態

✅ Kubernetes 集群已完全部署並運行
✅ ArgoCD 已安裝並配置完成
✅ Git Repository SSH 認證已自動配置
✅ Root Application 已同步 (Synced + Healthy)
✅ 基礎設施 ApplicationSets 已生成 6 個 Applications

---

## 🔐 ArgoCD 訪問

### 登入資訊

- **Username**: `admin`
- **Password**: `UVu0WapyjDXGxWzR`
- **URL**: https://localhost:8080 (需要 port forward)

### 訪問步驟

```bash
# 1. 設定 Port Forward
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443

# 2. 在瀏覽器中訪問
open https://localhost:8080

# 3. 使用上述登入資訊登入
```

---

## 📊 當前狀態說明

### Applications 狀態

```
NAME                              SYNC STATUS   HEALTH STATUS   說明
================================================================================
root                              Synced        Healthy         ✅ Root Application
cluster-bootstrap                 OutOfSync     Missing         ⏳ 等待基礎設施
infra-cert-manager                Unknown       Healthy         ⏳ 需要手動同步
infra-external-secrets-operator   Unknown       Healthy         ⏳ 需要手動同步
infra-ingress-nginx               Unknown       Unknown         ⏳ 需要手動同步
infra-metallb                     Unknown       Healthy         ⏳ 需要手動同步
infra-topolvm                     Unknown       Healthy         ⏳ 需要手動同步
infra-vault                       Unknown       Healthy         ⏳ 需要手動同步
```

### cluster-bootstrap 錯誤說明

**當前錯誤** (這是正常的!):
```
resource mapping not found for name: "argocd-server-tls"
no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

**為什麼這是正常的?**
- cluster-bootstrap 包含兩個階段:
  - ✅ Phase 1 (基礎資源): 已成功部署所有 Namespaces
  - ⏳ Phase 2 (進階資源): 等待基礎設施 CRDs 安裝

**Phase 2 需要的 CRDs**:
- `Certificate` (來自 cert-manager)
- `ClusterIssuer` (來自 cert-manager)
- `ArgoCDExtension` (來自 ArgoCD Rollouts)

**何時會成功?**
當基礎設施 Applications (cert-manager, ingress-nginx, argo-rollouts) 同步完成後,cluster-bootstrap 會自動重試並成功。

---

## 🚀 立即可執行的操作

### 選項 1: 在 ArgoCD UI 中手動同步 (推薦)

1. **訪問 ArgoCD UI** (https://localhost:8080)
2. **點擊每個 `infra-*` Application**
3. **點擊 "SYNC" 按鈕**
4. **等待同步完成**

**建議同步順序**:
1. infra-cert-manager (優先)
2. infra-ingress-nginx
3. infra-metallb
4. infra-external-secrets-operator
5. infra-vault
6. infra-topolvm

### 選項 2: 使用命令行同步

```bash
# 同步所有基礎設施 Applications
for app in infra-cert-manager infra-ingress-nginx infra-metallb \
           infra-external-secrets-operator infra-vault infra-topolvm; do
  kubectl --kubeconfig=/etc/kubernetes/admin.conf patch application $app -n argocd \
    -p='{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":true}}}' \
    --type=merge
  echo "Triggered sync for $app"
  sleep 5
done
```

### 選項 3: 使用 ArgoCD CLI

```bash
# 1. Port forward (在另一個終端)
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443 &

# 2. 登入
argocd login localhost:8080 \
  --username admin \
  --password dyiMhEmxz2dv52hK \
  --insecure

# 3. 同步所有基礎設施 Applications
argocd app sync infra-cert-manager
argocd app sync infra-ingress-nginx
argocd app sync infra-metallb
argocd app sync infra-external-secrets-operator
argocd app sync infra-vault
argocd app sync infra-topolvm

# 4. 檢查狀態
argocd app list
```

---

## 📋 驗證步驟

### 1. 檢查基礎設施 Pods

```bash
# cert-manager
kubectl get pods -n cert-manager

# Ingress NGINX
kubectl get pods -n ingress-nginx

# MetalLB
kubectl get pods -n metallb-system

# External Secrets
kubectl get pods -n external-secrets-system

# Vault
kubectl get pods -n vault

# TopoLVM
kubectl get pods -n topolvm-system
```

### 2. 檢查 CRDs

```bash
# cert-manager CRDs
kubectl get crd | grep cert-manager

# 應該看到:
# certificates.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
```

### 3. 檢查 cluster-bootstrap 狀態

```bash
# 當基礎設施部署完成後,cluster-bootstrap 應該自動重試並成功
kubectl get application cluster-bootstrap -n argocd

# 預期輸出:
# NAME                SYNC STATUS   HEALTH STATUS
# cluster-bootstrap   Synced        Healthy
```

---

## 🔍 故障排除

### 問題: 基礎設施 Application 同步失敗

**檢查**:
```bash
# 查看詳細錯誤
kubectl describe application infra-cert-manager -n argocd | tail -50

# 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50
```

**常見原因**:
1. Helm chart repository 無法訪問
2. 配置錯誤
3. 資源衝突

### 問題: cluster-bootstrap 一直失敗

**檢查**:
```bash
# 確認 CRDs 已安裝
kubectl get crd certificates.cert-manager.io
kubectl get crd clusterissuers.cert-manager.io

# 如果 CRDs 存在但仍失敗,手動觸發同步
kubectl patch application cluster-bootstrap -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

### 問題: 無法訪問 ArgoCD UI

**檢查**:
```bash
# 1. 確認 argocd-server pod 運行
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

# 2. 確認 port-forward 正常
lsof -i :8080

# 3. 測試連接
curl -k https://localhost:8080
```

---

## 📚 詳細文檔

### 部署相關
- **ansible/DEPLOYMENT_COMPLETE_FINAL.md** - 完整部署報告
- **ansible/ARGOCD_ACCESS_AND_STATUS.md** - ArgoCD 訪問和詳細狀態
- **deploy.md** - 完整部署手冊

### Bootstrap 相關
- **argocd/bootstrap/PHASE_DEPLOYMENT.md** - Bootstrap 分階段部署說明
- **argocd/bootstrap/README.md** - Bootstrap 資源概述

### 配置修正
- **ansible/GIT_REPOSITORY_AUTO_CONFIGURATION.md** - Git 認證自動化
- **ansible/CONFIGURATION_FIXES_COMPLETE.md** - 所有配置修正清單

---

## 🎯 預期的部署流程

### 當前階段 (已完成)

1. ✅ Terraform 部署 VM
2. ✅ Ansible 部署 Kubernetes 集群
3. ✅ ArgoCD 安裝和配置
4. ✅ Git Repository SSH 認證配置
5. ✅ Root Application 同步
6. ✅ ApplicationSets 生成基礎設施 Applications
7. ✅ Phase 1 資源部署 (Namespaces)

### 當前階段 (進行中)

8. ⏳ 基礎設施 Applications 同步 ← **您在這裡**
9. ⏳ Phase 2 資源部署 (Ingress, Certificates 等)
10. ⏳ Vault 初始化

### 後續階段

11. ⏳ 應用程式部署
12. ⏳ 監控和告警配置
13. ⏳ 最終驗證

---

## 💡 建議的下一步

### 立即執行 (5-10 分鐘)

1. **打開 ArgoCD UI**
2. **手動同步所有 `infra-*` Applications**
3. **監控同步進度**
4. **驗證 Pods 運行狀態**

### 等待完成後 (自動)

- cluster-bootstrap 會自動重試並成功
- Phase 2 資源會自動部署
- ArgoCD Ingress 會自動配置
- 可以開始部署應用程式

---

## ⚙️ 集群資訊

### 節點

```
NAME         ROLES                               IP ADDRESS
master-1     control-plane,workload-monitoring   192.168.0.11
master-2     control-plane,workload-mimir        192.168.0.12
master-3     control-plane,workload-loki         192.168.0.13
app-worker   workload-apps                       192.168.0.14
```

### 網路

- **Management Network**: 192.168.0.0/24
- **Storage Network**: 10.10.0.0/24
- **Control Plane VIP**: 192.168.0.10

### 版本

- **Kubernetes**: v1.32.0
- **ArgoCD**: v3.2.0
- **containerd**: 2.1.5

---

## 📞 支援

### 快速命令參考

```bash
# 檢查集群狀態
kubectl get nodes

# 檢查所有 Applications
kubectl get applications -n argocd

# 檢查所有 Pods
kubectl get pods -A

# 訪問 ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 強制刷新 Application
kubectl patch application <app-name> -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

### 常用路徑

- **ArgoCD UI**: https://localhost:8080
- **API Server**: https://192.168.0.10:6443
- **文檔目錄**: ansible/*.md, argocd/bootstrap/*.md

---

**文檔更新**: 2025-11-14
**集群狀態**: ✅ 健康,等待基礎設施同步
**下一步**: 在 ArgoCD UI 中手動同步基礎設施 Applications
