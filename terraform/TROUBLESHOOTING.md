# Terraform VM 部署故障排除

## SSH 無法連接問題

### 問題描述
使用 Terraform 部署的 VM 無法通過 SSH 連接。

### 根本原因

VM template 配置與 Terraform 配置不一致，導致以下問題：

1. **BIOS 模式不匹配**
   - **舊配置**: Template 使用預設 SeaBIOS
   - **Terraform 期望**: UEFI (ovmf)
   - **影響**: VM 可能無法正常啟動

2. **Cloud-init 儲存位置錯誤**
   - **舊配置**: `--ide2 local-lvm:cloudinit`
   - **正確配置**: `--ide2 local:cloudinit`
   - **原因**: `local-lvm` 不支援 snippets content type
   - **影響**: Cloud-init 無法注入網路配置和 SSH 金鑰

3. **磁碟儲存不一致**
   - **舊配置**: Template 磁碟在 `local-lvm`
   - **Terraform 期望**: 磁碟在 `nvme-vm`
   - **影響**: 效能不一致

4. **缺少 EFI 磁碟**
   - **問題**: UEFI 模式需要 EFI 磁碟
   - **解決**: 添加 `--efidisk0 nvme-vm:0,efitype=4m`

5. **SSH 金鑰參數錯誤**
   - **舊配置**: `--sshkey ~/.ssh/id_rsa.pub`
   - **正確配置**: `--sshkeys ~/.ssh/id_rsa.pub` (注意 sshkeys 有 's')

### 解決方案

#### 方案 A：重建 Template（推薦）

按照更新後的 `docs/infrastructure/02-proxmox/vm-template-creation.md` 重新建立 template：

```bash
# 1. 刪除舊 template
qm destroy 9000

# 2. 按照新文檔步驟建立 template
# 關鍵變更：
# - 使用 --bios ovmf
# - 添加 --efidisk0
# - 使用 nvme-vm storage
# - Cloud-init 使用 local:cloudinit
# - 使用 --sshkeys (複數)
```

#### 方案 B：修正現有 Template

如果不想重建，可以修正現有 template：

```bash
# 1. 將 template 轉回 VM
qm unlock 9000

# 2. 修改 BIOS 為 UEFI
qm set 9000 --bios ovmf

# 3. 添加 EFI 磁碟
qm set 9000 --efidisk0 nvme-vm:0,efitype=4m,pre-enrolled-keys=0

# 4. 修正 Cloud-init 位置
qm set 9000 --delete ide2
qm set 9000 --ide2 local:cloudinit

# 5. 重新設定 SSH 金鑰
qm set 9000 --sshkeys ~/.ssh/id_rsa.pub

# 6. 轉回 template
qm template 9000
```

### 驗證步驟

部署 VM 後驗證配置：

```bash
# 1. 檢查 VM 是否啟動
qm status 111

# 2. 檢查 QEMU Guest Agent 連接
qm guest exec 111 -- ip addr show

# 3. 透過 Proxmox 主機 SSH 測試（假設您在 Proxmox 主機上）
ssh ubuntu@192.168.0.11 'hostname'

# 4. 檢查 Cloud-init 日誌
ssh ubuntu@192.168.0.11 'sudo cat /var/log/cloud-init.log'
```

### 預防措施

1. **Template 驗證清單**：
   - [ ] BIOS 設為 ovmf
   - [ ] EFI 磁碟已創建
   - [ ] 磁碟在正確的 storage pool
   - [ ] Cloud-init 使用 `local:cloudinit`
   - [ ] QEMU Guest Agent 已安裝並運行
   - [ ] SSH 公鑰已正確注入

2. **測試 Template**：
   ```bash
   # Clone 測試 VM
   qm clone 9000 9999 --name test-vm --full true
   qm start 9999

   # 等待 30 秒後測試 SSH
   sleep 30
   ssh ubuntu@<VM_IP> 'echo Template works!'

   # 清理測試 VM
   qm stop 9999
   qm destroy 9999
   ```

### 相關文件
- [VM Template Creation Guide](../docs/infrastructure/02-proxmox/vm-template-creation.md)
- [Terraform Variables](./variables.tf)
- [Terraform Main Configuration](./main.tf)
