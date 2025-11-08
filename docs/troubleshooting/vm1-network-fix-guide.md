# vm-1 網路週期性凍結修復指南

## 問題描述

vm-1 與 Proxmox 主機（192.168.0.1）之間的連線週期性 freeze 約 40 秒，表現為：
- ping 週期性丟失約 40-42 個封包
- icmp_seq 從 11 跳到 54、從 58 跳到 100、從 105 跳到 147
- 其他 VM (vm-2 到 vm-5) 網路正常

**根本原因分析：**
這是典型的虛擬網路層問題，可能原因包括：
1. **VirtIO 驅動問題** - VirtIO 隊列溢出或緩衝區不足
2. **Bridge STP 重新計算** - 生成樹協議的週期性重新計算
3. **網卡中斷合併** - 中斷延遲設定過高
4. **Tap 介面問題** - Proxmox tap 介面配置問題

---

## 診斷步驟

### 1. 執行自動診斷腳本

在您的工作站上執行：

```bash
cd /Users/zoe/Documents/github/detectviz-gitops
./scripts/diagnose-vm1-network.sh
```

### 2. Proxmox 端手動診斷

SSH 登入到 Proxmox 主機，執行以下命令：

```bash
# 檢查 vm-1 的網卡配置（假設 vm-1 的 ID 是 111）
qm config 111 | grep net

# 檢查 vmbr0 bridge 配置
cat /etc/network/interfaces | grep -A 10 vmbr0

# 檢查 STP 狀態
brctl show vmbr0
brctl showstp vmbr0

# 檢查 tap 介面
ip -s link show | grep -A 5 "tap.*111"
```

---

## 修復方案

### 方案 1：禁用 Bridge STP（推薦優先嘗試）

**如果 STP 啟用且不需要，建議禁用：**

在 Proxmox Shell 執行：

```bash
# 檢查 STP 狀態
brctl showstp vmbr0 | grep "STP enabled"

# 如果啟用，立即禁用
brctl stp vmbr0 off

# 永久禁用 - 編輯 /etc/network/interfaces
# 確認 vmbr0 配置中有 bridge-stp off
cat > /tmp/vmbr0-config.txt <<'EOF'
auto vmbr0
iface vmbr0 inet static
	address 192.168.0.2/24
	gateway 192.168.0.1
	bridge-ports enp4s0
	bridge-stp off
	bridge-fd 0
EOF

# 備份原配置
cp /etc/network/interfaces /etc/network/interfaces.backup

# 手動更新配置（請小心編輯）
nano /etc/network/interfaces

# 重啟網路服務
systemctl restart networking
```

**驗證：**
```bash
# 在工作站執行
ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.11 "ping -c 100 192.168.0.1 | grep -E 'icmp_seq|packet'"
```

---

### 方案 2：調整 VirtIO 網卡設定

**增加 VirtIO 隊列大小和調整參數：**

在 Proxmox Shell 執行：

```bash
# 停止 vm-1（請先確認沒有重要任務運行）
qm stop 111

# 更新網卡配置，增加隊列大小
# queues=4 表示使用 4 個隊列（多核心優化）
qm set 111 -net0 virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,queues=4

# 啟動 vm-1
qm start 111
```

**如果問題持續，嘗試調整更多參數：**

```bash
# 停止 vm-1
qm stop 111

# 使用更保守的設定
qm set 111 -net0 virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr0,queues=2,rate=1000

# 啟動並測試
qm start 111
```

---

### 方案 3：更換網卡模型為 E1000（最保守方案）

**如果 VirtIO 持續有問題，可以換用更穩定但性能稍低的 E1000：**

在 Proxmox Shell 執行：

```bash
# 記錄當前 MAC 地址
qm config 111 | grep net0

# 停止 vm-1
qm stop 111

# 更換為 E1000 網卡（保留相同 MAC 地址）
qm set 111 -net0 e1000=XX:XX:XX:XX:XX:XX,bridge=vmbr0

# 啟動 vm-1
qm start 111
```

**進入 vm-1 檢查網卡：**
```bash
ssh ubuntu@192.168.0.11
ip link show eth0
# 應該看到 link/ether 而不是 virtio
```

---

### 方案 4：調整 vm-1 系統層級網路參數

**在 vm-1 內部優化網路設定：**

SSH 到 vm-1：

```bash
ssh ubuntu@192.168.0.11
```

執行以下命令：

