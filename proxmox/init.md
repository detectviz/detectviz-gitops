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
