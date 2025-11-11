# BIOS 和硬體配置指南

## 概述

本指南說明 ASMB10-iKVM 系統的 BIOS 配置和硬體初始化設置。

## 進入 BIOS

### 開機時進入 BIOS
1. 系統啟動時按 `DEL` 或 `F2` 鍵
2. 或從 IPMI Web 介面選擇 "Launch Virtual Console"

### IPMI 遠端進入
1. 登入 IPMI Web UI (https://192.168.0.4)
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

#### 儲存配置
- **SATA Mode**：AHCI
- **NVMe**：Enableds