# ArgoCD Git Repository SSH 認證設定與自動化

**最後更新**: 2025-11-14
**狀態**: ✅ 已自動化

---

## 概述

從 Phase 6 開始,Git Repository SSH 認證配置已經**完全自動化**,不再需要手動執行命令。本文檔說明自動化配置流程以及手動配置方法(用於故障排除)。

---

## 📋 自動化配置 (推薦)

### 前置條件

#### 1. 生成 SSH 金鑰

在執行 Ansible 部署前,必須先生成專用的 SSH 金鑰:

```bash
# 生成專用的 SSH 金鑰 (不使用密碼保護)
ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/id_ed25519_detectviz -N ""
```

#### 2. 將公鑰添加到 GitHub

```bash
# 顯示公鑰
cat ~/.ssh/id_ed25519_detectviz.pub
```

**在 GitHub 上添加 Deploy Key**:
1. 前往: https://github.com/detectviz/detectviz-gitops/settings/keys
2. 點擊 **Add deploy key**
3. 填寫:
   - **Title**: `ArgoCD Kubernetes Cluster`
   - **Key**: (貼上公鑰內容)
   - **Allow write access**: ❌ 不勾選 (只需讀取權限)
4. 點擊 **Add key**

### 自動化部署流程

完成前置條件後,執行完整部署:

```bash
# 1. 確認 SSH 金鑰存在
ls -la ~/.ssh/id_ed25519_detectviz*

# 2. 執行完整部署 (一鍵完成所有配置)
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml

# 3. 驗證結果
kubectl get application root -n argocd
# 預期輸出: SYNC STATUS = Synced
```

### 自動化功能

Phase 6 會自動執行以下步驟:

1. ✅ 檢查 SSH 私鑰是否存在 (`~/.ssh/id_ed25519_detectviz`)
2. ✅ 自動複製 SSH 私鑰到遠端主機
3. ✅ 自動建立 ArgoCD repository secret
4. ✅ 自動添加標籤和配置 repository URL
5. ✅ 自動獲取並配置 GitHub SSH known_hosts
6. ✅ 自動重啟 ArgoCD repo-server
7. ✅ 自動刷新 root application
8. ✅ 自動清理臨時檔案

### 容錯處理

- **SSH 金鑰存在**: 自動配置所有認證,Root Application 立即同步
- **SSH 金鑰不存在**: 顯示詳細警告訊息,提供手動配置指引

---

## 🔧 手動配置 (故障排除用)

### 問題說明

Root Application 無法同步 Git repository,錯誤訊息:

```
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = failed to list refs:
error creating SSH agent: "SSH agent requested but SSH_AUTH_SOCK not-specified"
```

**原因**: ArgoCD 需要 SSH 金鑰才能訪問私有 GitHub repository

### 方法 1: 配置 SSH Private Key (推薦)

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

# 為 secret 添加 repository 配置
kubectl patch secret detectviz-gitops-repo -n argocd \
  -p='{"stringData":{
    "type":"git",
    "url":"git@github.com:detectviz/detectviz-gitops.git"
  }}'
```

#### 步驟 4: 配置 SSH Known Hosts

```bash
# 獲取 GitHub 的 SSH host key
ssh-keyscan github.com > /tmp/github-hostkey

# 建立 known_hosts secret
kubectl create secret generic argocd-ssh-known-hosts \
  --from-file=ssh_known_hosts=/tmp/github-hostkey \
  -n argocd
```

#### 步驟 5: 重啟 ArgoCD Repo Server

```bash
# 重啟 ArgoCD repo-server 以載入新的 secret
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd

# 強制刷新 root application
sleep 5
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

### 方法 2: 使用 HTTPS (適用於公開 repository)

如果這是公開 repository,可以改用 HTTPS URL:

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

### 方法 3: 使用 ArgoCD CLI (互動式)

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

## ✅ 驗證步驟

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

---

## 🔍 故障排除

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

### 問題 4: SSH 金鑰存在但仍顯示警告

**症狀**: Ansible 顯示 "SSH 私鑰未找到" 警告

**原因**: SSH 金鑰路徑不正確

**解決方案**:
```bash
# 檢查金鑰路徑
ls -la ~/.ssh/id_ed25519_detectviz

# 如果路徑不同,建立軟連結
ln -s ~/.ssh/your-actual-key ~/.ssh/id_ed25519_detectviz
```

