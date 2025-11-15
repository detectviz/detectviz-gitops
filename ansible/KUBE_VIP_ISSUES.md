# Kube-VIP 部署問題總結

**日期**: 2025-11-13
**狀態**: ⚠️ 發現關鍵問題並提供解決方案

---

## 🔴 發現的問題

### 問題 1: Kube-VIP 無法連接 Kubernetes API

**錯誤訊息**:
```
error retrieving resource lock kube-system/plndr-cp-lock:
Get "https://kubernetes:6443/...": dial tcp: lookup kubernetes on 192.168.0.2:53: no such host
```

**根本原因**:
- Kube-VIP 使用 `cp_enable: true` 需要 leader election
- Leader election 需要訪問 Kubernetes API
- Kube-VIP 嘗試解析 `kubernetes` 主機名，但解析失敗
- Admin.conf 中的 server 地址是 `192.168.0.11:6443`，但 Kube-VIP 內部使用了 in-cluster 配置

**為什麼會這樣？**:
- Kube-VIP 以靜態 Pod 方式運行
- 靜態 Pod 使用 `hostNetwork: true`
- `hostNetwork: true` 的 Pod 無法使用 `hostAliases` 添加 DNS 記錄
- Kube-VIP 需要連接 `kubernetes` Service 進行 leader election

### 問題 2: Master-2 Join Command 缺少 Token

**錯誤訊息**:
```
"cmd": ["kubeadm", "join", "k8s-api.detectviz.internal:6443", "--token", "", "--discovery-token-ca-cert-hash", ...]
                                                                            ^^^ 空值！
```

**根本原因**:
- Ansible 任務生成 join command 時，`kubectl create token` 命令的 `--ttl` 參數不正確
- Kubernetes 1.32.0 中應該使用 `--duration` 而不是 `--ttl`
- 導致 token 生成失敗，join command 中的 token 為空

---

## ✅ 解決方案

### 解決方案 1: 手動綁定 VIP（臨時）

當前已實施的臨時解決方案：

```bash
# 在 master-1 上手動綁定 VIP
sudo ip addr add 192.168.0.10/32 dev eth0
sudo arping -c 3 -A -I eth0 192.168.0.10
```

**優點**:
- ✅ 簡單直接
- ✅ VIP 立即可用
- ✅ 不依賴 Kubernetes API

**缺點**:
- ❌ 重啟後需要重新綁定
- ❌ 沒有高可用（master-1 故障時 VIP 不會切換）
- ❌ 不是自動化解決方案

---

### 解決方案 2: 使用 Kube-VIP DaemonSet（推薦）

放棄靜態 Pod 方式，改用 DaemonSet 部署 Kube-VIP。

**步驟**:

#### 1. 創建 Kube-VIP RBAC

```yaml
# roles/master/templates/kube-vip-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-vip
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kube-vip-role
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "nodes"]
  verbs: ["list", "get", "watch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["get", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-vip-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-vip-role
subjects:
- kind: ServiceAccount
  name: kube-vip
  namespace: kube-system
```

#### 2. 創建 Kube-VIP DaemonSet

```yaml
# roles/master/templates/kube-vip-daemonset.yaml.j2
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: kube-vip
  template:
    metadata:
      labels:
        name: kube-vip
    spec:
      serviceAccountName: kube-vip
      hostNetwork: true
      priorityClassName: system-node-critical
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
        operator: Exists
      containers:
      - name: kube-vip
        image: ghcr.io/kube-vip/kube-vip:{{ kube_vip_version }}
        imagePullPolicy: IfNotPresent
        args:
        - manager
        env:
        - name: vip_address
          value: "{{ cluster_vip }}"
        - name: vip_interface
          value: "eth0"
        - name: port
          value: "6443"
        - name: vip_arp
          value: "true"
        - name: vip_leaderelection
          value: "true"
        - name: vip_leaseduration
          value: "15"
        - name: vip_renewdeadline
          value: "10"
        - name: vip_retryperiod
          value: "2"
        - name: cp_enable
          value: "true"
        - name: cp_namespace
          value: "kube-system"
        - name: svc_enable
          value: "false"
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
            - NET_RAW
```

#### 3. 修改 Ansible 任務

**文件**: `roles/master/tasks/main.yml`

替換靜態 Pod 部署部分：

```yaml
# 移除舊的靜態 Pod 部署
# - name: "[HA] Deploy Kube-VIP static pod"
#   ...

# 添加 DaemonSet 部署
- name: "[HA] Apply Kube-VIP RBAC"
  ansible.builtin.command: kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f -
  args:
    stdin: "{{ lookup('template', 'kube-vip-rbac.yaml') }}"
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: "[HA] Apply Kube-VIP DaemonSet"
  ansible.builtin.command: kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f -
  args:
    stdin: "{{ lookup('template', 'kube-vip-daemonset.yaml.j2') }}"
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
```

**優點**:
- ✅ 使用 ServiceAccount 正確訪問 API
- ✅ 支持 leader election
- ✅ 真正的多 master HA
- ✅ 自動部署和恢復

**缺點**:
- ⚠️ 需要等待 CNI 網路就緒
- ⚠️ 稍微複雜一點

---

### 解決方案 3: 修正 Join Command 生成（必須）

