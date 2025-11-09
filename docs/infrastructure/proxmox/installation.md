# Proxmox VE 安裝指南

## 概述

本指南說明如何在 DetectViz 硬體環境中安裝和配置 Proxmox Virtual Environment (VE)。

## 安裝步驟

### 1. 準備安裝媒體
- 下載 Proxmox VE ISO（建議使用 8.4+ 版本）
- 將 ISO 寫入 USB 開機碟

### 2. BIOS 設置
進入 BIOS 設置，確認開機順序：
```bash
Boot Option #1 → USB Drive (安裝碟)
Boot Option #2 → proxmox (SATA SSD)
```

### 3. 安裝過程
1. 從 USB 開機
2. 選擇 "Install Proxmox VE"
3. 設定網路：IP `192.168.0.2/24`
4. 磁碟選擇：僅選 SATA SSD
5. 完成安裝並重啟

## 後續配置

安裝完成後，請繼續參考：
- [Proxmox 配置指南](configuration.md)
- [VM 管理指南](vm-management.md)