# ArgoCD Git Repository SSH 認證設定

## 問題說明

Root Application 無法同步 Git repository,錯誤訊息:

```
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = failed to list refs:
error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"
```

**原因**: ArgoCD 需要 SSH 金鑰才能訪問私有 GitHub repository (`git@github.com:detectviz/detectviz-gitops.git`)

---

## 解決方案

### 方法 1: 配置 SSH Private Key (推薦用於私有 repository)

#### 步驟 1: 生成 Deploy Key (如果還沒有)

```bash
# 在本地機器生成專用的 SSH 金鑰 (不使用密碼保護)
ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/argocd-deploy-key -N ""

# 顯示公鑰
cat ~/.ssh/argocd-deploy-key.pub
```

#### 步驟 2: 在 GitHub 添加 Deploy Key

1. 前往 GitHub repository: https://github.com/detectviz/detectviz-gitops
2. 點擊 **Settings** → **Deploy keys** → **Add deploy key**
3. 填寫資訊:
   - **Title**: `ArgoCD Kubernetes Cluster`
   - **Key**: (貼上上一步驟的公鑰內容)
   - **Allow write access**: ❌ 不勾選 (ArgoCD 只需要讀取權限)
4. 點擊 **Add key**

#### 步驟 3: 將 Private Key 添加到 ArgoCD

```bash
# 建立 ArgoCD repository secret
kubectl create secret generic detectviz-gitops-repo \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd-deploy-key \
  -n argocd

# 為 secret 添加標籤,讓 ArgoCD 識別為 repository credential
kubectl label secret detectviz-gitops-repo \
  argocd.argoproj.io/secret-type=repository \
  -n argocd

# 為 secret 添加 annotations,指定 repository URL
kubectl annotate secret detectviz-gitops-repo \
  managed-by=argocd.argoproj.io \
  -n argocd

# 為 secret 添加 repository 配置
kubectl patch secret detectviz-gitops-repo -n argocd \
  -p='{"stringData":{
    "type":"git",
    "url":"git@github.com:detectviz/detectviz-gitops.git"
  }}'
```

#### 步驟 4: 驗證 Repository Connection

```bash
# 檢查 secret
kubectl get secret detectviz-gitops-repo -n argocd -o yaml

# 重新同步 root application
kubectl delete application root -n argocd
kubectl apply -f /tmp/root-argocd-app.yaml -n argocd

# 等待幾秒後檢查狀態
kubectl get application root -n argocd
kubectl describe application root -n argocd
```

---

### 方法 2: 使用 HTTPS 並改用公開 URL (適用於公開 repository)

如果這是公開 repository,可以改用 HTTPS URL:

#### 步驟 1: 修改 Root Application 使用 HTTPS

```bash
# 編輯 root application manifest
kubectl edit application root -n argocd

# 修改 spec.source.repoURL:
# 從: git@github.com:detectviz/detectviz-gitops.git
# 到: https://github.com/detectviz/detectviz-gitops.git
```

或者修改本地檔案並重新應用:

```bash
# 編輯本地檔案
vim argocd/root-argocd-app.yaml

# 修改 repoURL 行:
repoURL: 'https://github.com/detectviz/detectviz-gitops.git'

# 刪除並重新建立 application
kubectl delete application root -n argocd
kubectl apply -f argocd/root-argocd-app.yaml -n argocd
```

---

### 方法 3: 使用 ArgoCD CLI 添加 Repository (互動式)

```bash
# 1. 安裝 ArgoCD CLI (如果還沒有)
curl -sSL -o /tmp/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 /tmp/argocd /usr/local/bin/argocd

# 2. Port forward ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# 3. 登入 ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

# 4. 添加 repository (SSH)
argocd repo add git@github.com:detectviz/detectviz-gitops.git \
  --ssh-private-key-path ~/.ssh/argocd-deploy-key \
  --insecure-ignore-host-key

# 或添加 repository (HTTPS,公開 repo)
argocd repo add https://github.com/detectviz/detectviz-gitops.git

# 5. 驗證 repository 連接
argocd repo list
```

---

## 驗證步驟

### 1. 檢查 Repository Secret

