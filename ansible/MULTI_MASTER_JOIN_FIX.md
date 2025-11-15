# 多 Master 節點加入配置修正指南

**目的**: 讓 master-2 和 master-3 加入時使用 VIP 端點，實現真正的高可用

**更新日期**: 2025-11-13

---

## 📋 當前配置問題分析

### 問題 1: Join Command 端點不正確

**當前配置** (`roles/master/tasks/main.yml` line 279):
```yaml
echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN ..."
```

**生成的 join command**:
```bash
kubeadm join 192.168.0.11:6443 --token xyz... --discovery-token-ca-cert-hash sha256:abc...
```

**問題**:
- ❌ 後續 master (master-2, master-3) 加入時會直接連接到 `192.168.0.11`（master-1）
- ❌ 沒有利用 Kube-VIP 提供的 VIP (`192.168.0.10`)
- ❌ 不是真正的高可用配置（單點依賴 master-1）

### 問題 2: 為什麼需要使用 VIP？

| 場景 | 使用 master-1 IP | 使用 VIP |
|------|------------------|----------|
| master-1 正常 | ✅ 可以加入 | ✅ 可以加入 |
| master-1 故障 | ❌ 無法加入 | ✅ 可以加入（VIP 自動切換到 master-2） |
| 負載均衡 | ❌ 所有請求打到 master-1 | ✅ Kube-VIP 分散請求 |
| 真正的 HA | ❌ 單點依賴 | ✅ 任一 master 可服務 |

---

## ✅ 解決方案

### 方案 1: 分別生成 Worker 和 Master Join Command（推薦）

**修正位置**: `roles/master/tasks/main.yml` line 274-290

**修正前**:
```yaml
- name: Create kubeadm join command token
  ansible.builtin.shell: |
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: kubeadm_join_command
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Set join command facts on master
  ansible.builtin.set_fact:
    control_plane_join_command: "{{ kubeadm_join_command.stdout }} --control-plane{{ ' --certificate-key ' + kubeadm_certificate_key if kubeadm_certificate_key is defined else '' }}"
    worker_join_command: "{{ kubeadm_join_command.stdout }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - kubeadm_join_command is defined
```

**修正後**:
```yaml
- name: Create kubeadm join command token (創建 kubeadm 加入命令 token)
  ansible.builtin.shell: |
    # 使用 kubectl 創建 token 和 join 命令
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: kubeadm_join_command
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Create VIP-based join command for additional masters (為後續 master 創建基於 VIP 的加入命令)
  ansible.builtin.shell: |
    # 為後續 master 節點使用 VIP 端點
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_vip_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: kubeadm_join_command_vip
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Set join command facts on master (在 master 上設置加入命令事實)
  ansible.builtin.set_fact:
    # Worker 節點使用 master-1 IP（穩定且直接）
    worker_join_command: "{{ kubeadm_join_command.stdout }}"
    # 後續 Master 節點使用 VIP（實現 HA）
    control_plane_join_command: "{{ kubeadm_join_command_vip.stdout }} --control-plane{{ ' --certificate-key ' + kubeadm_certificate_key if kubeadm_certificate_key is defined else '' }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - kubeadm_join_command is defined
    - kubeadm_join_command_vip is defined
```

**關鍵變更**:
1. ✅ 新增 `kubeadm_join_command_vip` 任務，使用 `{{ control_plane_vip_endpoint }}`
2. ✅ Worker 節點使用 master-1 IP (`192.168.0.11:6443`)
3. ✅ Master 節點使用 VIP (`k8s-api.detectviz.internal:6443` → `192.168.0.10:6443`)

---

### 方案 2: 使用條件判斷動態選擇端點（替代方案）

**修正位置**: `roles/master/tasks/main.yml` line 274-290

