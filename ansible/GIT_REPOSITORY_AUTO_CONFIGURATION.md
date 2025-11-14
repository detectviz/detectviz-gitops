# Git Repository SSH 認證自動配置

## 概述

從這次部署開始,Git Repository SSH 認證配置已經**完全自動化**,不再需要手動執行命令。

**修改版本**: 2025-11-14
**影響範圍**: Phase 6 - ArgoCD 部署

---

## 自動化內容

### 新增功能

Phase 6 現在會自動執行以下步驟:

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

## 前置條件

### 必須完成 (在執行 Ansible 部署前)

#### 1. 生成 SSH 金鑰

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
   - **Allow write access**: ❌ 不勾選
4. 點擊 **Add key**

**完成後即可執行 Ansible 部署,所有 Git 認證配置都會自動完成！**

---

## 部署流程

### 自動化部署 (推薦)

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

### 部署時的輸出

**如果 SSH 金鑰存在** (自動配置):
```
TASK [Check if SSH private key exists] ************************************
ok: [master-1 -> localhost]

TASK [Configure ArgoCD Git Repository authentication] *********************
included: /path/to/block-tasks

TASK [Copy SSH private key to remote host] ********************************
changed: [master-1]

TASK [Create ArgoCD repository secret] ************************************
ok: [master-1]

TASK [Apply ArgoCD repository secret] *************************************
changed: [master-1]

TASK [Label repository secret] ********************************************
changed: [master-1]

TASK [Configure repository URL] *******************************************
changed: [master-1]

TASK [Get GitHub SSH known_hosts] *****************************************
ok: [master-1 -> localhost]

TASK [Create SSH known_hosts secret] **************************************
changed: [master-1]

TASK [Restart ArgoCD repo-server] *****************************************
changed: [master-1]

TASK [Wait for repo-server restart] ***************************************
ok: [master-1]

TASK [Clean up temporary SSH key] *****************************************
changed: [master-1]

TASK [Force refresh root application] *************************************
changed: [master-1]

TASK [Wait for root application to sync] **********************************
Pausing for 10 seconds
ok: [master-1]
```

**如果 SSH 金鑰不存在** (顯示警告):
```
TASK [Check if SSH private key exists] ************************************
ok: [master-1 -> localhost]

TASK [Display warning if SSH key not found] *******************************
ok: [master-1] => {
    "msg": [
        "⚠️  WARNING: SSH 私鑰未找到!",
        "",
        "路徑: /Users/zoe/.ssh/id_ed25519_detectviz",
        "",
        "Root Application 將無法同步 GitHub repository。",
        "請執行以下步驟配置 SSH 認證:",
        "",
        "1. 生成 SSH 金鑰:",
        "   ssh-keygen -t ed25519 -C \"argocd-deploy-key\" -f ~/.ssh/id_ed25519_detectviz -N \"\"",
        "",
        "2. 將公鑰添加到 GitHub repository 的 Deploy Keys:",
        "   https://github.com/detectviz/detectviz-gitops/settings/keys",
        "",
        "3. 重新執行部署或手動配置認證:",
        "   參考文件: ansible/ARGOCD_GIT_REPOSITORY_SETUP.md"
    ]
}
```

---

## 驗證步驟

### 自動配置成功後

```bash
# 1. 檢查 repository secret
kubectl get secret detectviz-gitops-repo -n argocd
kubectl get secret argocd-ssh-known-hosts -n argocd

# 2. 檢查 Root Application 同步狀態
kubectl get application root -n argocd

# 預期輸出:
# NAME   SYNC STATUS   HEALTH STATUS
# root   Synced        Degraded       ← Degraded 是正常的 (子應用尚未部署)

# 3. 檢查 ApplicationSets
kubectl get applicationset -n argocd

# 預期輸出:
# NAME               AGE
# argocd-bootstrap   1m
# detectviz-gitops   1m

# 4. 檢查所有 Applications
kubectl get applications -n argocd

# 預期輸出:
# NAME                SYNC STATUS   HEALTH STATUS
# cluster-bootstrap   OutOfSync     Missing
# root                Synced        Degraded
```

---

## 技術實現細節

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

**說明**: 在 Ansible 控制機 (localhost) 上檢查 SSH 金鑰

#### 2. 條件執行區塊

```yaml
- name: "Configure ArgoCD Git Repository authentication"
  when: ssh_key_stat.stat.exists
  block:
    # ... 所有配置任務
```

**說明**: 只有當 SSH 金鑰存在時,才執行配置任務

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

**說明**: 使用 `--dry-run=client -o yaml` 生成 secret YAML,然後用 kubernetes.core.k8s 模組應用

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

**說明**: 在控制機上執行 `ssh-keyscan`,將結果直接嵌入 secret definition

#### 5. 重啟並等待

```yaml
- name: "Restart ArgoCD repo-server"
  ansible.builtin.command: >
    kubectl rollout restart deployment argocd-repo-server -n argocd

- name: "Wait for repo-server restart"
  ansible.builtin.command: >
    kubectl rollout status deployment argocd-repo-server
    -n argocd --timeout=60s
```

**說明**: 確保 repo-server 重啟完成後才繼續

#### 6. 刷新 Root Application

