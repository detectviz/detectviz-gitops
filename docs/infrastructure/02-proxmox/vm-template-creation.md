# Ubuntu Cloud Image 模板製作

## 綁定 KVM 資源確認

- Bridge：`vmbr0`, Model：`virtio`

## 準備工作
```bash
# 1. 下載 Ubuntu 22.04 Cloud Image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

## 建立 VM 模板

### 第一階段：建立基礎 VM
```bash
# 2. 建立 VM（暫不轉為模板）
# 重要：使用 BIOS ovmf (UEFI) 以與 Terraform 配置一致
qm create 9000 --name ubuntu-2204-template --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --bios ovmf

# 3. 新增 EFI 磁碟（UEFI 必需）
qm set 9000 --efidisk0 nvme-vm:0,efitype=4m,pre-enrolled-keys=0

# 4. 匯入 Cloud Image 磁碟到儲存池（使用 nvme-vm，與 Terraform 一致）
qm importdisk 9000 jammy-server-cloudimg-amd64.img nvme-vm

# 5. 設定磁碟與開機順序
qm set 9000 --scsihw virtio-scsi-pci --scsi0 nvme-vm:vm-9000-disk-0
qm set 9000 --boot order=scsi0

# 6. 調整磁碟大小並啟用 discard（重要：讓 clone 的 VM 能調整大小）
qm disk resize 9000 scsi0 10G
qm set 9000 --scsi0 nvme-vm:vm-9000-disk-0,discard=on

# 7. 新增 Cloud-init 裝置（使用 local storage 存放 snippets）
qm set 9000 --ide2 local:cloudinit

# 8. 啟用序列主控台（Terraform 與 Cloud-init 監控需要）
qm set 9000 --serial0 socket --vga serial0

# 9. 啟用 QEMU Guest Agent（必須，Terraform 需要此功能）
qm set 9000 --agent enabled=1

# 10. 設定 cloud-init 預設登入帳號與 SSH 金鑰
# 確保此金鑰與 Terraform 設定中使用的 key 完全一致
# 確保 --ciuser 與 Terraform 變數 vm_user 一致，例如 "ubuntu"
qm set 9000 --ciuser ubuntu --sshkeys ~/.ssh/id_rsa.pub
```

### 第二階段：安裝 QEMU Guest Agent（必須）
```bash
# 11. 啟動 VM 進行軟體安裝
qm start 9000

# 12. 等待 VM 啟動完成（約 30-60 秒）
# 透過 Proxmox Web Console 或 SSH 連線到 VM

# 13. 安裝 QEMU Guest Agent
sudo apt update
sudo apt install -y cloud-init
sudo apt install -y qemu-guest-agent

# 14. 啟用並啟動 QEMU Guest Agent 服務
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent

# 15. 驗證 Agent 運行狀態
sudo systemctl status qemu-guest-agent

# 16. 清理系統（可選但建議）
sudo apt clean
sudo cloud-init clean --logs --seed

# 17. 關閉 VM
sudo shutdown -h now
```

### 第三階段：轉換為模板
```bash
# 18. 等待 VM 完全關閉後，轉為模板
qm template 9000

# 19. 驗證模板已建立
pvesh get /cluster/resources --type vm | grep ubuntu-2204-template
```

## 從模板建立 VM
```bash
# 從模板建立可啟動 VM
qm clone 9000 9100 --name ubuntu-2204-test --full true
```

> **重要注意事項**:
> - **QEMU Guest Agent 必須安裝**：Terraform 配置中已啟用 `agent.enabled = true`，缺少此套件會導致 Proxmox 無法獲取 VM IP 地址和執行優雅關機
> - **Cloud-init 裝置必須存在**：`ide2` 裝置用於注入使用者、SSH key 和網路設定，缺少會導致 Terraform 無法配置 VM
> - **使用者名稱一致性**：`--ciuser` 必須與 Terraform 變數 `vm_user` 相同（預設為 `ubuntu`）
> - **SSH 金鑰一致性**：模板中的 SSH 公鑰必須與 Terraform `ssh_public_key` 對應的私鑰配對
> - **清理 Cloud-init**：執行 `cloud-init clean` 可確保每個從模板複製的 VM 都有唯一的 instance-id
> - **cicustom 衝突**：如果原模板已設定 cicustom，請執行 `qm set 9000 --delete cicustom` 以避免衝突

## QEMU Guest Agent 功能說明

安裝 QEMU Guest Agent 後，Proxmox 可以：
- **自動偵測 IP 地址**：在 Proxmox Web UI 中顯示 VM 的 IP 地址
- **優雅關機**：執行 `qm shutdown` 時透過 Guest Agent 正常關機，而非強制斷電
- **時間同步**：確保 VM 與 Host 時間一致
- **檔案系統凍結**：支援一致性快照（snapshot）

這些功能對 Terraform 自動化部署和 Kubernetes 集群管理至關重要。