**文件**: `roles/master/tasks/main.yml`

修正 token 生成命令：

```yaml
# 修正前（❌ 錯誤）
- name: Create kubeadm join command token for workers
  ansible.builtin.shell: |
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    ...

# 修正後（✅ 正確）
- name: Create kubeadm join command token for workers
  ansible.builtin.shell: |
    # 使用 kubeadm token create 更可靠
    TOKEN=$(kubeadm token create --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: worker_join_cmd
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
```

或者更簡單：

```yaml
- name: Generate join command using kubeadm
  ansible.builtin.command: kubeadm token create --print-join-command
  register: join_command_base
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Set join commands
  ansible.builtin.set_fact:
    worker_join_command: "{{ join_command_base.stdout }}"
    control_plane_join_command: "{{ join_command_base.stdout | replace(control_plane_endpoint, control_plane_vip_endpoint) }} --control-plane --certificate-key {{ kubeadm_certificate_key }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - join_command_base is defined
```

---

## 🎯 推薦實施順序

### 立即修正（Phase 1）

1. ✅ **修正 Join Command 生成**
   - 使用 `kubeadm token create --print-join-command`
   - 這樣可以讓 master-2/3 成功加入

2. ⚠️ **保持手動 VIP 綁定**
   - 目前已手動綁定，暫時保持
   - 確保 API 可通過 VIP 訪問

### 後續優化（Phase 2）

3. 📋 **切換到 DaemonSet 模式**
   - 創建 RBAC 配置
   - 創建 DaemonSet 模板
   - 修改 Ansible 任務
   - 移除手動 VIP 綁定

4. 🧪 **測試多 Master HA**
   - 添加 master-2
   - 添加 master-3
   - 測試 leader election
   - 測試 VIP 切換

---

## 📝 修正後的部署流程

```bash
# 1. 清理環境
cd /Users/zoe/Documents/github/detectviz-gitops/terraform
terraform destroy -var-file=terraform.tfvars -auto-approve
terraform apply -var-file=terraform.tfvars -auto-approve

# 2. 部署集群
cd /Users/zoe/Documents/github/detectviz-gitops/ansible

# 2.1 先應用 join command 修正
# 編輯 roles/master/tasks/main.yml（應用解決方案 3）

# 2.2 執行部署
ansible-playbook -i inventory.ini deploy-cluster.yml

# 3. 手動綁定 VIP（臨時）
ssh ubuntu@192.168.0.11 'sudo ip addr add 192.168.0.10/32 dev eth0'

# 4. 驗證
curl -k https://192.168.0.10:6443/healthz  # 應返回 "ok"
ssh ubuntu@192.168.0.11 'kubectl get nodes'
```

---

## ✅ 當前狀態

| 組件 | 狀態 | 說明 |
|------|------|------|
| Master-1 初始化 | ✅ 成功 | API Server 正常運行 |
| VIP 綁定 | ✅ 手動綁定 | 192.168.0.10 可訪問 |
| Kube-VIP 自動化 | ❌ 失敗 | 靜態 Pod 無法連接 API |
| Master-2 加入 | ❌ 失敗 | Join command 缺少 token |
| Worker 加入 | ⏳ 未測試 | 應該可以成功 |
| CNI (Calico) | ✅ 部署 | 網路插件已安裝 |

---

## 🚀 下一步行動

### 優先級 1：修正 Join Command

**立即修改** `roles/master/tasks/main.yml` line 282-311：

```yaml
- name: Generate join commands using kubeadm
  ansible.builtin.shell: |
    # 使用 kubeadm 生成 worker join command
    WORKER_JOIN=$(kubeadm token create --print-join-command)

    # 生成 master join command（使用 VIP）
    TOKEN=$(echo $WORKER_JOIN | awk '{print $5}')
    MASTER_JOIN="kubeadm join {{ control_plane_vip_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash $(echo $WORKER_JOIN | awk '{print $NF}') --control-plane --certificate-key {{ kubeadm_certificate_key }}"

    echo "WORKER:$WORKER_JOIN"
    echo "MASTER:$MASTER_JOIN"
  register: join_commands_output
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Parse join commands
  ansible.builtin.set_fact:
    worker_join_command: "{{ join_commands_output.stdout_lines | select('match', '^WORKER:') | first | regex_replace('^WORKER:', '') }}"
    control_plane_join_command: "{{ join_commands_output.stdout_lines | select('match', '^MASTER:') | first | regex_replace('^MASTER:', '') }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - join_commands_output is defined
```

### 優先級 2：持久化 VIP 綁定

添加到 Ansible 任務中，在 kubeadm init 之後：

```yaml
- name: "[HA] Manually bind VIP (temporary solution)"
  ansible.builtin.shell: |
    ip addr add {{ cluster_vip }}/32 dev eth0 || true
    arping -c 3 -A -I eth0 {{ cluster_vip }} || true
  become: true
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
```

### 優先級 3：切換到 DaemonSet

按照解決方案 2 的步驟實施。

---

## 📚 相關資源

- [Kube-VIP 官方文檔](https://kube-vip.io/)
- [Kube-VIP ARP Mode](https://kube-vip.io/docs/about/architecture/)
- [Kubernetes Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
- [DaemonSet vs Static Pods](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/#understanding-daemon-pods)