```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

**預期輸出**:
```
NAME                      TYPE     DATA   AGE
detectviz-gitops-repo     Opaque   3      1m
```

### 2. 檢查 Repository 配置

```bash
kubectl get secret detectviz-gitops-repo -n argocd -o jsonpath='{.data}' | jq
```

**預期包含**:
- `sshPrivateKey`: SSH 私鑰 (base64 編碼)
- `type`: "git"
- `url`: repository URL

### 3. 檢查 Root Application 狀態

```bash
kubectl get application root -n argocd
```

**預期輸出**:
```
NAME   SYNC STATUS   HEALTH STATUS
root   Synced        Healthy
```

### 4. 檢查 ApplicationSets

```bash
kubectl get applicationset -n argocd
```

**預期看到**:
- `infrastructure` - 基礎設施 ApplicationSet
- 其他 ApplicationSets (取決於 `argocd/appsets/` 目錄內容)

### 5. 檢查 Root Application 詳情

```bash
kubectl describe application root -n argocd | tail -20
```

**健康狀態應該顯示**:
```
Status:
  Health:
    Status:  Healthy
  Sync:
    Status:  Synced
```

---

## 故障排除

### 問題 1: "Host key verification failed"

**錯誤訊息**:
```
failed to list refs: Host key verification failed
```

**解決方案**: 添加 GitHub 的 host key 到 known_hosts

```bash
# 獲取 GitHub 的 SSH host key
ssh-keyscan github.com > /tmp/github-hostkey

# 建立 known_hosts secret
kubectl create secret generic argocd-ssh-known-hosts \
  --from-file=ssh_known_hosts=/tmp/github-hostkey \
  -n argocd

# 或者在添加 repository 時使用 --insecure-ignore-host-key
argocd repo add git@github.com:detectviz/detectviz-gitops.git \
  --ssh-private-key-path ~/.ssh/argocd-deploy-key \
  --insecure-ignore-host-key
```

### 問題 2: "Permission denied (publickey)"

**錯誤訊息**:
```
failed to list refs: Permission denied (publickey)
```

**可能原因**:
1. Deploy key 沒有正確添加到 GitHub
2. Private key 格式錯誤
3. Repository URL 錯誤

**解決方案**:
```bash
# 1. 驗證 deploy key 在 GitHub 上
# 前往: https://github.com/detectviz/detectviz-gitops/settings/keys

# 2. 測試 SSH 連接
ssh -i ~/.ssh/argocd-deploy-key -T git@github.com
# 預期輸出: "Hi detectviz! You've successfully authenticated..."

# 3. 檢查 secret 內容
kubectl get secret detectviz-gitops-repo -n argocd -o jsonpath='{.data.sshPrivateKey}' | base64 -d | head -1
# 應該顯示: -----BEGIN OPENSSH PRIVATE KEY-----

# 4. 刪除並重新建立 secret
kubectl delete secret detectviz-gitops-repo -n argocd
kubectl create secret generic detectviz-gitops-repo \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd-deploy-key \
  -n argocd
kubectl label secret detectviz-gitops-repo \
  argocd.argoproj.io/secret-type=repository -n argocd
kubectl patch secret detectviz-gitops-repo -n argocd \
  -p='{"stringData":{"type":"git","url":"git@github.com:detectviz/detectviz-gitops.git"}}'
```

### 問題 3: Root Application 仍然顯示 "Unknown"

**錯誤訊息**:
```
SYNC STATUS   HEALTH STATUS
Unknown       Healthy
```

**解決方案**:
```bash
# 1. 強制刷新 application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge

# 2. 等待 ArgoCD 重新同步 (約 3 分鐘)
watch kubectl get application root -n argocd

# 3. 手動觸發同步
argocd app sync root --prune --force

# 4. 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50
```

### 問題 4: "argocd/appsets" 路徑不存在

**錯誤訊息**:
```
path 'argocd/appsets' does not exist
```

**解決方案**: 檢查 repository 結構

```bash
# 確認 argocd/appsets 目錄是否存在
ls -la argocd/appsets/

# 如果不存在,建立目錄和範例 ApplicationSet
mkdir -p argocd/appsets

# 建立範例 infrastructure ApplicationSet
cat > argocd/appsets/infrastructure.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: git@github.com:detectviz/detectviz-gitops.git
        revision: main
        directories:
          - path: argocd/apps/infrastructure/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: git@github.com:detectviz/detectviz-gitops.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
EOF

# Commit 並 push 到 GitHub
git add argocd/appsets/infrastructure.yaml
git commit -m "Add infrastructure ApplicationSet"
git push origin main

# 等待 ArgoCD 重新同步
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

---

## 自動化腳本

### 完整設定腳本 (setup-argocd-repo.sh)

