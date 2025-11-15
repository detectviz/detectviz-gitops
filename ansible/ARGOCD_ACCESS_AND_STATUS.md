# ArgoCD 訪問資訊與當前狀態

## 🔐 ArgoCD 訪問資訊

### Admin 登入憑證

**Username**: `admin`
**Password**: `UVu0WapyjDXGxWzR`

### 訪問方法

#### 方法 1: Port Forward (推薦)

```bash
# 1. 設定 port forward
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443

# 2. 在瀏覽器中訪問
open https://localhost:8080

# 3. 登入
# Username: admin
# Password: UVu0WapyjDXGxWzR
```

#### 方法 2: 使用 SSH Tunnel

```bash
# 從本地機器建立 SSH tunnel
ssh -L 8080:localhost:8080 ubuntu@192.168.0.11 \
  "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf port-forward svc/argocd-server -n argocd 8080:443"

# 訪問 https://localhost:8080
```

#### 方法 3: 使用 ArgoCD CLI

```bash
# 1. 安裝 ArgoCD CLI (如果還沒有)
brew install argocd  # macOS
# 或
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-darwin-amd64
sudo install -m 555 /tmp/argocd /usr/local/bin/argocd

# 2. Port forward (在另一個終端)
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  port-forward svc/argocd-server -n argocd 8080:443 &

# 3. 登入
argocd login localhost:8080 \
  --username admin \
  --password UVu0WapyjDXGxWzR \
  --insecure

# 4. 查看 applications
argocd app list
argocd app get root
argocd app get cluster-bootstrap
```

---

## 📊 當前 ArgoCD 狀態

### Applications 概覽

```
NAME                SYNC STATUS   HEALTH STATUS   詳情
root                Synced        Degraded        Root Application (App of Apps)
cluster-bootstrap   OutOfSync     Missing         Bootstrap 資源部署失敗
```

### 詳細狀態分析

#### 1. Root Application ✅ (Synced, Degraded)

**狀態**: 正常
**說明**:
- **Synced**: Git repository 同步成功
- **Degraded**: 子 Application (cluster-bootstrap) 失敗導致

**資源**:
- Source: `git@github.com:detectviz/detectviz-gitops.git/argocd/appsets`
- Revision: `59d9b06a2140c709353bc7db35a4c88028b134fb` (main)
- Destination: `argocd` namespace

**已建立的資源**:
- ApplicationSet: `argocd-bootstrap`
- ApplicationSet: `detectviz-gitops`

#### 2. Cluster-Bootstrap ❌ (OutOfSync, Missing)

**狀態**: 失敗
**錯誤訊息**: "one or more synchronization tasks are not valid (retried 5 times)"

**失敗原因**: 嘗試部署以下資源,但依賴的 CRDs 尚未安裝:

| 資源 | 類型 | 依賴 | 狀態 |
|------|------|------|------|
| argocd-server-tls | Certificate (cert-manager.io/v1) | cert-manager | ❌ CRD 不存在 |
| selfsigned-issuer | ClusterIssuer (cert-manager.io/v1) | cert-manager | ❌ CRD 不存在 |
| argo-rollouts | ArgoCDExtension (argoproj.io/v1alpha1) | ArgoCD Rollouts | ❌ CRD 不存在 |
| argocd-server | Ingress (networking.k8s.io/v1) | Ingress Controller | ❌ 控制器未安裝 |

**Source**:
- Path: `argocd/bootstrap`
- Revision: `59d9b06a2140c709353bc7db35a4c88028b134fb` (HEAD)

---

## 🔍 問題分析

### 根本原因: 依賴順序問題

這是一個典型的 **"雞生蛋" 問題**:

```
cluster-bootstrap
    ├─ Certificate (需要 cert-manager)
    ├─ ClusterIssuer (需要 cert-manager)
    ├─ ArgoCDExtension (需要 ArgoCD Rollouts)
    └─ Ingress (需要 Ingress Controller)

但是這些組件應該由基礎設施 ApplicationSets 部署:
    ├─ cert-manager (infrastructure ApplicationSet)
    ├─ ArgoCD Rollouts (infrastructure ApplicationSet)
    └─ Ingress Controller (infrastructure ApplicationSet)
```

