# ArgoCD Root Application 檔案路徑修正

## 問題描述

在 Phase 6 部署 ArgoCD Root Application 時遇到檔案路徑問題:

**錯誤訊息**:
```
[ERROR]: Task failed: Module failed: Failed to load resource definition:
[Errno 2] No such file or directory: '/Users/zoe/Documents/github/detectviz-gitops/argocd/root-argocd-app.yaml'
```

**原因**:
- `kubernetes.core.k8s` 模組在**遠端主機 (master-1)** 上執行
- 但 `src: "{{ playbook_dir }}/../argocd/root-argocd-app.yaml"` 指向的是 **Ansible 控制機** 上的檔案路徑
- 遠端主機無法訪問控制機上的檔案系統

---

## 修正方案

### 問題分析

kubernetes.core.k8s 模組的 `src` 參數有兩種行為:
1. **相對路徑**: 模組會在遠端主機上查找檔案
2. **絕對路徑**: 模組仍然在遠端主機上查找檔案

無論哪種情況,檔案都必須存在於**遠端主機**上,而不是 Ansible 控制機。

### 解決方案: 先複製,再應用

**檔案**: `ansible/deploy-cluster.yml:191-206`

**修正前**:
```yaml
# 部署 ArgoCD Root Application (App of Apps 模式)
- name: "Bootstrap ArgoCD Root Application (啟動 ArgoCD 根應用程式)"
  kubernetes.core.k8s:
    state: present
    src: "{{ playbook_dir }}/../argocd/root-argocd-app.yaml"  # ❌ 控制機路徑
    namespace: argocd
  become: true
```

**修正後**:
```yaml
# 部署 ArgoCD Root Application (App of Apps 模式)
# 先將 root application manifest 複製到遠端主機
- name: "Copy ArgoCD Root Application manifest to remote host (複製 ArgoCD 根應用程式 manifest 到遠端主機)"
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/../argocd/root-argocd-app.yaml"  # ✅ 從控制機複製
    dest: "/tmp/root-argocd-app.yaml"                          # ✅ 到遠端主機
    mode: "0644"

# 應用 Root Application manifest
- name: "Bootstrap ArgoCD Root Application (啟動 ArgoCD 根應用程式)"
  kubernetes.core.k8s:
    state: present
    src: "/tmp/root-argocd-app.yaml"  # ✅ 使用遠端主機路徑
    namespace: argocd
  become: true
```

---

## 為什麼需要這樣做?

### Ansible 模組的檔案處理

不同 Ansible 模組對 `src` 參數的處理方式不同:

| 模組 | `src` 參數行為 |
|------|---------------|
| **ansible.builtin.copy** | 從控制機複製到遠端主機 ✅ |
| **ansible.builtin.template** | 從控制機渲染並複製到遠端主機 ✅ |
| **kubernetes.core.k8s** | 在遠端主機上查找檔案 ❌ |
| **ansible.builtin.command** | 在遠端主機上執行 ❌ |

### 為什麼 kubernetes.core.k8s 不自動複製?

kubernetes.core.k8s 模組設計用於:
1. **遠端主機已有 manifest 檔案** (例如透過 git clone 或其他方式)
2. **直接傳遞 YAML 內容** (使用 `definition` 參數而非 `src`)

如果需要使用控制機上的檔案,必須先手動複製到遠端主機。

---

## 替代方案

### 方案 1: 使用 kubectl apply (推薦用於簡單場景)

```yaml
# 不需要複製檔案,直接 pipe YAML 內容
- name: "Bootstrap ArgoCD Root Application"
  ansible.builtin.shell: |
    cat << 'EOF' | kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f -
    {{ lookup('file', playbook_dir + '/../argocd/root-argocd-app.yaml') }}
    EOF
  become: true
```

**優點**:
- 單一任務完成
- 不需要在遠端主機留下臨時檔案

**缺點**:
- 無法使用 kubernetes.core.k8s 模組的等待/驗證功能
- 錯誤處理較複雜

### 方案 2: 使用 definition 參數

```yaml
- name: "Bootstrap ArgoCD Root Application"
  kubernetes.core.k8s:
    state: present
    definition: "{{ lookup('file', playbook_dir + '/../argocd/root-argocd-app.yaml') | from_yaml }}"
    namespace: argocd
  become: true
```

**優點**:
- 直接傳遞 YAML 內容,不需要檔案
- 保留 kubernetes.core.k8s 模組的所有功能

**缺點**:
- 對於大型 manifest,可能造成任務定義過長

### 方案 3: 使用 copy + k8s (當前採用)