```yaml
- name: "Force refresh root application"
  ansible.builtin.command: >
    kubectl patch application root -n argocd
    -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
    --type=merge
  when: ssh_key_stat.stat.exists

- name: "Wait for root application to sync"
  ansible.builtin.pause:
    seconds: 10
  when: ssh_key_stat.stat.exists
```

**說明**: 強制刷新並等待 10 秒讓 ArgoCD 重新同步

---

## 與手動配置的比較

### 之前 (手動配置)

```bash
# 需要執行 8 個步驟,約 5-10 分鐘
1. scp SSH key
2. kubectl create secret
3. kubectl label secret
4. kubectl patch secret (add URL)
5. ssh-keyscan + create known_hosts secret
6. kubectl rollout restart
7. kubectl rollout status
8. kubectl patch application (force refresh)
```

**問題**:
- ❌ 容易遺漏步驟
- ❌ 需要手動複製貼上命令
- ❌ 容易出錯 (引號、路徑等)
- ❌ 無法重複執行 (冪等性差)

### 現在 (自動配置)

```bash
# 只需要 1 個步驟,完全自動化
ansible-playbook -i inventory.ini deploy-cluster.yml
```

**優點**:
- ✅ 完全自動化,零人工介入
- ✅ 冪等性保證 (可重複執行)
- ✅ 錯誤處理完善
- ✅ 自動清理臨時檔案
- ✅ 清晰的警告訊息

---

## 故障排除

### 問題 1: SSH 金鑰存在但仍顯示警告

**症狀**: Ansible 顯示 "SSH 私鑰未找到" 警告

**原因**: SSH 金鑰路徑不正確

**解決方案**:
```bash
# 檢查金鑰路徑
ls -la ~/.ssh/id_ed25519_detectviz

# 如果路徑不同,建立軟連結
ln -s ~/.ssh/your-actual-key ~/.ssh/id_ed25519_detectviz
```

### 問題 2: Root Application 仍顯示 "Unknown"

**症狀**: `kubectl get application root -n argocd` 顯示 `Unknown` 狀態

**原因**:
1. SSH 金鑰尚未添加到 GitHub
2. repo-server 尚未完全重啟

**解決方案**:
```bash
# 1. 驗證 GitHub Deploy Key 是否已添加
#    訪問: https://github.com/detectviz/detectviz-gitops/settings/keys

# 2. 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50

# 3. 手動強制刷新
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge

# 4. 等待 30 秒後檢查
sleep 30
kubectl get application root -n argocd
```

### 問題 3: "Permission denied (publickey)"

**症狀**: repo-server 日誌顯示 "Permission denied (publickey)"

**原因**: GitHub Deploy Key 配置錯誤

**解決方案**:
```bash
# 1. 測試 SSH 連接
ssh -i ~/.ssh/id_ed25519_detectviz -T git@github.com
# 預期輸出: "Hi detectviz! You've successfully authenticated..."

# 2. 如果測試失敗,重新添加 Deploy Key
cat ~/.ssh/id_ed25519_detectviz.pub
# 將輸出的公鑰重新添加到 GitHub

# 3. 刪除並重新建立 secret
kubectl delete secret detectviz-gitops-repo -n argocd

# 4. 重新執行部署
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml \
  --start-at-task="Check if SSH private key exists"
```

---

## 配置變數 (進階)

如果需要自訂 SSH 金鑰路徑或 repository URL,可以在 `ansible/group_vars/all.yml` 中添加:

```yaml
# ============================================
# ArgoCD Git Repository 配置
# ============================================
argocd_ssh_key_path: "{{ lookup('env', 'HOME') }}/.ssh/id_ed25519_detectviz"
argocd_repo_url: "git@github.com:detectviz/detectviz-gitops.git"
argocd_repo_type: "git"
```

然後在 `deploy-cluster.yml` 中使用變數:

```yaml
- name: "Check if SSH private key exists"
  ansible.builtin.stat:
    path: "{{ argocd_ssh_key_path }}"
  register: ssh_key_stat
```

---

## 安全考量

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

## 總結

| 項目 | 手動配置 | 自動配置 |
|------|---------|---------|
| **配置時間** | 5-10 分鐘 | 0 分鐘 (自動) |
| **出錯風險** | 高 (8 個步驟) | 低 (自動化) |
| **冪等性** | ❌ 難以重複 | ✅ 可重複執行 |
| **容錯處理** | ❌ 手動檢查 | ✅ 自動檢查 |
| **清理** | ❌ 手動清理 | ✅ 自動清理 |
| **警告訊息** | ❌ 無 | ✅ 詳細指引 |
| **文檔需求** | ❌ 需要詳細手冊 | ✅ 自動化註解 |

**關鍵改進**:
- ✅ Git Repository SSH 認證現在**完全自動化**
- ✅ 只需確保 SSH 金鑰存在,其餘全自動
- ✅ 容錯處理完善,SSH 金鑰不存在會顯示詳細警告
- ✅ 可重複執行,冪等性保證

**相關文件**:
- `ansible/deploy-cluster.yml:191-344` (自動化配置代碼)
- `ansible/ARGOCD_GIT_REPOSITORY_SETUP.md` (手動配置參考)
- `deploy.md:538-580` (手動配置步驟,僅供參考)

---

**文檔更新**: 2025-11-14
**自動化版本**: 1.0
**測試狀態**: ✅ 已驗證成功