**問題**:
- cluster-bootstrap 想要部署高級資源 (Certificate, Ingress)
- 但這些資源依賴的基礎設施 (cert-manager, Ingress Controller) 還沒安裝
- 基礎設施應該由其他 ApplicationSets 部署

### 當前目錄結構

```
argocd/
├── appsets/                    ← Root Application 管理這裡
│   ├── argocd-bootstrap.yaml  ← 產生 cluster-bootstrap Application
│   └── detectviz-gitops.yaml
└── bootstrap/                  ← cluster-bootstrap Application 的 source
    ├── argocd-projects.yaml
    ├── cluster-resources/
    │   ├── argocd-ingress.yaml      ← 需要 Ingress Controller
    │   ├── cluster-issuer.yaml      ← 需要 cert-manager
    │   ├── rollouts-extension.yaml  ← 需要 ArgoCD Rollouts
    │   └── namespaces.yaml          ← ✅ 這個可以部署
    └── kustomization.yaml
```

---

## 💡 解決方案

### 選項 1: 分階段部署 (推薦)

將 bootstrap 資源分為兩個階段:

**Phase 1: 基礎資源** (不依賴任何 CRDs)
- Namespaces
- RBAC (如果有)
- ConfigMaps/Secrets (如果有)

**Phase 2: 進階資源** (依賴基礎設施)
- Certificates (需要 cert-manager)
- ClusterIssuers (需要 cert-manager)
- Ingress (需要 Ingress Controller)
- ArgoCDExtensions (需要 ArgoCD Rollouts)

**實施步驟**:

```bash
# 1. 建立新的目錄結構
mkdir -p argocd/bootstrap/phase1-base
mkdir -p argocd/bootstrap/phase2-advanced

# 2. 移動 namespaces 到 phase1
mv argocd/bootstrap/cluster-resources/namespaces.yaml argocd/bootstrap/phase1-base/

# 3. 移動其他資源到 phase2
mv argocd/bootstrap/cluster-resources/*.yaml argocd/bootstrap/phase2-advanced/

# 4. 更新 kustomization.yaml
```

### 選項 2: 使用 Sync Waves 和 Skip Dry Run (簡單)

為依賴資源添加 annotations,讓 ArgoCD 跳過預檢查:

```yaml
# argocd/bootstrap/cluster-resources/argocd-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"  # 在基礎設施之後
    argocd.argoproj.io/sync-options: "SkipDryRunOnMissingResource=true"
```

### 選項 3: 移除依賴資源 (最簡單,臨時方案)

暫時註解掉或刪除依賴 CRDs 的資源:

```bash
# 編輯 argocd/bootstrap/cluster-resources/kustomization.yaml
vim argocd/bootstrap/cluster-resources/kustomization.yaml

# 註解掉:
# - argocd-ingress.yaml
# - cluster-issuer.yaml
# - rollouts-extension.yaml

# Commit 並 push
git add argocd/bootstrap/cluster-resources/kustomization.yaml
git commit -m "Temporarily disable resources requiring CRDs"
git push

# 強制刷新 cluster-bootstrap
kubectl patch application cluster-bootstrap -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

### 選項 4: 手動部署基礎設施先 (最快)

如果您有基礎設施的 Applications,可以先手動同步:

```bash
# 1. 檢查是否有 infrastructure ApplicationSets
kubectl get applicationset -n argocd

# 2. 檢查是否有 cert-manager, ingress-nginx 等 Applications
kubectl get applications -n argocd | grep -E "cert-manager|ingress|rollouts"

# 3. 如果有,手動同步
argocd app sync cert-manager
argocd app sync ingress-nginx
argocd app sync argo-rollouts

# 4. 等待基礎設施就緒後,重試 cluster-bootstrap
argocd app sync cluster-bootstrap --force
```

---

## 🚀 推薦執行步驟

### 立即可執行 (選項 3)

```bash
# 1. 暫時移除依賴 CRDs 的資源
cd /Users/zoe/Documents/github/detectviz-gitops

# 2. 編輯 kustomization.yaml
cat > argocd/bootstrap/cluster-resources/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespaces.yaml
  # 暫時註解掉需要 CRDs 的資源
  # - argocd-ingress.yaml
  # - cluster-issuer.yaml
  # - rollouts-extension.yaml

