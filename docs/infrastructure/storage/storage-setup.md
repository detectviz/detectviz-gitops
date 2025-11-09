# 儲存設置指南

## 概述

本指南說明如何在 Proxmox VE 中設置和配置 DetectViz 的混合儲存架構。

## 前置準備

### 硬體檢查
```bash
# 檢查磁碟設備
lsblk -d

# 預期輸出：
# sda      8:0    0 476.9G  0 disk  # Acer RE100 SATA SSD
# nvme0n1 259:0   0   1.8T  0 disk  # TEAM MP44 NVMe SSD

# 檢查磁碟健康狀態
smartctl -a /dev/sda
smartctl -a /dev/nvme0n1
```

### 備份重要資料
```bash
# 備份現有配置
cp /etc/pve/storage.cfg /etc/pve/storage.cfg.backup
```

## Proxmox 儲存設置

### 1. SATA SSD 配置 (系統儲存)

#### 檢查預設配置
Proxmox 安裝時通常會自動配置 SATA SSD 作為 `local` 儲存。

```bash
# 檢查現有儲存配置
cat /etc/pve/storage.cfg

# 預期內容：
# dir: local
#         path /var/lib/vz
#         content iso,vztmpl,backup
```

#### 配置本地 LVM 儲存
```bash
# 檢查 LVM 配置
pvs
vgs
lvs

# 創建 VM 儲存目錄 (如果不存在)
mkdir -p /var/lib/vz
```

### 2. NVMe SSD 配置 (高效能儲存)

#### 創建 Volume Group
```bash
# 初始化實體卷
pvcreate /dev/nvme0n1

# 創建卷組
vgcreate nvme-vg /dev/nvme0n1

# 檢查卷組
vgdisplay nvme-vg
```

#### 配置 LVM-Thin Pool
```bash
# 創建 Thin Pool (使用全部空間的 95%，保留 5% 給 metadata)
lvcreate -l 95%FREE -T nvme-vg/nvme-thin-pool

# 檢查 Thin Pool
lvdisplay nvme-vg/nvme-thin-pool
```

### 3. Proxmox Web UI 儲存配置

#### 添加 NVMe 儲存
1. 登入 Proxmox Web UI (https://192.168.0.2:8006)
2. 前往 **Datacenter** → **Storage**
3. 點擊 **Add** → **LVM-Thin**

#### 配置參數
```
ID: nvme-vm
Volume Group: nvme-vg
Thin Pool: nvme-thin-pool
Content: Disk image, Container
Enabled: Yes
```

#### 驗證儲存配置
```bash
# 檢查 Proxmox 儲存配置
cat /etc/pve/storage.cfg

# 預期新增內容：
# lvmthin: nvme-vm
#         thinpool nvme-thin-pool
#         vgname nvme-vg
#         content images,rootdir
```

## 儲存最佳化配置

### I/O 調優
```bash
# NVMe I/O 調優
cat << EOF > /etc/udev/rules.d/60-nvme-io-optimization.rules
ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/add_random}="0"
ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/nr_requests}="1024"
EOF

# 重新載入 udev 規則
udevadm control --reload-rules
udevadm trigger
```

### EXT4 檔案系統優化
```bash
# 檢查檔案系統掛載選項
mount | grep ext4

# 如果需要重新掛載優化選項
mount -o remount,noatime,nodiratime /dev/mapper/nvme--vg-nvme--thin--pool
```

## 儲存測試

### 效能測試
```bash
# 安裝測試工具
apt install fio -y

# NVMe 讀寫測試
fio --name=randwrite --rw=randwrite --bs=4k --size=1g --numjobs=4 --runtime=60 --directory=/mnt/nvme-test

# SATA 讀寫測試
fio --name=randwrite --rw=randwrite --bs=4k --size=500m --numjobs=2 --runtime=30 --directory=/var/lib/vz
```

### 容量測試
```bash
# 檢查儲存容量
df -h

# 檢查 LVM 容量
vgdisplay nvme-vg
lvdisplay nvme-vg/nvme-thin-pool
```

## VM 儲存配置

### 新建 VM 時的儲存選擇
1. **系統碟**：選擇 `nvme-vm` 作為高效能儲存
2. **格式**：Raw (效能最佳) 或 Qcow2 (靈活性)
3. **快取**：Write back (平衡效能和安全性)

### 儲存遷移
```bash
# 將現有 VM 遷移到 NVMe 儲存
qm move_disk <vmid> <disk> nvme-vm --delete=1
```

## 備份儲存配置

### 配置備份儲存
```bash
# 在 SATA SSD 上創建備份目錄
mkdir -p /mnt/sata-backup

# 添加備份儲存到 Proxmox
pvesm add dir backup-sata --path /mnt/sata-backup --content backup
```

### 備份策略配置
1. 前往 **Datacenter** → **Backup**
2. 創建新的備份任務
3. 選擇儲存：`backup-sata`
4. 設定排程：每日凌晨 2:00
5. 保留策略：保留 7 個每日備份

## 監控和維護

### 儲存監控
```bash
# 儲存使用率
pvesm df

# 磁碟 I/O 統計
iostat -x 1

# LVM 統計
lvs -a
```

### 健康檢查
```bash
# 檔案系統檢查
fsck -n /dev/mapper/pve-root

# SMART 健康檢查
smartctl -H /dev/sda
smartctl -H /dev/nvme0n1
```

### 定期維護
```bash
# 清理未使用的 Thin Volume
lvremove -f nvme-vg/unused-volume

# 整理 Thin Pool
lvconvert --merge nvme-vg/nvme-thin-pool
```

## 故障排除

### 常見問題

#### 儲存空間不足
```bash
# 檢查使用情況
df -h
lvs

# 擴展 Thin Pool (如果有額外空間)
lvextend -l +100%FREE nvme-vg/nvme-thin-pool
```

#### I/O 性能問題
```bash
# 檢查 I/O 調度器
cat /sys/block/nvme0n1/queue/scheduler

# 檢查隊列深度
cat /sys/block/nvme0n1/queue/nr_requests
```

#### 儲存連接問題
```bash
# 檢查磁碟狀態
dmesg | grep -i nvme
dmesg | grep -i sata

# 重新掃描 SCSI 設備
rescan-scsi-bus.sh
```

## 安全配置

### 存取權限
```bash
# 檢查儲存目錄權限
ls -la /var/lib/vz
ls -la /mnt/sata-backup

# 設定適當權限
chown root:www-data /mnt/sata-backup
chmod 750 /mnt/sata-backup
```

### 加密考慮
```bash
# LUKS 加密 (可選)
cryptsetup luksFormat /dev/nvme0n1
cryptsetup luksOpen /dev/nvme0n1 nvme-encrypted
```

## 相關文檔

- [儲存架構設計](storage-architecture.md)
- [Proxmox 配置指南](../proxmox/configuration.md)
- [硬體規格說明](../hardware/hardware-specs.md)
