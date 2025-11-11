# Proxmox VE 初始系統配置

## 概述

本指南說明 Proxmox VE 的基本配置，包括網路、儲存和系統優化設置。

## 初始系統配置

### 系統更新

登入 Proxmox Web UI (https://192.168.0.2:8006) 後，首先更新系統：

```bash
# SSH 連接到 Proxmox 主機
ssh root@192.168.0.2
```

Proxmox 預設使用企業訂閱源，但我們使用免費版本：

```bash
# 編輯企業源配置
vi /etc/apt/sources.list.d/pve-enterprise.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise

# 編輯 Ceph 源配置
vi /etc/apt/sources.list.d/ceph.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
```

更新系統

```bash
apt update && apt upgrade -y
```