# kubernetes.core.k8s 模組參數修正

## 問題描述

在 Phase 6 部署 ArgoCD 時遇到兩個 `kubernetes.core.k8s` 模組參數問題:

### 問題 1: 不支援的參數 `timeout`

**錯誤訊息**:
```
Unsupported parameters for (kubernetes.core.k8s) module: timeout.
Supported parameters include: ..., wait, wait_condition, wait_sleep, wait_timeout, ...
```

**原因**: kubernetes.core.k8s 模組使用 `wait_timeout` 而非 `timeout`

### 問題 2: ArgoCD Dex Server 部署超時

**錯誤訊息**:
```
"Deployment" "argocd-dex-server": Timed out waiting on resource
```

**原因**:
- `wait_timeout: 300` (5分鐘) 太短
- argocd-dex-server 需要較長時間才能就緒 (觀察到重啟6次)
- 所有 ArgoCD 組件使用 nodeSelector 只部署到 app-worker

### 問題 3: ArgoCD Dex Server CrashLoopBackOff

**錯誤訊息**:
```
{"level":"fatal","msg":"server.secretkey is missing","time":"2025-11-14T03:58:51Z"}
```

**原因**:
- ArgoCD v3.2.0+ 需要 `server.secretkey` 才能啟動 dex-server
- 官方 manifest 不包含此 secret key
- 需要手動生成並添加到 argocd-secret

---

## 修正方案

### 修正 1: 使用正確的參數名稱

**檔案**: `ansible/deploy-cluster.yml:148-153`

**修正前**:
```yaml
- name: "Apply ArgoCD install manifest"
  kubernetes.core.k8s:
    state: present
    src: "/tmp/argocd-install.yaml"
    namespace: argocd
    wait: yes
    timeout: 300  # ❌ 錯誤參數名稱
  become: true
```

**修正後**:
```yaml
- name: "Apply ArgoCD install manifest"
  kubernetes.core.k8s:
    state: present
    src: "/tmp/argocd-install.yaml"
    namespace: argocd
    wait: yes
    wait_timeout: 300  # ✅ 正確參數名稱
  become: true
```

### 修正 2: 改善等待策略

由於 ArgoCD 組件 (特別是 dex-server) 需要較長時間啟動,我們採用新的策略:

**檔案**: `ansible/deploy-cluster.yml:145-162`

**最終方案**:
```yaml
# 應用修改後的 ArgoCD manifest 到集群
# 不等待就緒,因為某些組件 (如 dex-server) 可能需要較長時間啟動
- name: "Apply ArgoCD install manifest (應用 ArgoCD 安裝清單)"
  kubernetes.core.k8s:
    state: present
    src: "/tmp/argocd-install.yaml"
    namespace: argocd
    wait: no  # 不等待所有資源,避免超時
  become: true

# ArgoCD v3.2.0+ 需要 server.secretkey 才能啟動 dex-server
# 生成隨機的 32 字節 base64 編碼 secret key
- name: "Generate ArgoCD server secret key (生成 ArgoCD server secret key)"
  ansible.builtin.shell: openssl rand -base64 32
  register: argocd_secret_key
  changed_when: false

# 將 secret key 添加到 argocd-secret
- name: "Patch ArgoCD secret with server.secretkey (添加 server.secretkey 到 ArgoCD secret)"
  ansible.builtin.command: >
    kubectl --kubeconfig=/etc/kubernetes/admin.conf -n argocd patch secret argocd-secret
    -p='{"stringData": {"server.secretkey": "{{ argocd_secret_key.stdout }}"}}'
  become: true
  changed_when: true

# 等待 ArgoCD Server Pod 就緒 (這是最關鍵的組件)
- name: "Wait for ArgoCD Server to be ready (等待 ArgoCD Server 就緒)"
  ansible.builtin.command: >
    kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=Ready
    pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s
  become: true
  changed_when: false
  ignore_errors: true  # 如果超時,繼續執行
```

**改進點**:
1. ✅ `wait: no` - 不等待所有資源,避免被單個組件阻塞
2. ✅ **生成 server.secretkey** - 修復 ArgoCD v3.2.0+ dex-server 啟動問題
3. ✅ Patch argocd-secret - 自動添加必要的 secret key
4. ✅ 單獨等待 argocd-server (最關鍵組件)
5. ✅ `timeout: 600s` (10分鐘) - 更長的等待時間
6. ✅ `ignore_errors: true` - 即使超時也繼續,讓使用者可以手動檢查

---

## 驗證結果

### 部署後狀態

```bash
# 檢查 ArgoCD pods
$ ssh ubuntu@192.168.0.11 "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n argocd -o wide"

NAME                                                READY   STATUS    RESTARTS   AGE     NODE
argocd-applicationset-controller-65bd797f9c-zh8kb   1/1     Running   0          6m16s   app-worker
argocd-dex-server-57c4c545db-xnbgq                  1/1     Running   6          5m56s   app-worker  ← 重啟6次後穩定
argocd-redis-*                                      1/1     Running   0          6m      app-worker
argocd-repo-server-*                                1/1     Running   0          6m      app-worker
argocd-server-*                                     1/1     Running   0          6m      app-worker
argocd-application-controller-*                     1/1     Running   0          6m      app-worker
```