```bash
#!/bin/bash
set -e

echo "=== ArgoCD Git Repository 認證設定 ==="

# 檢查環境
if [ ! -f "$HOME/.ssh/argocd-deploy-key" ]; then
  echo "❌ SSH 金鑰不存在: $HOME/.ssh/argocd-deploy-key"
  echo "請先執行: ssh-keygen -t ed25519 -C 'argocd-deploy-key' -f ~/.ssh/argocd-deploy-key -N ''"
  exit 1
fi

# 建立 repository secret
echo "1. 建立 ArgoCD repository secret..."
kubectl create secret generic detectviz-gitops-repo \
  --from-file=sshPrivateKey=$HOME/.ssh/argocd-deploy-key \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# 添加標籤
echo "2. 添加 ArgoCD 標籤..."
kubectl label secret detectviz-gitops-repo \
  argocd.argoproj.io/secret-type=repository \
  -n argocd \
  --overwrite

# 添加 repository 配置
echo "3. 配置 repository URL..."
kubectl patch secret detectviz-gitops-repo -n argocd \
  -p='{"stringData":{
    "type":"git",
    "url":"git@github.com:detectviz/detectviz-gitops.git"
  }}'

# 建立 SSH known_hosts
echo "4. 添加 GitHub SSH known_hosts..."
ssh-keyscan github.com > /tmp/github-hostkey
kubectl create secret generic argocd-ssh-known-hosts \
  --from-file=ssh_known_hosts=/tmp/github-hostkey \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

# 重啟 ArgoCD repo-server 以載入新的 secret
echo "5. 重啟 ArgoCD repo-server..."
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# 強制刷新 root application
echo "6. 刷新 Root Application..."
sleep 5
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge

echo ""
echo "✅ ArgoCD Git Repository 認證設定完成!"
echo ""
echo "請執行以下命令驗證:"
echo "  kubectl get application root -n argocd"
echo "  kubectl describe application root -n argocd | tail -20"
```

**使用方法**:
```bash
chmod +x setup-argocd-repo.sh
./setup-argocd-repo.sh
```

---

## 最佳實踐

### 1. 使用專用的 Deploy Key

- ✅ 為每個集群生成獨立的 SSH 金鑰
- ✅ Deploy key 不設定密碼保護 (ArgoCD 無法處理加密的私鑰)
- ✅ 只授予讀取權限 (不勾選 "Allow write access")
- ✅ 定期輪換 deploy keys

### 2. Repository Secret 管理

- ✅ 使用 Kubernetes Secrets 儲存 SSH 私鑰
- ✅ 添加正確的標籤讓 ArgoCD 識別
- ✅ 考慮使用 Sealed Secrets 或 Vault 管理敏感資訊

### 3. 多 Repository 支援

如果有多個 Git repositories:

```bash
# 為每個 repository 建立獨立的 secret
kubectl create secret generic repo1-credentials \
  --from-file=sshPrivateKey=$HOME/.ssh/repo1-key \
  -n argocd

kubectl label secret repo1-credentials \
  argocd.argoproj.io/secret-type=repository -n argocd

kubectl patch secret repo1-credentials -n argocd \
  -p='{"stringData":{"type":"git","url":"git@github.com:org/repo1.git"}}'
```

### 4. 監控 Repository 連接狀態

```bash
# 定期檢查 repository 連接
argocd repo list

# 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -f
```

---

## 總結

| 步驟 | 說明 | 狀態 |
|------|------|------|
| 1. 生成 SSH 金鑰 | `ssh-keygen -t ed25519 -f ~/.ssh/argocd-deploy-key -N ""` | ⏳ 待執行 |
| 2. 添加到 GitHub | Settings → Deploy keys → Add key | ⏳ 待執行 |
| 3. 建立 K8s Secret | `kubectl create secret generic detectviz-gitops-repo` | ⏳ 待執行 |
| 4. 添加標籤 | `kubectl label secret ... argocd.argoproj.io/secret-type=repository` | ⏳ 待執行 |
| 5. 配置 URL | `kubectl patch secret ... url=git@github.com:...` | ⏳ 待執行 |
| 6. 驗證連接 | `kubectl get application root -n argocd` | ⏳ 待執行 |

**當前狀態**: Root Application 已建立,但無法同步 (缺少 SSH 認證)

**下一步操作**: 執行上述步驟配置 SSH 金鑰,或改用 HTTPS URL (如果是公開 repository)

---

**文檔更新**: 2025-11-14
**相關文件**:
- ansible/DEPLOYMENT_SUCCESS_SUMMARY.md (部署摘要)
- argocd/root-argocd-app.yaml (Root Application manifest)