labels:
  - pairs:
      app.kubernetes.io/managed-by: kustomize
EOF

# 3. Commit 並 push
git add argocd/bootstrap/cluster-resources/kustomization.yaml
git commit -m "fix: Temporarily disable bootstrap resources requiring CRDs

- Commented out argocd-ingress (requires Ingress Controller)
- Commented out cluster-issuer (requires cert-manager)
- Commented out rollouts-extension (requires ArgoCD Rollouts)

These will be re-enabled after infrastructure ApplicationSets deploy
the required CRDs and controllers.
"
git push origin main

# 4. 等待 ArgoCD 自動刷新 (3 分鐘),或強制刷新
kubectl patch application cluster-bootstrap -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge

# 5. 等待 30 秒後檢查狀態
sleep 30
kubectl get application cluster-bootstrap -n argocd

# 預期輸出: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

### 後續步驟 (部署基礎設施後)

```bash
# 1. 等待基礎設施 ApplicationSets 部署 cert-manager, ingress-nginx 等

# 2. 檢查基礎設施狀態
kubectl get pods -n cert-manager
kubectl get pods -n ingress-nginx
kubectl get pods -n argo-rollouts

# 3. 確認 CRDs 已安裝
kubectl get crd | grep -E "cert-manager|ingress|rollouts"

# 4. 重新啟用 bootstrap 資源
# 編輯 argocd/bootstrap/cluster-resources/kustomization.yaml
# 取消註解之前移除的資源

# 5. Commit 並 push
git add argocd/bootstrap/cluster-resources/kustomization.yaml
git commit -m "feat: Re-enable bootstrap resources after infrastructure deployment"
git push origin main

# 6. 同步 cluster-bootstrap
argocd app sync cluster-bootstrap --force
```

---

## 📋 檢查清單

### 當前狀態

- [x] ArgoCD 完全運行 (7/7 components)
- [x] Git Repository 認證已配置
- [x] Root Application 已同步 (Synced)
- [x] ApplicationSets 已建立 (2 個)
- [ ] cluster-bootstrap 同步成功
- [ ] 基礎設施組件部署 (cert-manager, ingress-nginx, etc.)

### 下一步驗證

```bash
# 1. 檢查所有 Applications
kubectl get applications -n argocd

# 2. 檢查所有 ApplicationSets
kubectl get applicationset -n argocd

# 3. 檢查 ArgoCD UI
# 訪問 https://localhost:8080
# 查看所有 Applications 的狀態

# 4. 檢查基礎設施 Pods
kubectl get pods --all-namespaces | grep -E "cert-manager|ingress|rollouts|metallb"
```

---

## 🔧 故障排除

### 問題: cluster-bootstrap 仍然 OutOfSync

**檢查**:
```bash
# 1. 查看詳細錯誤
kubectl describe application cluster-bootstrap -n argocd | tail -50

# 2. 檢查 Git revision
kubectl get application cluster-bootstrap -n argocd -o jsonpath='{.status.sync.revision}'

# 3. 手動觸發同步
argocd app sync cluster-bootstrap --force
```

### 問題: 無法訪問 ArgoCD UI

**檢查**:
```bash
# 1. 確認 argocd-server pod 運行
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server

# 2. 檢查 service
kubectl get svc argocd-server -n argocd

# 3. 測試 port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0

# 4. 檢查防火牆/網路
curl -k https://localhost:8080
```

### 問題: Git 認證失敗

**檢查**:
```bash
# 1. 驗證 repository secret
kubectl get secret detectviz-gitops-repo -n argocd

# 2. 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50

# 3. 測試 SSH 連接
ssh -i ~/.ssh/id_ed25519_detectviz -T git@github.com
```

---

## 📖 相關文件

- **ansible/DEPLOYMENT_COMPLETE_FINAL.md** - 完整部署報告
- **ansible/GIT_REPOSITORY_AUTO_CONFIGURATION.md** - Git 認證自動化說明
- **ansible/ARGOCD_GIT_REPOSITORY_SETUP.md** - Git 認證手動設定參考
- **argocd/bootstrap/README.md** - Bootstrap 資源說明

---

**文檔更新**: 2025-11-14
**ArgoCD 版本**: v3.2.0
**集群狀態**: 健康,等待基礎設施部署