```yaml
- name: Determine control plane endpoint for join command (決定 join command 使用的端點)
  ansible.builtin.set_fact:
    join_endpoint: >-
      {% if groups['masters'] | length > 1 %}
      {{ control_plane_vip_endpoint }}
      {% else %}
      {{ control_plane_endpoint }}
      {% endif %}
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Create kubeadm join command token (創建 kubeadm 加入命令 token)
  ansible.builtin.shell: |
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')

    # Worker join command - 使用 master-1 IP
    echo "WORKER_JOIN=kubeadm join {{ control_plane_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"

    # Master join command - 使用 VIP
    echo "MASTER_JOIN=kubeadm join {{ control_plane_vip_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: kubeadm_join_commands
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Parse join commands (解析加入命令)
  ansible.builtin.set_fact:
    worker_join_command: "{{ kubeadm_join_commands.stdout_lines | select('match', '^WORKER_JOIN=') | first | regex_replace('^WORKER_JOIN=', '') }}"
    control_plane_join_command: "{{ kubeadm_join_commands.stdout_lines | select('match', '^MASTER_JOIN=') | first | regex_replace('^MASTER_JOIN=', '') }} --control-plane{{ ' --certificate-key ' + kubeadm_certificate_key if kubeadm_certificate_key is defined else '' }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - kubeadm_join_commands is defined
```

---

## 📊 對比分析

### 方案 1 vs 方案 2

| 特性 | 方案 1（推薦） | 方案 2 |
|------|---------------|--------|
| 複雜度 | 🟢 簡單 | 🟡 中等 |
| 可讀性 | 🟢 清晰 | 🟡 需要理解 regex |
| 維護性 | 🟢 容易 | 🟡 稍複雜 |
| 靈活性 | 🟡 固定兩個 command | 🟢 可擴展 |
| 性能 | 🟢 兩次 shell 執行 | 🟢 一次 shell 執行 |

**建議**: 使用 **方案 1**，因為更簡單、更易理解

---

## 🎯 配置變數說明

### group_vars/all.yml 中的變數

```yaml
# 第一個 master 初始化時使用（kubeadm init）
control_plane_endpoint: "192.168.0.11:6443"

# Kube-VIP 綁定的虛擬 IP
cluster_vip: "192.168.0.10"

# 後續 master 加入時使用（kubeadm join）
control_plane_vip_endpoint: "k8s-api.detectviz.internal:6443"  # 解析到 192.168.0.10
```

### 變數用途對照表

| 變數 | 值 | 用於 | 說明 |
|------|-----|------|------|
| `control_plane_endpoint` | `192.168.0.11:6443` | kubeadm init<br>worker join | Master-1 實際 IP |
| `cluster_vip` | `192.168.0.10` | Kube-VIP 配置 | VIP 地址 |
| `control_plane_vip_endpoint` | `k8s-api.detectviz.internal:6443` | 後續 master join | VIP 端點（DNS 名稱） |

---

## 🔍 驗證步驟

### 部署後驗證 Join Commands

```bash
# SSH 到 master-1
ssh ubuntu@192.168.0.11

# 檢查生成的 worker join command
echo "Worker Join Command:"
sudo kubeadm token create --print-join-command

# 檢查證書 key（用於 master 加入）
echo "Certificate Key:"
sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1
```

### 手動生成正確的 Master Join Command

```bash
# 在 master-1 上執行
TOKEN=$(sudo kubeadm token create --ttl=24h)
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //')

# 生成 master-2/master-3 加入命令（使用 VIP）
echo "kubeadm join k8s-api.detectviz.internal:6443 \
  --token $TOKEN \
  --discovery-token-ca-cert-hash sha256:$CA_HASH \
  --control-plane \
  --certificate-key $CERT_KEY"
```

### 在 master-2 上執行加入

```bash
# 確認 VIP 可達
ping -c 3 192.168.0.10

# 確認 DNS 解析
nslookup k8s-api.detectviz.internal

# 確認 API Server 可訪問
curl -k https://k8s-api.detectviz.internal:6443/healthz
# 預期輸出：ok

# 執行加入命令
sudo kubeadm join k8s-api.detectviz.internal:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH> \
  --control-plane \
  --certificate-key <CERT_KEY>
```

---

## 📝 完整修正步驟

### Step 1: 更新 Ansible 任務

