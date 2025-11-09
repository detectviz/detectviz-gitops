# vm-1 網路問題診斷報告

**日期**: 2025-11-08
**問題**: vm-1 網路嚴重丟包，55% 穩定丟包率

---

## 問題總結

### 主要症狀
1. **vm-1 到 Proxmox 主機（192.168.0.1）**: 55% 穩定丟包率
2. **vm-1 到其他 VM（vm-2/3/4/5）**: 100% 不通，顯示 "Destination Host Unreachable"
3. **其他 VM 到 vm-1**: "Destination Port Unreachable" （可達但被拒絕）
4. **vm-1 到外網（8.8.8.8）**: 20% 丟包率（相對正常）

### 關鍵發現

#### 1. 丟包模式
```bash
# 100 個 ping 封包測試結果
100 packets transmitted, 45 received, 55% packet loss
# 前 55 個封包全部丟失，從 icmp_seq=56 開始才有回應
```

#### 2. ARP 表異常
```bash
# vm-1 的 ARP 表顯示其他 VM 都是 FAILED 狀態
192.168.0.12 dev eth0  FAILED  # vm-2
192.168.0.13 dev eth0  FAILED  # vm-3
192.168.0.14 dev eth0  FAILED  # vm-4
192.168.0.15 dev eth0  FAILED  # vm-5
192.168.0.1  dev eth0 lladdr dc:62:79:5f:4a:92 REACHABLE  # Proxmox 正常
```

#### 3. 網卡統計數據
```bash
# eth0 統計顯示大量接收丟包
RX: bytes packets errors dropped missed mcast
  1054006375 4396361    0     978     0     0
# dropped: 978 個封包被丟棄
```

#### 4. tcpdump 測試結果
- 從 vm-2 ping vm-1 時，vm-1 的 eth0 **完全沒有收到任何 ICMP 封包**
- 這表明封包在到達 vm-1 之前就被丟棄了

#### 5. 雙向測試結果對比
```bash
# vm-1 -> vm-2: Destination Host Unreachable (無法找到主機)
# vm-2 -> vm-1: Destination Port Unreachable (可達但被拒絕)
# vm-2 的 ARP 表有 vm-1 的 MAC: bc:24:11:74:5a:6d STALE
```

#### 6. 網卡驅動信息
```bash
# ethtool eth0 顯示
Speed: Unknown!
Duplex: Unknown! (255)
Auto-negotiation: off
# VirtIO 網卡但速度未知，可能配置異常
```

---

## 問題根因分析

基於以上診斷，問題**不是 vm-1 內部的防火牆或路由配置**，而是：

### 最可能的原因：Proxmox VirtIO 網卡或 Bridge 配置問題

1. **VirtIO 網卡隊列配置不當**
   - vm-1 的 VirtIO 網卡可能使用了與其他 VM 不同的隊列配置
   - 可能導致封包處理延遲或丟失

2. **Proxmox vmbr0 Bridge 的 MAC 學習或轉發問題**
   - Bridge 可能沒有正確學習 vm-1 的 MAC 地址
   - 或者 STP (生成樹協議) 導致端口阻塞

3. **vm-1 的 tap 介面配置異常**
   - Proxmox 為 vm-1 創建的 tap 介面可能有問題
   - 可能是隊列大小、緩衝區或其他參數配置錯誤

4. **硬體層級的封包過濾**
   - Proxmox 主機的 iptables 或 ebtables 可能過濾了部分流量
   - 或者網卡硬體 offload 功能導致問題

### 為什麼不是 vm-1 內部問題

1. ✅ **iptables 規則正常**: 已添加 ACCEPT ICMP 規則，仍然丟包
2. ✅ **路由表正常**: `192.168.0.0/24 dev eth0` 路由正確
3. ✅ **DNS 正常**: 可以解析外部域名
4. ✅ **外網訪問正常**: 可以 ping 通 8.8.8.8
5. ❌ **tcpdump 看不到封包**: 說明封包沒有到達 vm-1 的 eth0

---

## 推薦修復方案

### 方案 1：檢查並修復 Proxmox Bridge 配置（最優先）

**在 Proxmox 主機執行：**

```bash
# 1. 檢查 vmbr0 的 MAC 地址表
brctl showmacs vmbr0 | grep "bc:24:11:74:5a:6d"
# 應該看到 vm-1 的 MAC 地址

# 2. 檢查 vm-1 的 tap 介面
ip -s link show | grep -A 10 "tap.*-vm-1"
# 或者根據 VM ID
ip -s link show | grep -A 10 "tap111"

# 3. 檢查 tap 介面的錯誤統計
ip -s link show tap111i0  # 假設 vm-1 ID 是 111

# 4. 如果 STP 啟用，檢查端口狀態
brctl showstp vmbr0 | grep -A 10 "tap111"

# 5. 如果端口處於 blocking 狀態，禁用 STP
brctl stp vmbr0 off

# 6. 重啟 vm-1 的網路介面
ip link set tap111i0 down
ip link set tap111i0 up
```

### 方案 2：調整 vm-1 的 VirtIO 網卡配置

**在 Proxmox 主機執行：**

```bash
# 1. 查看 vm-1 當前網卡配置（假設 VM ID 是 111）
qm config 111 | grep net

# 2. 停止 vm-1
qm stop 111

# 3. 重新配置網卡，使用更保守的設定
# 獲取當前 MAC 地址
MAC=$(qm config 111 | grep "^net0:" | grep -oP 'virtio=\K[^,]+')

# 4. 更新網卡配置
qm set 111 -net0 virtio=$MAC,bridge=vmbr0,firewall=0

# 5. 啟動 vm-1
qm start 111

# 6. 等待啟動後測試
sleep 30
```