---

## 📚 技術實現細節 (Ansible)

### Ansible 任務流程

#### 1. 檢查 SSH 金鑰

```yaml
- name: "Check if SSH private key exists"
  ansible.builtin.stat:
    path: "{{ lookup('env', 'HOME') }}/.ssh/id_ed25519_detectviz"
  register: ssh_key_stat
  delegate_to: localhost
  become: false
```

#### 2. 條件執行區塊

```yaml
- name: "Configure ArgoCD Git Repository authentication"
  when: ssh_key_stat.stat.exists
  block:
    # ... 所有配置任務
```

#### 3. 建立 Repository Secret

```yaml
- name: "Create ArgoCD repository secret"
  ansible.builtin.command: >
    kubectl create secret generic detectviz-gitops-repo
    --from-file=sshPrivateKey=/tmp/argocd-ssh-key
    -n argocd
    --dry-run=client -o yaml
  register: repo_secret_yaml

- name: "Apply ArgoCD repository secret"
  kubernetes.core.k8s:
    state: present
    definition: "{{ repo_secret_yaml.stdout | from_yaml }}"
    namespace: argocd
```

#### 4. 獲取 GitHub Known Hosts

```yaml
- name: "Get GitHub SSH known_hosts"
  ansible.builtin.command: ssh-keyscan github.com
  register: github_known_hosts
  delegate_to: localhost

- name: "Create SSH known_hosts secret"
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: argocd-ssh-known-hosts
        namespace: argocd
      type: Opaque
      stringData:
        ssh_known_hosts: "{{ github_known_hosts.stdout }}"
```

---

## 🔒 安全考量

### SSH 金鑰管理

1. **不要在 Git 中儲存私鑰**:
   - ✅ SSH 金鑰只存在於本地機器
   - ✅ Ansible 自動清理臨時檔案
   - ✅ Secret 只存在於 Kubernetes 中

2. **最小權限原則**:
   - ✅ Deploy Key 只有讀取權限
   - ✅ 不勾選 "Allow write access"

3. **金鑰輪換**:
   - 建議每 6-12 個月輪換一次 deploy key
   - 輪換步驟:
     ```bash
     # 1. 生成新金鑰
     ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_detectviz_new -N ""

     # 2. 添加新公鑰到 GitHub

     # 3. 刪除舊 secret
     kubectl delete secret detectviz-gitops-repo -n argocd

     # 4. 替換金鑰
     mv ~/.ssh/id_ed25519_detectviz ~/.ssh/id_ed25519_detectviz.old
     mv ~/.ssh/id_ed25519_detectviz_new ~/.ssh/id_ed25519_detectviz

     # 5. 重新執行部署
     ansible-playbook -i inventory.ini deploy-cluster.yml

     # 6. 從 GitHub 刪除舊公鑰
     ```

### Kubernetes Secret 管理

考慮使用以下工具增強 secret 安全性:

1. **Sealed Secrets**: 加密 secrets 並存入 Git
2. **External Secrets Operator**: 從 Vault 同步 secrets
3. **SOPS**: 加密敏感檔案

---

## 📊 自動化 vs 手動對比

| 項目 | 手動配置 | 自動配置 |
|------|---------|---------|
| **配置時間** | 5-10 分鐘 | 0 分鐘 (自動) |
| **出錯風險** | 高 (8 個步驟) | 低 (自動化) |
| **冪等性** | ❌ 難以重複 | ✅ 可重複執行 |
| **容錯處理** | ❌ 手動檢查 | ✅ 自動檢查 |
| **清理** | ❌ 手動清理 | ✅ 自動清理 |
| **警告訊息** | ❌ 無 | ✅ 詳細指引 |

---

## ✅ 總結

**關鍵改進**:
- ✅ Git Repository SSH 認證現在**完全自動化**
- ✅ 只需確保 SSH 金鑰存在,其餘全自動
- ✅ 容錯處理完善,SSH 金鑰不存在會顯示詳細警告
- ✅ 可重複執行,冪等性保證

**相關文件**:
- `ansible/deploy-cluster.yml:191-344` (自動化配置代碼)
- `deploy.md:538-580` (手動配置步驟參考)

---

**文檔版本**: 2.0
**自動化狀態**: ✅ 已實施並驗證