**文件**: `roles/master/tasks/main.yml`

在 line 274 位置，替換整個 "Create kubeadm join command" 和 "Set join command facts" 區塊：

```yaml
# ============================================
# 生成 Join Commands（分別為 Worker 和 Master）
# ============================================

- name: Create kubeadm join command token for workers (為 worker 創建 join 命令)
  ansible.builtin.shell: |
    # Worker 使用 master-1 IP（穩定直接）
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: worker_join_cmd
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Create kubeadm join command token for masters (為後續 master 創建 join 命令)
  ansible.builtin.shell: |
    # 後續 Master 使用 VIP（實現 HA）
    TOKEN=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf create token --ttl=24h)
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    echo "kubeadm join {{ control_plane_vip_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash sha256:$CA_CERT_HASH"
  register: master_join_cmd
  changed_when: false
  when: "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"

- name: Set join command facts on master (設置 join 命令事實)
  ansible.builtin.set_fact:
    # Worker 使用 master-1 IP
    worker_join_command: "{{ worker_join_cmd.stdout }}"
    # Master 使用 VIP + control-plane flag + certificate key
    control_plane_join_command: "{{ master_join_cmd.stdout }} --control-plane{{ ' --certificate-key ' + kubeadm_certificate_key if kubeadm_certificate_key is defined else '' }}"
  when:
    - "'masters' in group_names and groups['masters'].index(inventory_hostname) == 0"
    - worker_join_cmd is defined
    - master_join_cmd is defined
```

### Step 2: 測試配置

```bash
# 重新部署集群
cd /Users/zoe/Documents/github/detectviz-gitops/ansible
ansible-playbook -i inventory.ini deploy-cluster.yml

# 檢查生成的 join commands
ssh ubuntu@192.168.0.11 'grep -r "kubeadm join" /root/'
```

---

## ✅ 預期結果

### 修正前的 Join Commands

```bash
# Worker join (❌ 正確)
kubeadm join 192.168.0.11:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy

# Master join (❌ 錯誤 - 使用 master-1 IP)
kubeadm join 192.168.0.11:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy --control-plane --certificate-key zzz
```

### 修正後的 Join Commands

```bash
# Worker join (✅ 使用 master-1 IP - 穩定直接)
kubeadm join 192.168.0.11:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy

# Master join (✅ 使用 VIP - 實現真正的 HA)
kubeadm join k8s-api.detectviz.internal:6443 --token xxx --discovery-token-ca-cert-hash sha256:yyy --control-plane --certificate-key zzz
```

### 實際效果

| 節點類型 | 連接端點 | 好處 |
|---------|---------|------|
| Worker | 192.168.0.11:6443 | 直接連接，穩定可靠 |
| Master-2 | 192.168.0.10:6443 (VIP) | master-1 故障時仍可加入 |
| Master-3 | 192.168.0.10:6443 (VIP) | 實現真正的多 master HA |

---

## 🎉 總結

### 為什麼需要這個修正？

1. **當前配置問題**:
   - 所有節點（包括後續 master）都使用 master-1 IP
   - 形成單點依賴，不是真正的高可用

2. **修正後的優勢**:
   - ✅ Worker 節點使用穩定的 master-1 IP
   - ✅ 後續 Master 使用 VIP，實現真正的 HA
   - ✅ Master-1 故障時，master-2/3 仍可通過 VIP 加入
   - ✅ 負載均衡到所有健康的 master 節點

### 何時應用此修正？

| 場景 | 是否需要 |
|------|---------|
| 當前部署（1 master + 1 worker） | ⚠️ 可選（未來擴展時需要） |
| 計劃部署 3 master HA 集群 | ✅ **必須**（否則不是真 HA） |
| 生產環境 | ✅ **強烈建議** |

### 下一步行動

1. ✅ 當前可以不修正，先完成單 master 部署驗證
2. 🔄 計劃添加 master-2, master-3 之前，**必須**先應用此修正
3. 📝 更新 inventory.ini 添加 master-2, master-3 配置
4. 🚀 重新執行 playbook 部署完整的 HA 集群
