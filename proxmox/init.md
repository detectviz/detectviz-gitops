# Proxmox 設置

## 安裝步驟

### 安裝 Proxmox VE
- 下載最新版 ISO（proxmox-ve_8.4-1.iso）。
- 安裝時選擇 「自訂 (Advanced) 安裝」。
- 磁碟選擇：僅選 SATA SSD (Acer RE100)。

#### BIOS 開機順序
```bash
Boot Option #1 → proxmox (SATA6G_4: Acer SSD RE100 512GB)
```
> 請於 BIOS 中移除 NVMe 項目，確保系統由 SATA SSD 啟動。

## 註解 Proxmox 企業訂閱源
```bash
root@proxmox:/etc/apt/sources.list.d# cat pve-enterprise.list
#deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise
root@proxmox:/etc/apt/sources.list.d# cat ceph.list
#deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
```

## VM 後續配置

### 安裝 QEMU Guest Agent

QEMU Guest Agent 提供 VM 內部資訊給 Proxmox 主機，提升管理效能和監控能力。

#### 1. 在 VM 中安裝 qemu-guest-agent
```bash
sudo apt-get update
sudo apt-get install qemu-guest-agent
```

#### 2. 啟動並設定開機自動啟動
```bash
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent
```

#### 3. 檢查服務狀態
```bash
sudo systemctl status qemu-guest-agent
```

> **注意：** 安裝完成後，建議重新啟動 VM 以確保 agent 正確載入。

### Proxmox Web UI 驗證

安裝 QEMU Guest Agent 後，在 Proxmox Web UI 的 VM 摘要頁面會顯示更多系統資訊，包括：
- 精確的 CPU 使用率
- 記憶體使用詳情
- 網路流量統計
- 磁碟 I/O 資訊
