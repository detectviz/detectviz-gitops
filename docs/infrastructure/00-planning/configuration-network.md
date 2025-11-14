# 網路配置

⚠️ **重要**：此步驟必須在所有其他配置之前完成，因為它是整個網路架構的基礎。
> 確保 enp5s0 已連接內部網路線路
> 所有節點的 enp5s0 應在同一 Layer 2 網段

## 目錄

- [網路架構總覽](#網路架構總覽)
  - [網路介面狀態](#網路介面狀態)
  - [網路流量分離](#網路流量分離)
  - [IP 位址對照表](#ip-位址對照表)
  - [Kubernetes 流量分層說明](#kubernetes-流量分層說明)
- [執行順序總覽](#執行順序總覽)
- [網路拓撲圖](#網路拓撲圖)
- [Proxmox 網路配置](#proxmox-網路配置)
  - [設定實體網卡 MTU](#1-設定實體網卡-mtu)
  - [更新網路配置](#2-更新網路配置)
  - [重新啟動網路服務](#3-重新啟動網路服務)
  - [驗證配置](#4-驗證配置)
  - [配置備份](#5-配置備份)
- [VM 網路配置](#vm-網路配置)
  - [Terraform 雙網路配置](#terraform-雙網路配置)
  - [Ansible 配置更新](#ansible-配置更新)
  - [Kubernetes CNI 配置](#kubernetes-cni-配置)
- [架構設計原則](#架構設計原則)
- [雙網路架構的優勢](#雙網路架構的優勢)
- [驗證檢查清單](#驗證檢查清單)
- [節點狀態檢查](#節點狀態檢查)
  - [橋接器與實體網卡狀態](#橋接器與實體網卡狀態)
  - [網路延遲與 MTU 驗證](#網路延遲與-mtu-驗證)
- [sysctl 網路參數調整](#sysctl-網路參數調整)
  - [Proxmox 宿主機設定](#一proxmox-宿主機設定必須)
  - [VM 節點設定](#二vm-節點設定建議)
  - [參數說明](#三參數說明)
  - [最佳實踐](#四最佳實踐)
- [VM 網路優化](#vm-網路優化)
  - [VirtIO 驅動配置](#virtio-驅動配置)
  - [多隊列設定](#多隊列設定-multiqueue)
  - [橋接網路優化](#橋接網路優化)
  - [進階優化](#進階優化可選)
  - [效能驗證](#效能驗證)

## 網路架構總覽

建立雙網路架構：
- **vmbr0 (enp4s0)**：管理網路 + 應用流量
- **vmbr1 (enp5s0)**：Kubernetes 內部網路（節點間通訊）

### 網路介面狀態

```bash
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: enp4s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master vmbr0 state UP mode DEFAULT group default qlen 1000
    link/ether bc:fc:e7:3b:ff:4c brd ff:ff:ff:ff:ff:ff
3: enp5s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/ether bc:fc:e7:3b:ff:4d brd ff:ff:ff:ff:ff:ff
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

## 執行順序總覽

**雙網路架構配置的正確執行順序**：

1. **硬體連接準備** - 連接第二張實體網卡 (enp5s0)
2. **Proxmox 網路配置** - 設定 vmbr0 和 vmbr1 雙橋接器
3. **Terraform VM 部署** - 創建具有雙網路配置的 VM
4. **Ansible 網路配置** - 配置 VM 雙網路介面
5. **Kubernetes CNI 配置** - 更新 CNI 使用內部網路
6. **驗證檢查** - 確保所有配置正確

---

### 網路拓撲圖

```bash
[Proxmox Host]
    ┌─────────────┐
    │   enp4s0    │ ←── 實體網卡（外接）
    │  (vmbr0)    │     mtu 1500
    │ 192.168.0.2 │
    └─────┬───────┘
          │
    ┌─────┴──────────────────────────────┐
    │                                    │
┌───┴────┐                           ┌───┴────┐
│ enp5s0 │                           │ enp5s0 │ ←── 實體網卡（內部）
│ (vmbr1)│                           │ (vmbr1)│ mtu 1500
│10.0.0.2│                           │10.0.0.2│
└───┬────┘                           └───┬────┘
    │                                    │
┌───┴──────────────────────────────┬─────┴─────┐
│                                  │           │
│  [Internal Kubernetes Network]   │           │
│  10.0.0.0/24                     │           │
│                                  │           │
├──────────────────────────────────┼───────────┤
│ Master-1    Master-2    Master-3 │ Worker    │
│ 10.0.0.11   10.0.0.12   10.0.0.13│10.0.0.14  │
│                                  │           │
│ [Kubernetes Control Plane]       │ [Pods]    │
│ • API Server (6443)              │ • Apps    │
│ • etcd (2379-2380)               │ • Services│
│ • Scheduler                      │           │
│ • Controller Manager             │           │
└──────────────────────────────────┴───────────┘

[External Network]
    192.168.0.0/24
    ├── Gateway: 192.168.0.1
    ├── DNS: 8.8.8.8
    └── Internet Access
```

---

### 0. 配置備份
```bash
# 備份網路配置
cp /etc/network/interfaces /etc/network/interfaces.backup

# 備份 sysctl 配置
cp /etc/sysctl.d/98-pve-networking.conf /etc/sysctl.d/98-pve-networking.conf.backup
```

### 1. 設定實體網卡 MTU

```bash
# 設定 enp4s0 MTU 為 9000
ip link set dev enp4s0 mtu 1500
```

> [!NOTE]
> 若使用 Overlay 網路（如 VXLAN / IPIP），請確保 CNI 層的 MTU 減去 50 bytes 封裝開銷，例如 Flannel 設定 `--mtu=8950`。


### 2. 更新網路配置

編輯 `/etc/network/interfaces`：

```bash
auto enp4s0
iface enp4s0 inet manual
    mtu 1500

# 保留 vmbr0 配置（外部網路，設 Gateway）
# 只有 vmbr0 設 Gateway
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.2/24
    gateway 192.168.0.1              
    bridge-ports enp4s0
    bridge-stp off
    bridge-fd 0
    mtu 1500

auto enp5s0
iface enp5s0 inet manual
    mtu 1500

# 新增 vmbr1 內部網路（不設 Gateway）
# vmbr1 不設 gateway
auto vmbr1
iface vmbr1 inet static
    address 10.0.0.2/24              
    bridge-ports enp5s0
    bridge-stp off
    bridge-fd 0
    mtu 1500
```

#### 橋接器與實體網卡對應
- **vmbr0** ↔ **enp4s0**: 實體網卡與橋接器的綁定
- **vmbr1** ↔ **enp5s0**: 實體網卡與橋接器的綁定
- **MTU 9000**: 支援巨型幀以提升網路效能，需要網卡、交換機、線材全部支援巨型幀（Jumbo Frames），否則會導致連線失敗

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

---

## VM 網路配置

> [!NOTE]
> 所有節點與交換機必須支援 9000 MTU，否則封包會被丟棄。


#### 1. Terraform 雙網路配置

```hcl
# terraform.tfvars
proxmox_bridge     = "vmbr0"  # 管理/外部流量
k8s_overlay_bridge = "vmbr1"  # 內部節點通訊 (Pod / etcd)

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

#### 2. Ansible 配置更新

```yaml
# inventory.ini
[masters]
master-1 ansible_host=192.168.0.11 ansible_user=ubuntu  # vmbr0 IP
master-2 ansible_host=192.168.0.12 ansible_user=ubuntu
master-3 ansible_host=192.168.0.13 ansible_user=ubuntu

[masters:vars]
cluster_network=10.0.0.0/24  # vmbr1 集群網路

[workers]
app-worker ansible_host=192.168.0.14 ansible_user=ubuntu

[workers:vars]
cluster_network=10.0.0.0/24  # vmbr1 集群網路

[k8s_cluster:vars]
k8s_overlay_bridge = "vmbr1"
network_mtu = 1500
```

#### 3. Kubernetes CNI 配置

1. 更新 Calico 或 Flannel 配置以使用內部集群網路：
```yaml
# calico-config.yaml (範例)
- name: IP_AUTODETECTION_METHOD
  value: "interface=eth1"  # eth1 對應 vmbr1

# 若未來使用 Calico，建議使用 CIDR 自動偵測：
# 這樣可動態偵測內部橋接 IP，避免介面名稱變動
- name: IP_AUTODETECTION_METHOD
  value: "cidr=10.0.0.0/24"

# 或使用 can-reach 方法
- name: IP_AUTODETECTION_METHOD
  value: "can-reach=10.0.0.1"
```

2. 若使用 Kubernetes Overlay（如 Flannel），需確保底層 MTU 減去 50 bytes 封裝開銷：
```yaml
# kube-flannel.yaml 中設定
- --iface=eth1        # 對應 vmbr1 的介面
- --iface-regex=eth1  # 或使用 regex 匹配
- --mtu=1450           # 1500 - 50 (VXLAN overhead)
```

> [!IMPORTANT]
> Flannel MTU 計算：實體網路 MTU (9000) - VXLAN 封裝開銷 (50) = 8950

### 架構設計原則

- **vmbr0（外部網路）**：配置 Default Gateway，用於控制平面管理與對外流量。
- **vmbr1（內部網路）**：無 Gateway，僅用於節點間私有通訊，Kubernetes Control Plane、etcd、Pod Overlay 都使用此網路。
- **路由分離**：確保外部流量（SSH、應用服務）與內部流量（etcd、API Server）完全隔離。

### 雙網路架構的優勢

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

---

## 驗證檢查清單

- [ ] Proxmox 宿主機 enp4s0 和 enp5s0 的 MTU 設為 9000
- [ ] vmbr0 的 MTU 設為 9000
- [ ] vmbr1 的 MTU 設為 9000
- [ ] VM 可以正常啟動並獲取 IP
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

> [!NOTE]
> 若使用 LACP 或 VLAN trunk，可在 vmbr1 加上：
> bridge_ports enp5s0.100
> 並在 Switch 側設定對應 VLAN。

## sysctl 網路參數調整

為確保橋接封包、Kubernetes CNI、etcd 與 Overlay 網路正常運作，Proxmox（宿主機）與 VM（節點）皆需設定適當的 sysctl 參數。

### 一、Proxmox 宿主機設定（必須）
Proxmox 作為橋接與虛擬網路轉發的主控層，若未調整 rp_filter 或 ip_forward，可能導致 ICMP / VXLAN 封包被丟棄。

#### 設定檔：`/etc/sysctl.d/99-proxmox-network.conf`
```bash
cat <<EOF | tee /etc/sysctl.d/99-proxmox-network.conf
# Proxmox Host Network Configuration
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
# 若不使用 IPv6，可停用
net.ipv6.conf.all.disable_ipv6 = 1
EOF

sysctl --system
```

#### 驗證：
```bash
sysctl net.ipv4.ip_forward
sysctl net.ipv4.conf.all.rp_filter
```
預期輸出：
```
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 2
```

---

### 二、VM 節點設定（Ansible 自動化部署）
每個 Kubernetes 節點（Master / Worker）都需開啟 IP 轉發與橋接封包檢查，以確保 Pod 與 Service 封包能正確路由。

#### 設定檔：`/etc/sysctl.d/99-k8s.conf`
```bash
cat <<EOF | sudo tee /etc/sysctl.d/99-k8s.conf
# Kubernetes Node sysctl Configuration
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF

sudo sysctl --system
```

#### 驗證：
```bash
sysctl net.ipv4.ip_forward
sudo iptables -L | grep KUBE
```
若看到 `KUBE-SERVICES`、`KUBE-FORWARD` 等規則，表示 NetworkPolicy 模組已啟用。

---

### 三、參數說明

| 參數 | 推薦值 | 說明 |
|------|---------|------|
| `net.ipv4.ip_forward` | 1 | 啟用 IP 封包轉發，CNI Overlay 必須 |
| `net.bridge.bridge-nf-call-iptables` | 1 | 允許橋接封包進入 iptables |
| `net.ipv4.conf.all.rp_filter` | 2 | 寬鬆模式允許橋接非對稱路由（推薦 Kubernetes）|
| `net.ipv4.conf.default.rp_filter` | 2 | 套用至新建立介面 |
| `net.ipv6.conf.all.disable_ipv6` | 1 *(可選)* | 停用 IPv6 避免干擾 |

---

### 四、最佳實踐
- Proxmox 與所有 VM 都需保持一致的 rp_filter 與 ip_forward 設定；
- 建議使用 `99-proxmox-network.conf`（宿主層）與 `99-k8s.conf`（節點層）分層管理；
- 可在 Terraform / Ansible 階段自動套用，確保新節點初始化時設定一致。

---

此配置可避免常見封包遺失（ICMP Reply Drop、VXLAN 不通）問題，確保 Detectviz 叢集在 Proxmox 雙橋接環境下運作穩定。

## VM 網路優化

為確保虛擬機在 Kubernetes 叢集運行期間具備最佳網路效能，建議啟用 VirtIO 驅動、調整多隊列 (Multiqueue) 與 MTU，並針對橋接網路進行調優。

### VirtIO 驅動配置
在 Proxmox 建立或修改 VM 時，建議：
```yaml
Network Device:
  - Model: virtio          # 使用 VirtIO 驅動，效能最佳
  - Firewall: enabled      # 啟用 VM 層級防火牆
  - Link down: disabled    # 確保連線維持啟用
  - Multiqueue: enabled    # 啟用多隊列（多核心 VM 效益顯著）
```
> [!TIP]
> 若 VM 僅配置單核心 CPU，Multiqueue 無效；多核心 VM 建議設置 `queues = CPU 核心數`。

---

### 多隊列設定 (Multiqueue)
啟用多隊列可讓多核心 VM 平行處理網路封包，顯著提升吞吐量。

```bash
# 檢查支援的最大隊列數
ethtool -l eth0

# 設定多隊列（例如 4 核 VM）
sudo ethtool -L eth0 combined 4
```
建議：  
- 每個 vCPU 配置一個網路隊列。  
- 驗證設定：
  ```bash
  ethtool -l eth0 | grep Combined
  ```

---

### 橋接網路優化
調整 Proxmox 橋接器以降低延遲與封包等待時間：

```bash
# 檢查橋接狀態
brctl show vmbr0

# 優化橋接參數（單橋環境可關閉 STP）
brctl setfd vmbr0 0
brctl stp vmbr0 off
```
> [!CAUTION]
> 若日後啟用 LACP 或 VLAN Trunk，多橋接環境請保持 STP = on，避免廣播迴圈。

---

### 進階優化（可選）
| 功能 | 目的 | 指令範例 |
|------|------|-----------|
| 關閉 GRO/GSO/TSO | 降低封包延遲 | `ethtool -K eth0 gro off gso off tso off` |
| 啟用 RPS/RFS | 分散 CPU 處理負載 | `echo f > /sys/class/net/eth0/queues/rx-0/rps_cpus` |
| 檢查 vhost_net 模組 | 確保虛擬網路加速啟用 | `lsmod | grep vhost_net` |

---

### 效能驗證
優化完成後，可透過 `iperf3` 驗證：
```bash
# Master-1 啟動伺服器
iperf3 -s

# Master-2 進行測試
iperf3 -c 10.0.0.12 -P 4 -t 30
```
> 預期結果：單流吞吐量約 8–10 Gbps（VirtIO + Multiqueue 組合）

---

此配置可確保 Detectviz 叢集在 Proxmox 環境中具備最佳的網路效能與穩定性，適用於高併發與多節點應用場景。
