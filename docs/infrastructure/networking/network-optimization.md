# 網路優化指南

## 概述

本指南說明 Proxmox/KVM 環境中的網路優化設置，解決常見的網路性能和連線問題。

## rp_filter 設置

[Proxmox 修改 rp_filter 設定](https://pve.proxmox.com/pve-docs/chapter-pvesdn.html#_multiple_evpn_exit_nodes)

### 問題描述
在 KVM/Bridge/Tap 網路環境中，可能會遇到 ICMP Reply 封包遺失的問題。這是因為 Linux 的反向路徑過濾 (Reverse Path Filtering) 機制。

### 解決方案
將 `rp_filter` 設為 `1` (Loose Mode) 而不是 `0` (Off)，允許橋接的非對稱路由。

### 配置步驟

#### 1. 建立設定檔
```bash
cat <<EOF | tee /etc/sysctl.conf
# 覆蓋 PVE Firewall 的 rp_filter 設定，允許橋接非對稱路由
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
```

#### 2. 立即載入設定
```bash
sysctl --system
```

#### 3. 驗證設置
```bash
sysctl net.ipv4.conf.all.rp_filter
# 預期輸出: net.ipv4.conf.all.rp_filter = 1
```

### 技術說明
- **rp_filter = 0**: 完全關閉反向路徑過濾 (不安全)
- **rp_filter = 1**: 寬鬆模式，允許橋接網路的非對稱路由
- **rp_filter = 2**: 嚴格模式 (預設值，可能導致橋接問題)

## VM 網路優化

### VirtIO 驅動
```yaml
# VM 網路配置優化
Network Device:
  - Model: virtio          # 使用 VirtIO 驅動，效能最佳
  - Firewall: enabled      # 啟用防火牆
  - Link down: disabled    # 保持鏈路啟用
  - Multiqueue: enabled    # 多 CPU 時啟用多隊列
```

### 多隊列設置
對於多 CPU VM，啟用多隊列以提升網路性能：

```bash
# 在 VM 中檢查隊列數量
ethtool -l eth0

# 設置隊列數量
ethtool -L eth0 combined 4
```

## 網路性能測試

### 基本連線測試
```bash
# ICMP 測試
ping -c 4 192.168.0.1

# TCP 連線測試
telnet 192.168.0.2 22

# DNS 解析測試
time nslookup google.com
```

### 吞吐量測試
```bash
# 安裝 iperf3
apt install iperf3 -y

# 服務器端
iperf3 -s

# 客戶端測試
iperf3 -c <server-ip> -t 30
```

### 網路負載測試
```bash
# 安裝網路測試工具
apt install iptraf-ng nload -y

# 實時網路監控
iptraf-ng

# 網路負載監控
nload
```

## 橋接網路優化

### Bridge 參數調優
```bash
# 查看橋接參數
brctl show vmbr0

# 優化橋接設置
brctl setfd vmbr0 0      # 轉發延遲設為 0
brctl stp vmbr0 off      # 關閉 STP (單橋接環境)
```

### 防火牆優化
```bash
# 查看橋接防火牆規則
iptables -L -v -n | grep vmbr0

# 優化橋接轉發
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
```

## MTU 設置

### Jumbo Frame 配置
```bash
# 檢查當前 MTU
```bash
ip link show vmbr0
```
```bash
# 輸出結果
5: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether bc:fc:e7:3b:ff:4c brd ff:ff:ff:ff:ff:ff
```
>  表示 Proxmox 主機的 bridge vmbr0 MTU 為 1500

# 設置 Jumbo Frame (9000) 
適用於 Kubernetes Pod Overlay（Flannel/VXLAN）網路傳輸

```bash
ip link set dev vmbr0 mtu 9000
ip link show vmbr0
```
```bash
# 輸出結果
5: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP mode DEFAULT group default qlen 1000
    link/ether bc:fc:e7:3b:ff:4c brd ff:ff:ff:ff:ff:ff
```
>  表示 Proxmox 主機的 bridge vmbr0 MTU 為 9000

# 永久設置
若確認無誤後，寫入 `/etc/network/interfaces` 永久生效：

```yaml
# /etc/network/interfaces
auto lo
iface lo inet loopback

iface enp4s0 inet manual
iface enp5s0 inet manual
iface enx36fe0bfce7d0 inet manual

auto vmbr0
iface vmbr0 inet static
	address 192.168.0.2/24
	gateway 192.168.0.1
	bridge-ports enp4s0
	bridge-stp off
	bridge-fd 0
  mtu 9000 # 適用於 Kubernetes Pod Overlay（Flannel/VXLAN）網路傳輸

source /etc/network/interfaces.d/*
```
重啟網路服務：
```bash
systemctl restart networking
```

### VM MTU 配置

1. VM 內部網卡（virtio）也必須設定對應的 Jumbo Frame MTU：
```bash
ip link set eth0 mtu 9000
```
[!NOTE]
>   所有節點與交換機必須支援 9000 MTU，否則封包會被丟棄。

2. 若使用 Kubernetes Overlay（如 Flannel），需確保底層 MTU 減去 50 bytes 封裝開銷，例如：
```yaml
kube-flannel.yaml 中設定：
- --iface=eth0
- --mtu=8950
```

## 網路故障排除

### 常見問題診斷

#### 封包遺失
```bash
# 檢查網路統計
ip -s link show vmbr0

# 查看丟棄的封包
netstat -i

# 網路抓包分析
tcpdump -i vmbr0 icmp -n
```

#### 性能問題
```bash
# CPU 使用率檢查
top -p $(pgrep qemu)

# 網路隊列檢查
ss -tunlp | grep qemu

# 橋接統計
brctl showstp vmbr0
```

#### 連線問題
```bash
# ARP 表檢查
arp -n

# 路由表檢查
ip route show

# 防火牆規則檢查
iptables -L -n
```

### 進階診斷工具
```bash
# 安裝網路診斷工具
apt install net-tools traceroute mtr tcpdump -y

# 追蹤路由
traceroute 192.168.0.1

# 網路鏈路測試
mtr 192.168.0.1

# 詳細網路統計
ip -s -s link show vmbr0
```

## 監控和維護

### 網路監控
```bash
# 安裝監控工具
apt install iftop vnstat -y

# 實時流量監控
iftop -i vmbr0

# 網路使用統計
vnstat -i vmbr0
```

### 定期檢查
- 網路連線狀態
- 橋接配置完整性
- 防火牆規則有效性
- DNS 解析正常性

## 安全注意事項

### 網路安全
- 定期更新防火牆規則
- 監控異常網路流量
- 限制不必要的網路服務

### 配置備份
```bash
# 備份網路配置
cp /etc/network/interfaces /etc/network/interfaces.backup

# 備份 sysctl 配置
cp /etc/sysctl.d/98-pve-networking.conf /etc/sysctl.d/98-pve-networking.conf.backup
```

## 相關文檔

- [Bridge 配置指南](bridge-config.md)
- [DNS 設置指南](dns-setup.md)
- [域名映射](domain-mapping.md)
- [Proxmox 配置指南](../proxmox/configuration.md)