```bash
# 1. 調整網卡中斷合併參數
sudo ethtool -C eth0 rx-usecs 10 tx-usecs 10

# 2. 增加網路緩衝區
sudo ethtool -G eth0 rx 1024 tx 1024

# 3. 禁用 TCP offload（可能導致性能下降，但更穩定）
sudo ethtool -K eth0 tso off gso off

# 4. 永久化設定
sudo bash -c 'cat > /etc/systemd/system/network-tuning.service <<EOF
[Unit]
Description=Network Performance Tuning
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -C eth0 rx-usecs 10 tx-usecs 10
ExecStart=/usr/sbin/ethtool -G eth0 rx 1024 tx 1024
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl daemon-reload
sudo systemctl enable network-tuning.service
sudo systemctl start network-tuning.service
```

---

### 方案 5：檢查和修復 Proxmox 內核模組

**在 Proxmox 主機上：**

```bash
# 檢查 vhost_net 模組是否加載
lsmod | grep vhost

# 如果未加載，加載模組
modprobe vhost_net

# 永久加載
echo "vhost_net" >> /etc/modules

# 檢查模組參數
cat /sys/module/vhost_net/parameters/*
```

---

## 驗證修復

在工作站執行長時間網路測試：

```bash
# 方法 1: 使用 ping 測試（5 分鐘）
ssh ubuntu@192.168.0.11 "ping -c 300 -i 1 192.168.0.1" | tee vm1-ping-test.log

# 分析結果
grep "packet loss" vm1-ping-test.log

# 方法 2: 檢查是否有序列號跳躍
grep "icmp_seq" vm1-ping-test.log | awk '{print $5}' | cut -d= -f2 | awk 'NR>1{if($1-prev>1) print "Jump detected: " prev " -> " $1}{prev=$1}'

# 方法 3: 測試實際數據傳輸
ssh ubuntu@192.168.0.11 "dd if=/dev/zero bs=1M count=1000 | ssh ubuntu@192.168.0.1 'cat > /dev/null'" 2>&1 | grep -i copied
```

**成功標準：**
- ✅ 300 個 ping 封包，0% packet loss
- ✅ icmp_seq 連續無跳號
- ✅ 大數據傳輸穩定，無中斷

---

## 推薦修復順序

1. **先嘗試方案 1（禁用 STP）** - 最簡單，不影響 VM
2. **如果失敗，嘗試方案 4（vm-1 內部優化）** - 不需要停止 VM
3. **如果仍失敗，嘗試方案 2（VirtIO 調整）** - 需要重啟 VM
4. **最後考慮方案 3（更換 E1000）** - 最保守，會降低性能

---

## 後續監控

修復後，建議設置監控腳本：

```bash
# 創建監控腳本
cat > ~/monitor-vm1-network.sh <<'EOF'
#!/bin/bash
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    result=$(ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.11 "ping -c 10 -W 2 192.168.0.1 2>&1 | tail -2")
    echo "[$timestamp] $result"
    sleep 60
done
EOF

chmod +x ~/monitor-vm1-network.sh

# 後台運行監控
nohup ~/monitor-vm1-network.sh > vm1-network-monitor.log 2>&1 &
```

查看監控日誌：
```bash
tail -f vm1-network-monitor.log
```

---

## 故障排除

### 如果所有方案都失敗

1. **檢查 Proxmox 主機系統日誌：**
   ```bash
   journalctl -u pve-cluster -n 100
   dmesg | grep -i "vmbr0\|tap\|bridge"
   ```

2. **檢查硬體層級問題：**
   ```bash
   # 檢查實體網卡錯誤
   ip -s link show enp4s0
   ethtool -S enp4s0 | grep error
   ```

3. **考慮重建 vm-1：**
   - 備份 vm-1 的重要數據
   - 使用 Terraform 重新創建 vm-1
   - 使用不同的網卡模型（E1000）

---

## 更新文檔

修復成功後，請更新：
- [deploy-troubleshooting.md](../../deploy-troubleshooting.md)
- [issue.md](../../issue.md)

記錄：
- 採用的修復方案
- 修復前後的測試結果
- 任何特殊配置

---

## 參考資料

- [Proxmox VE Network Configuration](https://pve.proxmox.com/wiki/Network_Configuration)
- [VirtIO Network Performance](https://www.linux-kvm.org/page/Networking)
- [Bridge STP Configuration](https://wiki.linuxfoundation.org/networking/bridge)