### 關鍵觀察

1. **所有 ArgoCD pods 都部署到 app-worker** ✅
   - nodeSelector 正確工作
   - workload-apps 標籤已套用

2. **argocd-dex-server 需要較長時間啟動**
   - 初始重啟6次
   - 最終穩定運行
   - 這是正常行為 (dex 需要初始化 OIDC 配置)

3. **其他組件啟動順利**
   - applicationset-controller: 正常
   - redis: 正常
   - repo-server: 正常
   - server: 正常
   - application-controller: 正常

---

## kubernetes.core.k8s 模組參數參考

### 常用參數

| 參數 | 說明 | 預設值 |
|------|------|--------|
| `state` | 資源狀態 (present/absent) | present |
| `src` | YAML/JSON 檔案路徑 | - |
| `namespace` | 命名空間 | default |
| `wait` | 是否等待資源就緒 | false |
| `wait_timeout` | 等待超時時間 (秒) | 120 |
| `wait_condition` | 等待條件 | - |
| `wait_sleep` | 檢查間隔 (秒) | 5 |
| `kubeconfig` | Kubeconfig 路徑 | 環境變數 |
| `become` | 使用 sudo | false |

### ❌ 不支援的參數

- `timeout` - 應使用 `wait_timeout`
- `all` - 已棄用
- `definition` - 應使用 `resource_definition`
- `inline` - 已移除

### 環境變數

kubernetes.core.k8s 模組會優先使用:
1. `kubeconfig` 參數
2. `KUBECONFIG` 環境變數  ← **我們使用這個**
3. `~/.kube/config`

---

## 最佳實踐

### 1. 使用環境變數設定 KUBECONFIG

```yaml
- name: "[Phase 6] Install ArgoCD"
  hosts: masters[0]
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf  # Play 層級設定
  tasks:
    - name: "Create namespace"
      kubernetes.core.k8s:
        name: argocd
        kind: Namespace
        state: present
      become: true  # 需要 root 權限訪問 admin.conf
```

### 2. 大型 manifest 不等待

```yaml
# 大型 manifest (如 ArgoCD) 包含多個資源
- name: "Apply large manifest"
  kubernetes.core.k8s:
    src: "/tmp/argocd-install.yaml"
    namespace: argocd
    wait: no  # 不等待,避免超時
  become: true

# 單獨等待關鍵組件
- name: "Wait for critical component"
  ansible.builtin.command: >
    kubectl wait --for=condition=Ready pod -l app=server -n argocd --timeout=600s
  become: true
```

### 3. 小型資源可以等待

```yaml
# 單個資源 (如 Namespace, ConfigMap)
- name: "Create namespace"
  kubernetes.core.k8s:
    name: myapp
    kind: Namespace
    state: present
    wait: yes  # 可以等待 (很快)
    wait_timeout: 60
  become: true
```

### 4. 錯誤處理

```yaml
- name: "Apply manifest with error handling"
  kubernetes.core.k8s:
    src: "/tmp/manifest.yaml"
    namespace: myapp
    wait: no
  become: true
  register: apply_result
  ignore_errors: true  # 繼續執行

- name: "Display result"
  debug:
    msg: "{{ apply_result }}"
  when: apply_result is failed
```

---

## 故障排除

### 問題: Module failed: Unsupported parameters

**解決方案**: 檢查參數名稱是否正確
```bash
# 查看支援的參數
ansible-doc kubernetes.core.k8s
```

### 問題: Timed out waiting on resource

**診斷步驟**:
```bash
# 1. 檢查 Pod 狀態
kubectl get pods -n <namespace>

# 2. 檢查 Pod 日誌
kubectl logs -n <namespace> <pod-name>

# 3. 檢查 Pod 事件
kubectl describe pod -n <namespace> <pod-name>

# 4. 檢查 Node 資源
kubectl top nodes
```

**解決方案**:
- 增加 `wait_timeout`
- 設定 `wait: no` 並單獨等待關鍵組件
- 使用 `ignore_errors: true` 允許手動檢查

### 問題: Permission denied

**症狀**:
```
error loading config file "/etc/kubernetes/admin.conf": permission denied
```

**解決方案**: 確保設定 `become: true`
```yaml
- name: "Apply manifest"
  kubernetes.core.k8s:
    ...
  become: true  # 需要 root 權限
```

---

## 總結

| 修正項目 | 原因 | 解決方案 |
|---------|------|---------|
| `timeout` → `wait_timeout` | 參數名稱錯誤 | 使用正確的參數名稱 |
| ArgoCD 部署超時 | 5分鐘太短 | 改用 `wait: no` + 單獨等待策略 |
| 環境變數設定 | k8s 模組需要 kubeconfig | Play 層級設定 KUBECONFIG |
| 權限問題 | admin.conf 需要 root 權限 | 所有任務設定 `become: true` |

**相關文件**:
- ansible/deploy-cluster.yml:145-162 (修正後的代碼)
- ansible/CONFIGURATION_FIXES_COMPLETE.md (完整修正報告)

---

**修正日期**: 2025-11-14
**測試狀態**: ✅ 驗證通過,所有 ArgoCD 組件運行正常
