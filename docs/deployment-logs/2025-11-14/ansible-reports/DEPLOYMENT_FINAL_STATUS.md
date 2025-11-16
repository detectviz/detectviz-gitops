# Kubernetes 集群部署 - 最終狀態

**日期**: 2025-11-13
**狀態**: 🔄 進行中 - 正在完成 Worker 節點配置
**版本**: Kubernetes 1.32.0

---

## 📊 部署進度

### ✅ Phase 1: 節點準備 (已完成)

**狀態**: ✅ 完成
**時間**: ~5 分鐘

- ✅ 安裝 containerd (2.1.5)
- ✅ 安裝 Kubernetes 組件 (kubelet, kubeadm, kubectl 1.32.0)
- ✅ 配置 containerd CRI
- ✅ 配置系統參數

### ✅ Phase 2: 網路配置 (已完成)

**狀態**: ✅ 完成
**時間**: ~1 分鐘

- ✅ 雙網路接口配置 (eth0 + eth1)
- ✅ Netplan 配置應用

### ✅ Phase 3: Master 節點部署 (已完成)

**狀態**: ✅ 完成
**時間**: ~8 分鐘

#### Master-1 (192.168.0.11)
- ✅ Kubeadm init 成功
- ✅ VIP 192.168.0.10 綁定到 eth0
- ✅ Calico CNI 3.27.3 部署
- ✅ API Server 健康檢查通過
- ✅ 生成 join commands

**部署輸出**:
```
✅ VIP 192.168.0.10 已成功綁定到 eth0 網卡
DNS resolution successful
Containerd sandbox image: registry.k8s.io/pause:3.10
```

#### Master-2 (192.168.0.12)
- ✅ 成功加入集群
- ✅ 使用 VIP endpoint (k8s-api.detectviz.internal:6443)
- ✅ Certificate SANs 驗證通過

#### Master-3 (192.168.0.13)
- ✅ 成功加入集群
- ✅ 使用 VIP endpoint (k8s-api.detectviz.internal:6443)
- ✅ Certificate SANs 驗證通過

### 🔄 Phase 4: Worker 節點部署 (進行中)

**狀態**: 🔄 重新部署中
**Worker**: app-worker (192.168.0.14)

**已完成**:
- ✅ LVM 工具安裝
- ✅ 磁碟配置檢查
  - sda: 100GB (系統磁碟)
  - sdb: 250GB (資料磁碟，準備用於 TopoLVM)

**待完成**:
- 🔄 LVM Volume Group 配置
- ⏳ Worker 加入集群
- ⏳ 節點標籤和 taint 配置

---

## 🔧 應用的修正

### 修正 1: EFI Disk 配置 ✅

**文件**: `terraform/main.tf`
**問題**: VM 啟動失敗 - `storage 'local' does not support content-type 'images'`

**修正內容**:
```hcl
efi_disk {
  datastore_id      = var.proxmox_storage  # nvme-vm
  file_format       = "raw"
  type              = "4m"
  pre_enrolled_keys = false
}
```

**位置**:
- Master 節點: Line 73-80
- Worker 節點: Line 193-200

**文檔**: `EFI_DISK_FIX.md`

---

### 修正 2: Certificate SANs 配置 ✅

**文件**: `ansible/roles/master/templates/kubeadm-config.yaml.j2`
**問題**: Master-2/3 無法加入 - certificate 不包含 VIP

**修正內容**:
```yaml
apiServer:
  certSANs:
    - "{{ cluster_vip }}"                    # 192.168.0.10
    - "k8s-api.detectviz.internal"           # VIP 域名
    - "k8s-api"
    - "192.168.0.11"                         # Master-1 IP
    - "192.168.0.12"                         # Master-2 IP
    - "192.168.0.13"                         # Master-3 IP
    - "master-1"
    - "master-2"
    - "master-3"
    - "localhost"
    - "127.0.0.1"
```

**位置**: Line 40-63
**文檔**: `CERTIFICATE_SANS_FIX.md`

---

### 修正 3: configure_lvm 變數 ✅

**文件**: `ansible/group_vars/all.yml`
**問題**: Worker role 失敗 - `'configure_lvm' is undefined`

**修正內容**:
```yaml
# 儲存配置變數 (Storage Configuration)
configure_lvm: true
```

**位置**: Line 48-51

---

### 修正 4: lvm_volume_groups 變數 ✅

**文件**: `ansible/group_vars/all.yml`
**問題**: Worker role 失敗 - `'lvm_volume_groups' is undefined`

**修正內容**:
```yaml
lvm_volume_groups:
  - name: topolvm-vg
    devices:
      - /dev/sdb
    pvs:
      - /dev/sdb
```

**位置**: Line 53-59

---

### 修正 5: VIP 自動綁定 ✅

**文件**: `ansible/roles/master/tasks/main.yml`
**已在前次部署中應用**

**修正內容**:
```yaml
- name: "[HA] Manually bind VIP if not bound"
  ansible.builtin.shell: |
    ip addr add {{ cluster_vip }}/32 dev eth0 || true
    arping -c 3 -A -I eth0 {{ cluster_vip }} || true
```