### 方案 3：檢查 Proxmox 主機的封包過濾

**在 Proxmox 主機執行：**

```bash
# 1. 檢查 ebtables 規則
ebtables -L

# 2. 檢查 bridge 的 iptables 規則
iptables -L FORWARD -n -v | grep vmbr0

# 3. 檢查是否啟用了 bridge netfilter
cat /proc/sys/net/bridge/bridge-nf-call-iptables
cat /proc/sys/net/bridge/bridge-nf-call-ip6tables

# 4. 如果啟用，暫時禁用測試
echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables
echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables

# 5. 測試後如果有改善，永久禁用
cat >> /etc/sysctl.conf <<EOF
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
EOF
sysctl -p
```

### 方案 4：重建 vm-1 的網路介面（最激進）

**在 Proxmox 主機執行：**

```bash
# 1. 停止 vm-1
qm stop 111

# 2. 刪除現有網卡
qm set 111 -delete net0

# 3. 添加新網卡（使用新的 MAC 地址）
qm set 111 -net0 virtio,bridge=vmbr0,firewall=0

# 4. 啟動 vm-1
qm start 111

# 5. 在 vm-1 內部更新網路配置
# SSH 到 vm-1 後執行
sudo netplan apply
# 或
sudo systemctl restart networking
```

---

## 臨時解決方案（vm-1 內部）

如果無法訪問 Proxmox 主機，可以在 vm-1 內部嘗試以下緩解措施：

### 調整 ARP 參數

```bash
# SSH 到 vm-1
ssh ubuntu@192.168.0.11

# 1. 增加 ARP 重試次數和超時
sudo sysctl -w net.ipv4.neigh.eth0.retrans_time_ms=1000
sudo sysctl -w net.ipv4.neigh.eth0.base_reachable_time_ms=30000
sudo sysctl -w net.ipv4.neigh.default.gc_stale_time=120

# 2. 永久化設定
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.ipv4.neigh.eth0.retrans_time_ms = 1000
net.ipv4.neigh.eth0.base_reachable_time_ms = 30000
net.ipv4.neigh.default.gc_stale_time = 120
EOF'

# 3. 應用設定
sudo sysctl -p
```

### 調整反向路徑過濾

```bash
# 當前設定是 2 (strict mode)，改為 1 (loose mode)
sudo sysctl -w net.ipv4.conf.eth0.rp_filter=1
sudo sysctl -w net.ipv4.conf.all.rp_filter=1

# 永久化
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF
net.ipv4.conf.eth0.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
EOF'

sudo sysctl -p
```

### 重啟網路服務

```bash
# 方法 1: 使用 netplan
sudo netplan apply

# 方法 2: 重啟 networking 服務
sudo systemctl restart networking

# 方法 3: 完全重置網路介面
sudo ip link set eth0 down
sudo ip link set eth0 up
sudo dhclient eth0
```

---

## 驗證修復

修復後，執行以下測試：

```bash
# 1. 長時間 ping 測試（從工作站）
ssh ubuntu@192.168.0.11 "ping -c 200 -i 0.5 192.168.0.1" | tee ping-test.log
grep "packet loss" ping-test.log
# 期望: 0% packet loss

# 2. 測試 VM 間連通性
ssh ubuntu@192.168.0.11 "ping -c 10 192.168.0.12"
# 期望: 0% packet loss

# 3. 檢查 ARP 表
ssh ubuntu@192.168.0.11 "ip neigh show | grep 192.168.0"
# 期望: 所有 VM 都是 REACHABLE 狀態

# 4. 測試 Kubernetes 節點狀態
ssh ubuntu@192.168.0.11 "kubectl --kubeconfig=/tmp/admin.conf get nodes"
# 期望: 所有節點 Ready
```

---

## 後續監控

修復後建議設置監控：

```bash
# 創建網路監控腳本
cat > ~/monitor-vm1.sh <<'EOF'
#!/bin/bash
LOG="/var/log/vm1-network-monitor.log"
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Ping 測試
    PING_RESULT=$(ssh ubuntu@192.168.0.11 "ping -c 10 -W 2 192.168.0.1 2>&1 | tail -2")

    # ARP 檢查
    ARP_STATUS=$(ssh ubuntu@192.168.0.11 "ip neigh show | grep -c FAILED")

    echo "[$TIMESTAMP] Ping: $PING_RESULT | ARP Failures: $ARP_STATUS" >> $LOG

    sleep 300  # 每 5 分鐘檢查一次
done
EOF

chmod +x ~/monitor-vm1.sh
nohup ~/monitor-vm1.sh &
```

---

## 聯繫和升級

如果上述方案都無法解決：

1. **收集 Proxmox 端日誌**:
   ```bash
   journalctl -u pvedaemon -n 100
   journalctl -u pve-cluster -n 100
   dmesg | grep -i "vmbr0\|tap\|bridge"
   ```

2. **考慮硬體問題**:
   - 檢查實體網卡狀態
   - 檢查交換機端口
   - 更換網線

3. **Proxmox 論壇求助**:
   - 提供 vm-1 配置: `qm config 111`
   - 提供 bridge 配置: `cat /etc/network/interfaces`
   - 提供錯誤日誌

---

## 更新記錄

- **2025-11-08**: 初始診斷報告
- 問題狀態: **待修復 - 需要 Proxmox 主機訪問權限**
