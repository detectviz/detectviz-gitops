# DetectViz 硬體規格說明

## 目錄

- [系統總覽](#系統總覽)
- [主要硬體規格](#主要硬體規格)
  - [處理器 (CPU)](#處理器-cpu)
  - [記憶體 (RAM)](#記憶體-ram)
  - [儲存系統](#儲存系統)
  - [網路介面](#網路介面)
- [IPMI/KVM 管理](#ipmikvm-管理)
  - [管理介面規格](#管理介面規格)
- [硬體初始化檢查](#硬體初始化檢查)
  - [CPU 資訊驗證](#cpu-資訊驗證)
  - [記憶體驗證](#記憶體驗證)
  - [儲存設備檢查](#儲存設備檢查)
- [網路介面配置](#網路介面配置)
  - [實體網路介面](#實體網路介面)
- [系統啟動測試](#系統啟動測試)
  - [基本功能測試](#基本功能測試)
  - [硬體健康檢查](#硬體健康檢查)

---

## 系統總覽

DetectViz 平臺採用 ASMB10-iKVM 工業級伺服器，提供高可用性的 Kubernetes 集群運行環境。

## 主要硬體規格

### 處理器 (CPU)
- **型號**：Intel(R) Core(TM) i7-14700F
- **核心數量**：20 核心
- **邏輯處理器**：28 個 (支援超線程)
- **基礎頻率**：2.1 GHz
- **睿頻**：5.4 GHz
- **快取**：33MB Intel Smart Cache

### 記憶體 (RAM)
- **容量**：64 GB (32GB × 2)
- **型號**：D5-6000
- **類型**：DDR5
- **頻率**：6000 MT/s
- **時序**：CL30
- **ECC 支持**：是 (工業級)

### 儲存系統

#### 主系統碟 (SATA SSD)
- **型號**：Acer SSD RE100
- **容量**：512 GB
- **介面**：SATA 6Gb/s
- **讀取速度**：562 MB/s
- **寫入速度**：529 MB/s
- **用途**：Proxmox 系統安裝

#### 高性能資料碟 (NVMe SSD)
- **型號**：TEAM MP44
- **容量**：2 TB
- **介面**：PCIe Gen4
- **讀取速度**：7400 MB/s
- **寫入速度**：7000 MB/s
- **用途**：VM 儲存、資料庫、AI 模型

### 網路介面
- **晶片組**：Intel I210-AT
- **介面數量**：3 個 Gigabit Ethernet
- **主要用途**：
  - `enp4s0`：Proxmox 主管理網路 (vmbr0)
  - `enp5s0`：預留擴展網路
  - `enx36fe0bfce7d0`：預留擴展網路

## IPMI/KVM 管理

### 管理介面規格
- **型號**：ASMB10-iKVM
- **網路**：專用管理網路 (192.168.0.4)
- **支援協議**：
  - IPMI 2.0
  - KVM-over-IP
  - Virtual Media
  - Serial-over-LAN


## 硬體初始化檢查

### CPU 資訊驗證
```bash
# 系統啟動後檢查
cat /proc/cpuinfo | grep -E "processor|model name|cpu cores"

# 預期輸出：
# Intel(R) Core(TM) i7-14700F
# 20 核心, 28 邏輯處理器
```

### 記憶體驗證
```bash
# 檢查記憶體
dmidecode -t memory | grep -E "Size|Type|Speed"

# 預期輸出：
# Size: 32768 MB
# Type: DDR5
# Speed: 6000 MT/s
```

### 儲存設備檢查
```bash
# 檢查磁碟
lsblk -d

# 預期輸出：
# sda      8:0    0 476.9G  0 disk  # Acer RE100 SATA SSD
# nvme0n1 259:0   0   1.8T  0 disk  # TEAM MP44 NVMe SSD
```

## 網路介面配置

### 實體網路介面
```bash
# 檢查網路介面
ip link show

# 預期輸出：
# enp4s0: 主網路介面
# enp5s0: 預留介面
# enx36fe0bfce7d0: 預留介面
```

## 系統啟動測試

### 基本功能測試
```bash
# 測試網路連線
ping -c 3 192.168.0.1

# 測試 DNS 解析
nslookup google.com

# 測試儲存 I/O
dd if=/dev/zero of=/tmp/testfile bs=1M count=100 && rm /tmp/testfile
```

### 硬體健康檢查
```bash
# 檢查系統日誌
dmesg | grep -i error

# 檢查硬體狀態
ipmitool sdr list
```