**位置**: Line 203-229

---

### 修正 6: Join Command 生成邏輯 ✅

**文件**: `ansible/roles/master/tasks/main.yml`
**已在前次部署中應用**

**修正內容**:
```yaml
- name: Generate join commands using kubeadm
  ansible.builtin.shell: |
    WORKER_JOIN=$(kubeadm token create --print-join-command)
    TOKEN=$(echo $WORKER_JOIN | awk '{print $5}')
    CA_HASH=$(echo $WORKER_JOIN | awk '{print $NF}')
    MASTER_JOIN="kubeadm join {{ control_plane_vip_endpoint }} --token $TOKEN --discovery-token-ca-cert-hash $CA_HASH --control-plane --certificate-key {{ kubeadm_certificate_key }}"
    echo "WORKER:$WORKER_JOIN"
    echo "MASTER:$MASTER_JOIN"
```

**位置**: Line 283-310

---

### 修正 7: 移除 skip-phases kube-proxy ✅

**文件**: `ansible/roles/master/tasks/main.yml`
**已在前次部署中應用**

**修正前**:
```yaml
kubeadm init --skip-phases=addon/kube-proxy
```

**修正後**:
```yaml
kubeadm init  # 不跳過 kube-proxy
```

**位置**: Line 130-137

---

### 修正 8: 新增 Kubernetes 核心參數配置 ✅

**文件**: `ansible/roles/common/tasks/main.yml`
**問題**: Worker 節點加入失敗 - IP forwarding 未啟用

**修正內容**:
```yaml
# Kubernetes 系統參數配置
- name: "Configure kernel parameters for Kubernetes"
  become: true
  ansible.builtin.sysctl:
    name: "{{ item.name }}"
    value: "{{ item.value }}"
    state: present
    sysctl_set: yes
    reload: yes
  loop:
    - { name: "net.ipv4.ip_forward", value: "1" }
    - { name: "net.bridge.bridge-nf-call-iptables", value: "1" }
    - { name: "net.bridge.bridge-nf-call-ip6tables", value: "1" }

- name: "Load br_netfilter kernel module"
  become: true
  ansible.builtin.modprobe:
    name: br_netfilter
    state: present

- name: "Ensure br_netfilter loads on boot"
  become: true
  ansible.builtin.lineinfile:
    path: /etc/modules-load.d/k8s.conf
    line: br_netfilter
    create: yes
    mode: "0644"
```

**位置**: Line 118-147

**說明**:
- `net.ipv4.ip_forward=1`: 啟用 IP 轉發，Kubernetes 網路必需
- `net.bridge.bridge-nf-call-iptables=1`: 允許 iptables 處理橋接流量
- `net.bridge.bridge-nf-call-ip6tables=1`: 允許 ip6tables 處理 IPv6 橋接流量
- `br_netfilter`: 載入網橋過濾內核模組，持久化到重啟後

---

## 🎯 集群配置摘要

### 網路配置

| 項目 | 值 |
|------|-----|
| Control Plane Endpoint (Init) | 192.168.0.11:6443 |
| Control Plane VIP Endpoint (Join) | k8s-api.detectviz.internal:6443 |
| VIP Address | 192.168.0.10 |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

### 節點信息

| 節點 | IP | 角色 | CPU | Memory | 磁碟 |
|------|-----|------|-----|--------|------|
| master-1 | 192.168.0.11 | Control Plane | 4 cores | 8GB | 100GB |
| master-2 | 192.168.0.12 | Control Plane | 3 cores | 8GB | 100GB |
| master-3 | 192.168.0.13 | Control Plane | 3 cores | 8GB | 100GB |
| app-worker | 192.168.0.14 | Worker | 12 cores | 24GB | 100GB + 250GB |

### 組件版本

| 組件 | 版本 |
|------|------|
| Kubernetes | 1.32.0 |
| Containerd | 2.1.5 |
| Calico CNI | 3.27.3 |
| Kube-VIP | 0.7.1 |
| Ubuntu | 22.04.5 LTS |

---

## ✅ 驗證方法

### 檢查 Master 節點狀態

```bash
ssh ubuntu@192.168.0.11 'sudo kubectl get nodes -o wide'
```

**預期輸出**:
```
NAME       STATUS   ROLES           AGE   VERSION
master-1   Ready    control-plane   15m   v1.32.0
master-2   Ready    control-plane   10m   v1.32.0
master-3   Ready    control-plane   10m   v1.32.0
app-worker Ready    <none>          5m    v1.32.0
```

### 檢查 VIP 綁定

```bash
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'
```

**預期輸出**:
```
inet 192.168.0.10/32 scope global eth0
```

### 檢查系統 Pods

```bash
ssh ubuntu@192.168.0.11 'sudo kubectl get pods -n kube-system'
```

**預期輸出**:
```
NAME                                   READY   STATUS
calico-kube-controllers-xxx            1/1     Running
calico-node-xxx                        1/1     Running (x3+)
coredns-xxx                            1/1     Running (x2)
etcd-master-1                          1/1     Running
kube-apiserver-master-1                1/1     Running (x3)
kube-controller-manager-master-1       1/1     Running (x3)
kube-proxy-xxx                         1/1     Running (x4)
kube-scheduler-master-1                1/1     Running (x3)
kube-vip-master-1                      1/1     Running (or CrashLoop - VIP已手動綁定)
```

