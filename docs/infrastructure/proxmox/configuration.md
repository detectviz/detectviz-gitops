# Proxmox VE 配置指南

## 概述

本指南說明 Proxmox VE 的基本配置，包括網路、儲存和系統優化設置。

## 初始系統配置

### 1. 系統更新

登入 Proxmox Web UI (https://192.168.0.2:8006) 後，首先更新系統：

```bash
# SSH 連接到 Proxmox 主機
ssh root@192.168.0.2

# 更新系統
apt update && apt upgrade -y
```

### 2. 註解企業訂閱源

Proxmox 預設使用企業訂閱源，但我們使用免費版本：

```bash
# 編輯企業源配置
nano /etc/apt/sources.list.d/pve-enterprise.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise

# 編輯 Ceph 源配置
nano /etc/apt/sources.list.d/ceph.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
```

### 3. 添加免費倉庫

```bash
# 編輯 sources.list
nano /etc/apt/sources.list

# 添加以下行：
deb http://ftp.debian.org/debian bookworm main contrib
deb http://ftp.debian.org/debian bookworm-updates main contrib

# 重新載入套件列表
apt update
```

## 網路配置

### Bridge 設置

Proxmox 使用 Linux Bridge 提供網路連接。詳見：[網路配置指南](../networking/bridge-config.md)

### DNS 配置

Proxmox 主機應使用內部 DNS 伺服器。詳見：[DNS 設置指南](../networking/dns-setup.md)

## 儲存配置

### 儲存架構

DetectViz 使用混合儲存架構：
- 系統層：SATA SSD (Acer RE100 512GB)
- 高效層：NVMe SSD (TEAM MP44 2TB)

詳見：[儲存架構指南](../storage/storage-architecture.md)

### 儲存池設置

詳見：[儲存設置指南](../storage/storage-setup.md)

## 網路優化

### rp_filter 設置

解決 KVM/Bridge/Tap 網路封包遺失問題。詳見：[網路優化指南](../networking/network-optimization.md)

## 系統優化

### 時間同步

確保系統時間同步：

```bash
# 安裝 chrony
apt install chrony -y

# 檢查時間同步狀態
chronyc tracking
```

### 防火牆設置

Proxmox 預設啟用防火牆，根據需要配置：

```bash
# 檢查防火牆狀態
pve-firewall status

# Web UI 配置：Datacenter → Firewall
```

## 監控和維護

### 訂閱狀態

雖然使用免費版本，但建議監控訂閱狀態：

```bash
# 檢查訂閱狀態
pveversion --verbose
```

### 日誌管理

```bash
# 查看系統日誌
journalctl -u pve-cluster

# 查看 VM 日誌
tail -f /var/log/pve/tasks/
```

## 下一步

配置完成後，請參考：
- [VM 管理指南](vm-management.md) - 虛擬機創建和管理
- [Terraform 配置](../../terraform/README.md) - 自動化 VM 部署
