# Ansible 配置修正摘要

## 問題分析

### 1. 主要問題
在 `ansible/deploy-cluster.yml` 部署期間,Phase 5 (節點標籤) 失敗,錯誤訊息:
```
ssh: connect to host 192.168.0.11 port 22: Network is unreachable
```

### 2. 根本原因

經過診斷發現兩個主要問題:

#### 問題 A: kubectl 無法連接到 API Server
- Phase 5 和 Phase 7 中的 `kubectl` 命令沒有指定 `--kubeconfig` 參數
- 導致 kubectl 嘗試使用預設的 localhost:8080,而非正確的 kubeconfig 路徑
- 錯誤訊息: `The connection to the server localhost:8080 was refused`

#### 問題 B: Ubuntu 使用者缺少 kubeconfig
- master role 只為 root 使用者設定了 `~/.kube/config`
- 但 ansible 使用 ubuntu 使用者執行命令
- 導致 ubuntu 使用者執行 kubectl 時無法找到有效的配置

#### 問題 C: Worker 節點未成功加入
- app-worker 在 Phase 4 執行時,join 命令檔案不存在
- kubelet 服務未啟動

## 修正內容

### 1. deploy-cluster.yml 修正

#### Phase 5 - 節點標籤 (行 45-72)
**修正前:**
```yaml
- name: "Label nodes for specific workloads (為節點添加標籤)"
  ansible.builtin.command: >
    kubectl label node {{ item.name }} {{ item.label }} --overwrite
  become: false
```

**修正後:**
```yaml
- name: "Label nodes for specific workloads (為節點添加標籤)"
  ansible.builtin.command: >
    kubectl --kubeconfig=/etc/kubernetes/admin.conf label node {{ item.name }} {{ item.label }} --overwrite
  become: true
```

**變更:**
- 新增 `--kubeconfig=/etc/kubernetes/admin.conf` 參數
- 將 `become: false` 改為 `become: true` (在 task 層級)

#### Phase 7 - 最終驗證 (行 122-134)
**修正前:**
```yaml
- name: "[Phase 7] Validate Kubernetes Cluster Deployment (最終驗證)"
  hosts: masters[0]
  become: false
  tasks:
    - name: "Wait for all nodes to be in Ready state"
      ansible.builtin.command: kubectl wait --for=condition=Ready node --all --timeout=5m

    - name: "Get final cluster node status"
      ansible.builtin.command: kubectl get nodes -o wide
```

**修正後:**
```yaml
- name: "[Phase 7] Validate Kubernetes Cluster Deployment (最終驗證)"
  hosts: masters[0]
  become: true
  tasks:
    - name: "Wait for all nodes to be in Ready state"
      ansible.builtin.command: kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=Ready node --all --timeout=5m

    - name: "Get final cluster node status"
      ansible.builtin.command: kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
```

**變更:**
- 將 play 層級的 `become: false` 改為 `become: true`
- 所有 kubectl 命令新增 `--kubeconfig=/etc/kubernetes/admin.conf` 參數

### 2. master role 修正

#### 檔案: `ansible/roles/master/tasks/main.yml` (行 154-178)

**新增任務:**
```yaml
- name: Ensure .kube directory exists for ansible user (確保 ansible 用戶的 .kube 目錄存在)
  ansible.builtin.file:
    path: "/home/{{ ansible_user }}/.kube"
    state: directory
    mode: "0755"
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Copy admin kubeconfig to ansible user (複製 admin kubeconfig 到 ansible 用戶)
  ansible.builtin.copy:
    src: /etc/kubernetes/admin.conf
    dest: "/home/{{ ansible_user }}/.kube/config"
    remote_src: yes
    mode: "0600"
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
```

**說明:**
- 在複製 kubeconfig 給 root 使用者之後
- 同時為 ansible_user (ubuntu) 建立 `~/.kube` 目錄
- 複製 admin.conf 到 ubuntu 使用者的家目錄
- 設定正確的檔案權限和擁有者

### 3. 手動修正 - Worker 加入叢集

由於 app-worker 未自動加入叢集,已手動執行:
```bash
# 1. 生成新的 join token
ssh ubuntu@192.168.0.11 "sudo kubeadm token create --print-join-command"

# 2. 在 app-worker 上執行 join 命令
ssh ubuntu@192.168.0.14 "sudo kubeadm join 192.168.0.11:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"

# 3. 驗證節點加入
ssh ubuntu@192.168.0.11 "kubectl get nodes"
```

### 4. 臨時修正 - 為現有叢集設定 kubeconfig

在 master-1 上為 ubuntu 使用者設定 kubeconfig:
```bash
ssh ubuntu@192.168.0.11 "mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown ubuntu:ubuntu ~/.kube/config"
```

## 叢集最終狀態

### 節點狀態
```
NAME         STATUS   ROLES                               AGE    VERSION
app-worker   Ready    workload-apps                       2m     v1.32.0
master-1     Ready    control-plane,workload-monitoring   20m    v1.32.0
master-2     Ready    control-plane,workload-mimir        19m    v1.32.0
master-3     Ready    control-plane,workload-loki         18m    v1.32.0
```

### 節點標籤
所有節點標籤已正確套用:
- **master-1**: `node-role.kubernetes.io/workload-monitoring=true`
- **master-2**: `node-role.kubernetes.io/workload-mimir=true`
- **master-3**: `node-role.kubernetes.io/workload-loki=true`
- **app-worker**: `node-role.kubernetes.io/workload-apps=true`

### 核心組件狀態
所有 Kubernetes 核心組件運行正常:
- ✅ etcd: 3 個實例 (HA 配置)
- ✅ kube-apiserver: 3 個實例
- ✅ kube-controller-manager: 3 個實例
- ✅ kube-scheduler: 3 個實例
- ✅ CoreDNS: 2 個實例
- ✅ Calico CNI: 4 個節點 (全部就緒)
- ✅ kube-proxy: 運行在所有節點

## 建議與最佳實踐

### 1. 統一使用 --kubeconfig 參數
所有 kubectl 命令應明確指定 kubeconfig 路徑:
```yaml
ansible.builtin.command: kubectl --kubeconfig=/etc/kubernetes/admin.conf <command>
```

### 2. 或使用環境變數
也可以在 play 或 task 層級設定環境變數:
```yaml
environment:
  KUBECONFIG: /etc/kubernetes/admin.conf
```

### 3. 為所有 master 節點設定使用者 kubeconfig
考慮為所有 master 節點 (不只是第一個) 設定 ansible_user 的 kubeconfig:
```yaml
when: "'masters' in group_names"  # 移除 index 條件
```

### 4. Worker 加入流程改進
確保 worker join 命令在正確的時機生成和傳遞:
- 在 master-1 完成初始化後立即生成
- 使用 ansible facts 或 set_fact 傳遞到 worker 節點
- 或使用 delegate_to 直接從 master-1 獲取

## 測試建議

在下次部署前,建議測試:
1. 完整銷毀現有叢集
2. 使用修正後的 playbook 重新部署
3. 驗證所有 phase 都能順利完成
4. 確認所有節點和標籤都正確設定

## 相關檔案

- `/Users/zoe/Documents/github/detectviz-gitops/ansible/deploy-cluster.yml`
- `/Users/zoe/Documents/github/detectviz-gitops/ansible/roles/master/tasks/main.yml`

---
建立時間: 2025-11-14
修正者: Claude Code
