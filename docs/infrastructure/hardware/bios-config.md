# BIOS 和硬體配置指南

## 概述

本指南說明 ASMB10-iKVM 系統的 BIOS 配置和硬體初始化設置。

## 進入 BIOS

### 開機時進入 BIOS
1. 系統啟動時按 `DEL` 或 `F2` 鍵
2. 或從 IPMI Web 介面選擇 "Launch Virtual Console"

### IPMI 遠端進入
1. 登入 IPMI Web UI (https://192.168.0.104)
2. 選擇 **Remote Control** → **Launch Virtual Console**
3. 在虛擬控制台中按 BIOS 進入鍵

## BIOS 主要設置

### 開機順序 (Boot)

#### 正常運行時
```bash
Boot Option #1 → proxmox (SATA6G_4: Acer SSD RE100 512GB)
Boot Option #2 → UEFI OS
Boot Option #3 → UEFI: AMI Virtual CDROM0 1.00 Partition 1
```

#### 安裝 Proxmox 時
```bash
Boot Option #1 → USB Drive (安裝碟)
Boot Option #2 → proxmox (SATA SSD)
```

> **重要**：安裝前請移除 NVMe 項目的開機選項，確保系統由 SATA SSD 啟動。

### 安全設置 (Security)

#### Secure Boot
- **Secure Boot Mode**：`Custom`
- **OS Type**：`Other OS`

#### TPM 設置
- **TPM Device**：根據需求啟用
- **TPM Version**：2.0 (建議)

### 進階設置 (Advanced)

#### CPU 配置
- **Hyper-Threading**：Enabled (啟用超線程)
- **Intel Virtualization Technology**：Enabled (必須啟用)
- **Intel VT-d**：Enabled (IOMMU 支持)

#### 記憶體配置
- **XMP Profile**：Profile 1 (DDR5-6000)
- **Memory Remap**：Enabled

#### 儲存配置
- **SATA Mode**：AHCI
- **NVMe**：Enabled

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

### IPMI 網路設置
- 詳見：[IPMI 設置指南](ipmi-setup.md)

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

## 故障排除

### 無法進入 BIOS
- 確認按鍵時機 (系統啟動初期)
- 檢查鍵盤連線
- 使用 IPMI 遠端控制台

### 開機失敗
- 檢查開機順序設置
- 驗證儲存設備狀態
- 確認電源供應穩定

### 硬體偵測問題
- 重置 BIOS 為預設值
- 檢查硬體連接
- 聯絡硬體支援

## 維護建議

### 定期檢查
- BIOS 版本更新
- 硬體健康狀態
- 系統日誌異常

### 備份設置
- 記錄 BIOS 配置
- 備份自訂設置
- 文件化變更

## 相關文檔

- [IPMI/KVM 管理設置](ipmi-setup.md)
- [硬體規格說明](hardware-specs.md)
- [Proxmox 安裝指南](proxmox/installation.md)