### 檢查 API Server 可訪問性

```bash
# 通過 VIP
curl -k https://192.168.0.10:6443/healthz

# 通過 Master-1
curl -k https://192.168.0.11:6443/healthz
```

**預期輸出**: `ok`

### 檢查證書 SANs

```bash
ssh ubuntu@192.168.0.11 'sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -A 15 "Subject Alternative Name"'
```

**預期輸出** (應包含所有添加的 SANs):
```
X509v3 Subject Alternative Name:
    DNS:k8s-api.detectviz.internal
    DNS:k8s-api
    DNS:kubernetes
    DNS:kubernetes.default
    DNS:kubernetes.default.svc
    DNS:kubernetes.default.svc.cluster.local
    DNS:localhost
    DNS:master-1
    DNS:master-2
    DNS:master-3
    IP Address:10.96.0.1
    IP Address:127.0.0.1
    IP Address:192.168.0.10
    IP Address:192.168.0.11
    IP Address:192.168.0.12
    IP Address:192.168.0.13
```

---

## 📈 部署時間線

```
[09:18] Terraform Apply 開始
  └─ VM 創建和啟動

[09:24] Terraform Apply 完成 ✅
  └─ 所有 4 個 VM 成功創建

[09:26] Ansible Deployment 開始
  └─ Phase 1: 節點準備
  └─ Phase 2: 網路配置
  └─ Phase 3: Master 節點部署

[09:28] Master-1 初始化完成 ✅
  └─ VIP 192.168.0.10 綁定成功
  └─ Calico CNI 部署

[09:28] Master-2 加入完成 ✅

[09:28] Master-3 加入完成 ✅

[09:28] Worker 部署遇到錯誤 ❌
  └─ Error: 'configure_lvm' undefined

[09:29] 添加 configure_lvm 變數 ✅
  └─ 重新部署

[09:31] Worker 部署再次遇到錯誤 ❌
  └─ Error: 'lvm_volume_groups' undefined

[09:31] 添加 lvm_volume_groups 配置 ✅
  └─ 重新部署 (進行中)

[09:32] Worker 部署進行中 🔄
```

---

## 🎯 待完成任務

### Worker 節點配置 (進行中)

1. 🔄 配置 LVM Volume Group (topolvm-vg)
2. ⏳ Worker 加入集群
3. ⏳ 節點標籤配置
4. ⏳ 驗證 worker 節點狀態

### 後續優化任務

1. ⏳ 切換 Kube-VIP 到 DaemonSet 模式
2. ⏳ 持久化 VIP 綁定配置
3. ⏳ 部署 TopoLVM CSI Driver
4. ⏳ 部署監控系統 (Prometheus + Grafana)
5. ⏳ 部署日誌系統 (Loki)

---

## 📚 相關文檔

### 修正文檔
- `EFI_DISK_FIX.md` - EFI Disk 配置修正
- `CERTIFICATE_SANS_FIX.md` - Certificate SANs 配置
- `FIXES_APPLIED.md` - 所有已應用修正的總結
- `KUBE_VIP_ISSUES.md` - Kube-VIP 問題分析
- `MULTI_MASTER_JOIN_FIX.md` - 多 Master 加入配置

### 參考文檔
- `QUICK_REFERENCE.md` - 快速參考指南
- `CONFIG_STATUS_CHECK.md` - 配置完整性檢查
- `CONFIG_CHANGES_SUMMARY.md` - 配置修正總結
- `DEPLOYMENT_STATUS.md` - 部署狀態

---

## 🎉 部署總結

### 已解決的問題

1. ✅ **EFI Disk 配置** - 修復 VM 啟動失敗
2. ✅ **Certificate SANs** - Master-2/3 成功加入
3. ✅ **VIP 自動綁定** - 手動綁定機制正常工作
4. ✅ **Join Command 生成** - Token 正確生成
5. ✅ **kube-proxy 部署** - Service 網路正常
6. ✅ **configure_lvm 變數** - Worker role 配置完整
7. ✅ **lvm_volume_groups 配置** - LVM 配置定義
8. ✅ **Kubernetes 核心參數** - IP forwarding 和網橋過濾器自動配置

### 當前狀態

- ✅ **Infrastructure**: 所有 VM 運行正常
- ✅ **Master Nodes**: 3 個 master 節點完全就緒
- ✅ **HA Configuration**: VIP 和證書配置正確
- 🔄 **Worker Node**: 正在完成 LVM 配置和加入集群

### 預期最終狀態

完成 worker 節點部署後，將擁有：
- ✅ 3-node HA control plane (master-1, master-2, master-3)
- ✅ 1 worker node (app-worker)
- ✅ VIP-based load balancing (192.168.0.10)
- ✅ Calico CNI networking
- ✅ 準備好部署應用和儲存系統 (TopoLVM)

**預計完成時間**: 5-10 分鐘內
