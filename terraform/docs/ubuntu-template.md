# Proxmox Ubuntu Cloud Image 模板

---

## 製作 Ubuntu Cloud Image 模板
```bash
# 1. 下載 Ubuntu 22.04 Cloud Image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

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

# 7. 啟用 QEMU Guest Agent（可選，供 Terraform 判斷 VM 狀態）
# 注意：DetectViz 部署腳本選擇不在 Ansible 中安裝 QEMU Guest Agent
# 如果需要更好的 Terraform 兼容性，可以在模板中預安裝
# qm set 9000 --agent enabled=1,fstrim_cloned_disks=1

# 7.1 安裝 QEMU Guest Agent（可選，建議於模板內完成）
# 提供 Terraform 與 Proxmox 正確的 VM 狀態與網路資訊回報
# 若需要安裝，請啟動臨時 VM 執行：
# sudo apt update && sudo apt install -y qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent

# 8. 設定 cloud-init 預設登入帳號與 SSH 金鑰
# 確保此金鑰與 Terraform 設定中使用的 key 完全一致
# 確保 --ciuser 與 Terraform 變數 vm_user 一致，例如 "ubuntu"。
# 若未設定使用者名稱，Terraform 會出現 "user name not set" 錯誤。
qm set 9000 --ciuser ubuntu --sshkey ~/.ssh/id_rsa.pub

# 9. 設定 Cloud-init 使用內建 NoCloud datasource（不依賴 snippets）
# Cloud-init 會自動產生網路與使用者設定，不需指定 meta-data.yml 或 network-config.yml
qm set 9000 --boot c --bootdisk scsi0

# 10. 確保序列主控台支援 qm terminal / Web Console 登入
qm set 9000 --serial0 socket --vga serial0

# 11. 設定模板為永久模板
qm template 9000

# 12. 驗證
pvesh get /cluster/resources --type vm | grep ubuntu-2204-template
```

> 注意：
> - Cloud-init 裝置 (`ide2`) 必須存在，否則 Terraform 無法注入使用者、SSH key 或網路設定。
> - `--ciuser` 與 Terraform 中的 `vm_user` 需相同（例如 `ubuntu`）。
> - 模板 SSH 公鑰與 Terraform `ssh_public_key` 對應的私鑰必須一致。
> - 若需使用 Proxmox Web Console 檢視，請保留 `serial0` 設定。
> ⚠️ 若原模板已設定 cicustom 或 ide2 指向 local:snippets，請執行：
> qm set 9000 --delete cicustom
> qm set 9000 --ide2 local-lvm:cloudinit
> 以免 Terraform 執行時出現 `volume 'local:snippets/network-config.yml' does not exist` 錯誤。

### 常用指令

1. **從模板建立可啟動 VM**
```bash
qm clone 9000 9100 --name ubuntu-2204-qga --full true
```
- `9000`：來源模板 VM ID
- `9100`：新 VM ID，可自訂
- `--full true`：建立完整複本（非連結 clone）

### 常見錯誤排查

1. **QEMU Guest Agent timeout**
   - 錯誤訊息：
     ```
     Warning: error waiting for network interfaces from QEMU agent
     timeout while waiting for the QEMU agent on VM to publish the network interfaces
     ```
   - 原因：模板未安裝或未啟動 qemu-guest-agent。
   - 解法：
     ```
     sudo apt install -y qemu-guest-agent
     sudo systemctl enable --now qemu-guest-agent
     ```

2. **user name not set**
   - 錯誤訊息：
     ```
     received an HTTP 500 response - Reason: user name not set
     ```
   - 原因：Cloud-init 未設 ciuser。
   - 解法：
     ```
     qm set 9000 --ciuser ubuntu
     ```
