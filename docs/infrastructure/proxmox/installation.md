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

## Ubuntu Cloud Image 模板製作

### 準備工作
```bash
# 1. 下載 Ubuntu 22.04 Cloud Image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### 建立 VM 模板
```bash
# 2. 建立 VM 模板
qm create 9000 --name ubuntu-2204-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0

# 3. 匯入 Cloud Image 磁碟到儲存池（建議使用 local-lvm）
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm

# 4. 設定磁碟與開機順序
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --boot c --bootdisk scsi0

# 5. 新增 Cloud-init 裝置
qm set 9000 --ide2 local-lvm:cloudinit

# 6. 啟用序列主控台（Terraform 與 Cloud-init 監控需要）
qm set 9000 --serial0 socket --vga serial0

# 7. 設定 cloud-init 預設登入帳號與 SSH 金鑰
# 確保此金鑰與 Terraform 設定中使用的 key 完全一致
# 確保 --ciuser 與 Terraform 變數 vm_user 一致，例如 "ubuntu"
qm set 9000 --ciuser ubuntu --sshkey ~/.ssh/id_rsa.pub

# 8. 設定 Cloud-init 使用內建 NoCloud datasource（不依賴 snippets）
qm set 9000 --boot c --bootdisk scsi0

# 9. 設定模板為永久模板
qm template 9000
```

### 可選：安裝 QEMU Guest Agent
```bash
# 如果需要在模板中預安裝 QEMU Guest Agent：
# 啟動臨時 VM 並安裝
sudo apt update && sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
# 然後關閉 VM 並轉為模板
```

### 驗證模板
```bash
# 檢查模板是否正確建立
pvesh get /cluster/resources --type vm | grep ubuntu-2204-template
```

### 從模板建立 VM
```bash
# 從模板建立可啟動 VM
qm clone 9000 9100 --name ubuntu-2204-test --full true
```

> **重要注意事項**:
> - Cloud-init 裝置 (`ide2`) 必須存在，否則 Terraform 無法注入使用者、SSH key 或網路設定
> - `--ciuser` 與 Terraform 中的 `vm_user` 需相同（預設 `ubuntu`）
> - 模板 SSH 公鑰與 Terraform `ssh_public_key` 對應的私鑰必須一致
> - 如果原模板已設定 cicustom，請執行 `qm set 9000 --delete cicustom` 以避免衝突

### 常見錯誤排查

#### QEMU Guest Agent timeout
```
錯誤訊息：
Warning: error waiting for network interfaces from QEMU agent
timeout while waiting for the QEMU agent on VM to publish the network interfaces
```
**解決方案**：
```bash
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

#### user name not set
```
錯誤訊息：
received an HTTP 500 response - Reason: user name not set
```
**解決方案**：
```bash
qm set 9000 --ciuser ubuntu
```

## 後續配置

安裝完成後，請繼續參考：
- [Proxmox 配置指南](configuration.md)
- [VM 管理指南](vm-management.md)