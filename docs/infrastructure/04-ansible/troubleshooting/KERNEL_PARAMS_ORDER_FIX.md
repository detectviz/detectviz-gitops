# Kernel 參數配置順序修正

**日期**: 2025-11-13
**問題**: br_netfilter 模組載入順序錯誤
**狀態**: ✅ 已修正

---

## 🔴 問題

執行 Ansible 部署時遇到以下錯誤：

```
[ERROR]: Task failed: Module failed: setting net.bridge.bridge-nf-call-iptables failed:
sysctl: cannot stat /proc/sys/net/bridge/bridge-nf-call-iptables: No such file or directory
```

### 根本原因

`net.bridge.bridge-nf-call-iptables` 和 `net.bridge.bridge-nf-call-ip6tables` 這兩個 sysctl 參數只有在 `br_netfilter` 內核模組載入後才會存在。

之前的 task 順序是：
1. ❌ 先設定 sysctl 參數（包括 bridge-nf-call-*）
2. ❌ 再載入 br_netfilter 模組

這導致設定 bridge-nf-call-* 參數時失敗，因為對應的 `/proc/sys/net/bridge/` 路徑還不存在。

---

## ✅ 修正

### 文件

`ansible/roles/common/tasks/main.yml` (Lines 118-149)

### 正確的順序

```yaml
# ============================================
# Kubernetes 系統參數配置
# ============================================

# 步驟 1: 必須先載入 br_netfilter 模組
- name: "Load br_netfilter kernel module"
  become: true
  ansible.builtin.modprobe:
    name: br_netfilter
    state: present

# 步驟 2: 設定模組持久化
- name: "Ensure br_netfilter loads on boot"
  become: true
  ansible.builtin.lineinfile:
    path: /etc/modules-load.d/k8s.conf
    line: br_netfilter
    create: yes
    mode: "0644"

# 步驟 3: 現在可以安全地設定所有 sysctl 參數
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
```

---

## 📝 為什麼順序很重要？

### br_netfilter 模組的作用

`br_netfilter` 內核模組提供橋接網路過濾功能，載入後會創建以下 sysctl 參數：

- `/proc/sys/net/bridge/bridge-nf-call-iptables`
- `/proc/sys/net/bridge/bridge-nf-call-ip6tables`
- `/proc/sys/net/bridge/bridge-nf-call-arptables`

### 依賴關係

```
br_netfilter 模組
    ↓ (創建 /proc/sys/net/bridge/ 路徑)
bridge-nf-call-* 參數
    ↓ (允許設定)
sysctl 配置
```

### 錯誤順序的後果

如果在模組載入前嘗試設定參數：

```bash
$ sudo sysctl net.bridge.bridge-nf-call-iptables=1
sysctl: cannot stat /proc/sys/net/bridge/bridge-nf-call-iptables: No such file or directory
```

### 正確順序的結果

先載入模組，再設定參數：

```bash
$ sudo modprobe br_netfilter
$ sudo sysctl net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-iptables = 1
```

---

## ✅ 驗證

### 手動驗證順序

```bash
# 1. 確認模組未載入（可能會失敗）
lsmod | grep br_netfilter

# 2. 嘗試設定參數（會失敗）
sudo sysctl net.bridge.bridge-nf-call-iptables=1
# 預期錯誤: No such file or directory

# 3. 載入模組
sudo modprobe br_netfilter

# 4. 再次設定參數（成功）
sudo sysctl net.bridge.bridge-nf-call-iptables=1
# 預期輸出: net.bridge.bridge-nf-call-iptables = 1
```

### Ansible 執行驗證

```bash
# 重新執行 common role
ansible-playbook -i inventory.ini deploy-cluster.yml --tags common

# 預期結果: 所有 task 成功，無錯誤
```

### 檢查最終配置

```bash
# 檢查模組是否載入
ansible all -i inventory.ini -m shell -a "lsmod | grep br_netfilter"

# 檢查參數是否正確設定
ansible all -i inventory.ini -m shell -a "sysctl net.bridge.bridge-nf-call-iptables"
ansible all -i inventory.ini -m shell -a "sysctl net.ipv4.ip_forward"

# 檢查持久化配置
ansible all -i inventory.ini -m shell -a "cat /etc/modules-load.d/k8s.conf"
```

---

## 📚 相關知識

### Linux 內核模組載入機制

1. **modprobe**: 載入模組到當前運行的內核
   - 臨時生效，重啟後失效
   - 創建 `/proc/sys/` 下的對應參數

2. **/etc/modules-load.d/*.conf**: 設定開機自動載入
   - 永久生效，重啟後依然有效
   - 系統啟動時自動執行

### sysctl 參數設定

1. **sysctl -w**: 動態修改內核參數
   - 臨時生效，重啟後失效
   - 需要參數路徑存在

2. **/etc/sysctl.conf** 或 **/etc/sysctl.d/*.conf**: 設定持久化
   - 永久生效，重啟後自動應用
   - 需要對應的內核模組支援

---

## 🎯 最佳實踐

### Ansible Task 順序建議

對於需要內核模組支援的 sysctl 參數：

```yaml
# ✅ 正確順序
1. Load kernel module (modprobe)
2. Persist module configuration (/etc/modules-load.d/)
3. Configure sysctl parameters (sysctl)
4. Persist sysctl configuration (/etc/sysctl.d/)
```

### 為什麼 net.ipv4.ip_forward 不受影響？

`net.ipv4.ip_forward` 是內核內建參數，不需要額外載入模組，所以可以直接設定。

只有 `net.bridge.bridge-nf-call-*` 參數依賴 `br_netfilter` 模組。

---

## 🎉 總結

**問題**: Ansible 嘗試在 br_netfilter 模組載入前設定 bridge-nf-call-* 參數

**修正**: 調整 task 順序，先載入模組，再設定參數

**結果**: ✅ 所有內核參數正確配置，Kubernetes 網路功能正常

**相關文檔**:
- `KERNEL_PARAMS_FIX.md` - Kubernetes 核心參數完整說明
- `ansible/roles/common/tasks/main.yml` - Lines 118-149