```yaml
- name: "Copy ArgoCD Root Application manifest"
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/../argocd/root-argocd-app.yaml"
    dest: "/tmp/root-argocd-app.yaml"
    mode: "0644"

- name: "Bootstrap ArgoCD Root Application"
  kubernetes.core.k8s:
    state: present
    src: "/tmp/root-argocd-app.yaml"
    namespace: argocd
  become: true
```

**優點**:
- 清晰易懂,兩個步驟分離
- 保留 kubernetes.core.k8s 模組的所有功能
- 易於除錯 (可以在遠端主機上查看檔案)

**缺點**:
- 需要兩個任務
- 在遠端主機留下臨時檔案

---

## 驗證方法

### 部署後檢查

**檢查 Root Application**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get application -n argocd
```

**預期輸出**:
```
NAME   SYNC STATUS   HEALTH STATUS
root   Synced        Healthy
```

**檢查 Root Application 詳情**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf describe application root -n argocd
```

**檢查 ApplicationSets** (由 Root Application 管理):
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get applicationset -n argocd
```

**預期看到**:
- infrastructure (基礎設施 ApplicationSet)
- 其他 ApplicationSets (如果已定義)

### 檢查 ArgoCD UI

1. **獲取 ArgoCD admin 密碼**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

2. **設定 Port Forward**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf port-forward svc/argocd-server -n argocd 8080:443
```

3. **訪問 ArgoCD UI**:
- URL: https://localhost:8080
- Username: `admin`
- Password: (步驟 1 獲取的密碼)

4. **驗證 Root Application**:
- 在 Applications 頁面應該看到 "root" application
- 狀態應該是 "Synced" 和 "Healthy"

---

## 常見問題 (FAQ)

### Q1: 為什麼不使用 `definition` 參數?

**A**: `definition` 參數適用於簡單的單一資源,但對於 App of Apps 模式,使用檔案更清晰。此外,`definition` 需要將整個 YAML 內容嵌入到任務中,降低可讀性。

### Q2: 臨時檔案 `/tmp/root-argocd-app.yaml` 會自動清理嗎?

**A**: 不會自動清理,但這不是問題:
1. /tmp 通常會在系統重啟時清空
2. 檔案很小 (< 1KB)
3. 重複執行部署會覆蓋舊檔案

如果需要手動清理:
```yaml
- name: "Clean up temporary manifest"
  ansible.builtin.file:
    path: "/tmp/root-argocd-app.yaml"
    state: absent
```

### Q3: 可以使用其他目錄嗎?

**A**: 可以,但建議使用 `/tmp`:
- `/tmp` 具有標準權限,所有使用者都可以寫入
- 不需要事先建立目錄
- 系統會自動管理生命週期

如果使用其他目錄,確保:
1. 目錄已存在
2. ansible_user 有寫入權限

### Q4: 為什麼 Phase 6 其他任務不需要複製檔案?

**A**: 因為它們使用不同的方法:
1. **ArgoCD install manifest**: 使用 `get_url` 從 GitHub 下載到遠端主機
2. **NodeSelector patching**: 使用 `kubectl patch`,不需要檔案
3. **Secret patching**: 使用 `kubectl patch`,不需要檔案

只有需要應用本地 manifest 檔案時,才需要先複製到遠端主機。

---

## 相關資源

### Ansible 文件
- [kubernetes.core.k8s module](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/k8s_module.html)
- [ansible.builtin.copy module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html)
- [Ansible lookup plugins](https://docs.ansible.com/ansible/latest/plugins/lookup.html)

### ArgoCD 文件
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)

---

## 總結

| 項目 | 說明 |
|------|------|
| **問題根因** | kubernetes.core.k8s 模組在遠端主機查找檔案,無法訪問控制機檔案系統 |
| **解決方案** | 先用 copy 模組複製檔案到遠端主機,再用 k8s 模組應用 |
| **修正檔案** | ansible/deploy-cluster.yml:191-206 |
| **影響範圍** | Phase 6: ArgoCD 部署 - Bootstrap Root Application 任務 |
| **測試狀態** | ✅ 待驗證 (需要重新執行部署) |

**關鍵重點**:
- ✅ kubernetes.core.k8s 模組的 `src` 參數必須指向遠端主機上的檔案
- ✅ 使用 ansible.builtin.copy 將控制機上的檔案複製到遠端主機
- ✅ 這是 Ansible 跨主機檔案操作的標準做法
- ✅ 替代方案包括使用 `definition` 參數或 kubectl 命令

---

**文檔更新**: 2025-11-14
**相關文件**:
- ansible/deploy-cluster.yml:191-206 (修正後的代碼)
- ansible/CONFIGURATION_FIXES_COMPLETE.md (完整修正報告)
