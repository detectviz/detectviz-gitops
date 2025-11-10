# DetectViz 網路配置指南

## 目錄

- [執行順序總覽](#執行順序總覽)
- [網路架構總覽](#網路架構總覽)
- [Proxmox 手動網路配置](#proxmox-手動網路配置)
- [Proxmox 橋接器配置](#proxmox-橋接器配置)
- [Terraform 配置（階段一）](#terraform-配置階段一)
- [VM 網路配置](#vm-網路配置)
- [Ansible 配置（階段一）](#ansible-配置階段一)
- [驗證檢查清單](#驗證檢查清單)
- [節點狀態檢查](#節點狀態檢查)
- [未來擴展（階段二）](#未來擴展階段二)
  - [網路架構總覽](#網路架構總覽)
  - [網路拓撲圖](#網路拓撲圖)
  - [網路流量分離](#網路流量分離)
  - [IP 位址對照表](#ip-位址對照表)
  - [Kubernetes 流量分層說明](#kubernetes-流量分層說明)
  - [階段二配置步驟](#階段二配置步驟)
  - [架構設計原則](#架構設計原則)
  - [階段二的優勢](#階段二的優勢)
  - [遷移注意事項](#遷移注意事項)

## 執行順序總覽

**階段一網路配置的正確執行順序**：

1. **閱讀網路架構總覽** - 了解整體設計
2. **Proxmox 手動網路配置** - 設定橋接器和 MTU（必須先完成）
3. **Terraform VM 部署** - 創建具有正確網路配置的 VM
4. **Ansible 網路配置** - 配置 VM 內部網路設定
5. **驗證檢查** - 確保所有配置正確

---

## 網路架構總覽

**階段一：單網卡運作**（當前推薦配置）

目前採用單一網路橋接器設計，所有 Kubernetes 節點透過 `vmbr0` 進行網路通訊。

### 網路拓撲

```bash
[Proxmox Host]
    enp4s0 (MTU 9000) ──┐
                        ├── vmbr0 (MTU 9000)
                        │
[VM Network]            ├── Master-1: 192.168.0.11
                        ├── Master-2: 192.168.0.12
                        ├── Master-3: 192.168.0.13
                        └── Worker:   192.168.0.14
```

### 網路介面狀態

```bash
root@proxmox:~# ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN
2: enp4s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc mq master vmbr0 state UP
3: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP
```

| 介面 | 狀態 | MTU | 用途 | 備註 |
|------|------|-----|------|------|
| **vmbr0** | UP | 9000 | 主橋接器 | 所有 VM 網路 |
| **enp4s0** | UP | 9000 | 實體網卡 | 綁定到 vmbr0 |

## Proxmox 手動網路配置

⚠️ **重要**：此步驟必須在所有其他配置之前完成，因為它是整個網路架構的基礎。

### 1. 設定實體網卡 MTU

```bash
# 設定 enp4s0 MTU 為 9000
sudo ip link set dev enp4s0 mtu 9000
```

### 2. 更新網路配置

編輯 `/etc/network/interfaces`：

```bash
auto enp4s0
iface enp4s0 inet manual
    mtu 9000

auto vmbr0
iface vmbr0 inet static
    address 192.168.0.2/24           # Proxmox 宿主機 IP
    gateway 192.168.0.1              # 網路閘道
    bridge-ports enp4s0              # 綁定的實體網卡
    bridge-stp off                   # 停用生成樹協議
    bridge-fd 0                      # 設定轉發延遲為 0
    mtu 9000                         # 支援巨型幀
```

#### 橋接器與實體網卡對應
- **vmbr0** ↔ **enp4s0**: 實體網卡與橋接器的綁定
- **MTU 9000**: 支援巨型幀以提升網路效能

### 3. 重新啟動網路服務

```bash
sudo systemctl restart networking
```

### 4. 驗證配置

```bash
# 檢查橋接器狀態
ip addr show vmbr0
ip route

# 測試網路連線
ping 192.168.0.1
ping 8.8.8.8
```

### 5. 若未來建立 vmbr1（階段二）

當 enp5s0 接線時，可新增獨立內部網路橋接器：

```bash
auto enp5s0
iface enp5s0 inet manual
    mtu 9000

auto vmbr1
iface vmbr1 inet static
    address 10.0.0.2/24              # 內部網路 IP（避免與 vmbr0 衝突）
    # vmbr1 不設 gateway（內部網路不需路由到外部）
    bridge-ports enp5s0              # 綁定的實體網卡
    bridge-stp off                   # 停用生成樹協議
    bridge-fd 0                      # 設定轉發延遲為 0
    mtu 9000                         # 支援巨型幀
```

> 暫時不需加入此段，因為目前尚未接線。使用獨立 IP 段可避免路由競爭問題。

## Terraform 配置（階段一）

```hcl
# terraform.tfvars
proxmox_bridge     = "vmbr0"  # 主管理網路
proxmox_mtu        = 9000     # 支援巨型幀
k8s_overlay_bridge = "vmbr0"  # 同主網路
```

---

## VM 網路配置

### Terraform VM 配置

所有 VM 只使用單一網路介面：

```hcl
resource "proxmox_virtual_environment_vm" "k8s_masters" {
  # ... 其他配置 ...

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    enabled = true
    mtu    = 9000
  }
}
```

### VM 內部網路設定

VM 啟動後會自動配置網路，Ansible 會設定 MTU：

```yaml
# Ansible 網路配置任務
- name: Configure network MTU (配置網路 MTU)
  command: ip link set ens18 mtu {{ network_mtu }}
```

## Ansible 配置（階段一）

```yaml
# Ansible inventory 變數
[k8s_cluster:vars]
network_mtu = 9000
k8s_overlay_bridge = "vmbr0"
```

---

## 驗證檢查清單

- [ ] Proxmox 宿主機 enp4s0 MTU 設為 9000
- [ ] vmbr0 MTU 設為 9000
- [ ] VM 可以正常啟動並獲取 IP
- [ ] VM 內部 ens18 介面 MTU 設為 9000
- [ ] 網路連線正常（內部/外部）

---

## 節點狀態檢查

### 橋接器與實體網卡狀態

```bash
# 查看橋接器與實體卡狀態
ip -br addr show
```

### 網路延遲與 MTU 驗證

```bash
# 驗證 MTU 是否真的生效（8972 = 9000 - 28 bytes for headers）
ping -M do -s 8972 192.168.0.1

# 檢查路由表
ip route
```

---

## 未來擴展（階段二）：雙網路架構

### 網路架構總覽

階段二啟用第二張實體網卡，建立雙網路架構：
- **vmbr0 (enp4s0)**：管理網路 + 應用流量
- **vmbr1 (enp5s0)**：Kubernetes 內部網路（節點間通訊）

### 網路拓撲圖

```bash
[Proxmox Host]
    ┌─────────────┐
    │   enp4s0    │ ←── 實體網卡（外接）
    │  (vmbr0)    │     MTU 9000
    │ 192.168.0.2 │
    └─────┬───────┘
          │
    ┌─────┴─────────────────────────────┐
    │                                   │
┌───┴───┐                           ┌───┴───┐
│ enp5s0│ ←── 實體網卡（內部）         │ enp5s0│
│ (vmbr1)│     MTU 9000             │ (vmbr1)│
│10.0.0.2│                          │10.0.0.2│
└───┬───┘                           └───┬───┘
    │                                   │
┌───┴─────────────────────────────┬─────┴───┐
│                                 │         │
│  [Internal Kubernetes Network]  │         │
│  10.0.0.0/24                   │         │
│                                 │         │
├─────────────────────────────────┼─────────┤
│ Master-1    Master-2    Master-3 │ Worker  │
│ 10.0.0.11   10.0.0.12   10.0.0.13│10.0.0.14│
│                                 │         │
│ [Kubernetes Control Plane]      │ [Pods]  │
│ • API Server (6443)            │ • Apps   │
│ • etcd (2379-2380)             │ • Services│
│ • Scheduler                    │         │
│ • Controller Manager           │         │
└─────────────────────────────────┴─────────┘

[External Network]
    192.168.0.0/24
    ├── Gateway: 192.168.0.1
    ├── DNS: 8.8.8.8
    └── Internet Access
```

### 網路流量分離

| 網路類型 | 橋接器 | IP 段 | 用途 | 說明 |
|----------|--------|-------|------|------|
| **外部網路** | vmbr0 | 192.168.0.0/24 | 管理 + 應用流量 | SSH 登入、應用服務、外部存取 |
| **內部網路** | vmbr1 | 10.0.0.0/24 | Kubernetes 內部 | 節點間通訊、Pod Overlay 網路、etcd |

### IP 位址對照表

| 節點 | vmbr0 IP (外部網路) | vmbr1 IP (內部網路) | 用途 |
|------|-------------------|-------------------|------|
| Proxmox Host | 192.168.0.2 | 10.0.0.2 | 橋接器網關 |
| Master-1 | 192.168.0.11 | 10.0.0.11 | 控制平面節點 |
| Master-2 | 192.168.0.12 | 10.0.0.12 | 控制平面節點 |
| Master-3 | 192.168.0.13 | 10.0.0.13 | 控制平面節點 |
| Worker | 192.168.0.14 | 10.0.0.14 | 應用工作節點 |

### Kubernetes 流量分層說明

Kubernetes CNI（如 Calico / Flannel）會在 `vmbr1` 上建立 Overlay Tunnel（VXLAN / IPIP），因此：
- **節點間通訊**：直接走 `vmbr1` 實體網路
- **Pod Overlay 通訊**：Pod 間流量 encapsulated 在該網路中傳輸

### 階段二配置步驟

#### 1. 硬體連接
```bash
# 確保 enp5s0 已連接內部網路線路
# 所有節點的 enp5s0 應在同一 Layer 2 網段
```

#### 2. Proxmox 網路配置

編輯 `/etc/network/interfaces`：

```bash
# 保留 vmbr0 配置（外部網路，設 Gateway）
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.2/24
    gateway 192.168.0.1              # 只有 vmbr0 設 Gateway
    bridge-ports enp4s0
    bridge-stp off
    bridge-fd 0
    mtu 9000

# 新增 vmbr1 內部網路（不設 Gateway）
auto enp5s0
iface enp5s0 inet manual
    mtu 9000

auto vmbr1
iface vmbr1 inet static
    address 10.0.0.2/24              # vmbr1 不設 gateway
    bridge-ports enp5s0
    bridge-stp off
    bridge-fd 0
    mtu 9000
```

#### 3. VM 網路配置更新

Terraform 配置需更新為雙網路：

```hcl
# terraform.tfvars
proxmox_bridge     = "vmbr0"  # 外部網路
k8s_overlay_bridge = "vmbr1"  # 內部網路

# VM 配置
resource "proxmox_virtual_environment_vm" "k8s_masters" {
  # 外部網路 (管理 + 應用)
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    enabled = true
    mtu    = 9000
  }

  # 內部網路 (Kubernetes)
  network_device {
    bridge = "vmbr1"
    model  = "virtio"
    enabled = true
    mtu    = 9000
  }
}
```

#### 4. Ansible 配置更新

```yaml
# inventory.ini
[masters]
master-1 ansible_host=192.168.0.11 ansible_user=ubuntu  # vmbr0 IP
master-2 ansible_host=192.168.0.12 ansible_user=ubuntu
master-3 ansible_host=192.168.0.13 ansible_user=ubuntu

[masters:vars]
internal_ip=10.0.0.11  # vmbr1 IP，用於 Kubernetes 內部通訊

[workers]
app-worker ansible_host=192.168.0.14 ansible_user=ubuntu

[workers:vars]
internal_ip=10.0.0.14  # vmbr1 IP

[k8s_cluster:vars]
k8s_overlay_bridge = "vmbr1"
network_mtu = 9000
```

#### 5. Kubernetes CNI 配置

更新 Calico 或 Flannel 配置以使用內部網路：

```yaml
# calico-config.yaml (範例)
- name: IP_AUTODETECTION_METHOD
  value: "interface=ens19"  # ens19 對應 vmbr1

# 或指定特定 IP
- name: IP
  value: "{{ internal_ip }}"
```

### 架構設計原則

- **vmbr0（外部網路）**：配置 Default Gateway，用於控制平面管理與對外流量。
- **vmbr1（內部網路）**：無 Gateway，僅用於節點間私有通訊，Kubernetes Control Plane、etcd、Pod Overlay 都使用此網路。
- **路由分離**：確保外部流量（SSH、應用服務）與內部流量（etcd、API Server）完全隔離。

### 階段二的優勢

#### 效能提升
- **流量分離**：管理流量與應用流量分離
- **減少干擾**：Kubernetes 內部通訊不影響外部存取
- **網路優化**：可針對不同網路類型進行最佳化

#### 架構改善
- **安全性**：內部網路隔離
- **可擴展性**：便於添加更多節點
- **維護便利**：網路問題診斷更精準

#### 使用場景
- **多節點叢集**：3+ 個 Master 節點
- **高流量應用**：需要網路效能優化的工作負載
- **網路隔離需求**：安全要求較高的環境

### 遷移注意事項

1. **逐步遷移**：可先保持階段一，逐步測試階段二
2. **網路連線**：確保所有節點的 enp5s0 在同一網段
3. **IP 規劃**：提前規劃 10.0.0.0/24 網段的使用
4. **測試驗證**：遷移前後都要進行完整網路測試

階段二配置將在需要更高網路效能和架構複雜度時實施。