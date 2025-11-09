# Proxmox Bridge 配置指南

## 概述

本指南說明如何在 Proxmox VE 中配置 Linux Bridge。

## Bridge 配置

### vmbr0 設置
```bash
auto vmbr0
iface vmbr0 inet static
    address 192.168.0.2/24
    gateway 192.168.0.1
    bridge-ports enp4s0
    bridge-stp off
    bridge-fd 0
```

### VM 網路配置
- **Bridge**：vmbr0
- **Model**：VirtIO
- **Firewall**：啟用

## 測試驗證

```bash
# 測試網路連線
ping 192.168.0.1
ping 8.8.8.8
```

## 相關文檔

- [DNS 設置指南](dns-setup.md)
- [網路優化指南](network-optimization.md)