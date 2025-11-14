# EFI Disk 配置修正

**日期**: 2025-11-13
**問題**: VM 啟動失敗 - storage 'local' does not support content-type 'images'
**狀態**: ✅ 已修正

---

## 🔴 問題描述

### 錯誤訊息

```
Error: error waiting for VM start: task "UPID:proxmox:0001661C:001F103F:69148263:qmstart:112:terraform-prov@pve!terraform-token:" failed to complete with exit code: storage 'local' does not support content-type 'images'

  with proxmox_virtual_environment_vm.k8s_masters[1],
  on main.tf line 32, in resource "proxmox_virtual_environment_vm" "k8s_masters":
  32: resource "proxmox_virtual_environment_vm" "k8s_masters" {
```

### 根本原因

1. **UEFI BIOS 需要 EFI disk**: VM 配置使用 `bios = "ovmf"` (UEFI 模式)，需要 EFI disk 來存儲 UEFI 固件
2. **缺少明確的 efi_disk 配置**: Terraform 配置中沒有明確指定 `efi_disk` 區塊
3. **默認使用 local storage**: Proxmox 默認嘗試將 EFI disk 放在 `local` storage
4. **local storage 不支持 images**: `local` storage 只支持 `vztmpl`, `iso`, `backup` 等 content types，不支持 `images`

**為什麼會這樣？**

- UEFI BIOS 的 VM 需要一個特殊的 EFI disk 來存儲 UEFI 變數和引導信息
- 如果沒有明確指定 `efi_disk` 配置，Proxmox provider 會嘗試自動創建
- 但自動創建時會使用默認的 storage（通常是 `local`）
- `local` storage 通常配置為僅支持 ISO、模板等，不支持 VM 磁碟鏡像

---

## ✅ 解決方案

### 修正文件

**文件**: `terraform/main.tf`

### 修正內容 - Master 節點

在 master 節點的 disk 配置後添加 `efi_disk` 區塊 (Line 73-80):

```hcl
  # 磁碟配置
  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = parseint(replace(var.master_disk_size, "G", ""), 10)
    file_format  = "raw"
    replicate    = false # 單節點 Proxmox 環境不支援磁碟複製
  }

  # EFI 磁碟配置 (UEFI BIOS 必需)
  # 必須明確指定 storage，否則會使用 local storage 導致錯誤
  efi_disk {
    datastore_id      = var.proxmox_storage # 使用與系統磁碟相同的 storage (nvme-vm)
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  # 雙網路配置
  network_device {
    ...
  }
```

### 修正內容 - Worker 節點

在 worker 節點的 disk 配置後添加 `efi_disk` 區塊 (Line 193-200):

```hcl
  # 額外資料磁碟配置 (scsi1+) - 供 TopoLVM 使用
  dynamic "disk" {
    for_each = try([var.worker_data_disks[count.index]], [])
    content {
      datastore_id = disk.value.storage
      interface    = "scsi1"
      size         = parseint(replace(disk.value.size, "G", ""), 10)
      file_format  = "raw"
      replicate    = false
    }
  }

  # EFI 磁碟配置 (UEFI BIOS 必需)
  # 必須明確指定 storage，否則會使用 local storage 導致錯誤
  efi_disk {
    datastore_id      = var.proxmox_storage # 使用與系統磁碟相同的 storage (nvme-vm)
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  # 雙網路配置
  network_device {
    ...
  }
```

### efi_disk 配置參數說明

| 參數 | 值 | 說明 |
|-----|-----|------|
| `datastore_id` | `var.proxmox_storage` (nvme-vm) | EFI disk 存儲位置，必須使用支持 `images` content type 的 storage |
| `file_format` | `raw` | 磁碟格式，raw 格式性能最佳 |
| `type` | `4m` | EFI disk 大小類型，4m = 4MB (標準 UEFI 變數存儲大小) |
| `pre_enrolled_keys` | `false` | 是否預先註冊安全啟動金鑰，false 表示不使用安全啟動 |

---

## 🔍 修正後的結果

### Terraform 部署成功

```
Plan: 4 to add, 0 to change, 4 to destroy.

proxmox_virtual_environment_vm.k8s_masters[0]: Creating...
proxmox_virtual_environment_vm.k8s_masters[1]: Creating...
proxmox_virtual_environment_vm.k8s_masters[2]: Creating...
proxmox_virtual_environment_vm.k8s_workers[0]: Creating...

proxmox_virtual_environment_vm.k8s_masters[0]: Creation complete after 5m43s [id=111]
proxmox_virtual_environment_vm.k8s_masters[1]: Creation complete after 5m46s [id=112]
proxmox_virtual_environment_vm.k8s_masters[2]: Creation complete after 5m48s [id=113]
proxmox_virtual_environment_vm.k8s_workers[0]: Creation complete after 6m2s [id=114]

Apply complete! Resources: 4 added, 0 changed, 4 destroyed.
```

### VM 成功啟動

所有 VM 都成功創建和啟動：
- ✅ master-1 (VM ID: 111) - 192.168.0.11
- ✅ master-2 (VM ID: 112) - 192.168.0.12
- ✅ master-3 (VM ID: 113) - 192.168.0.13
- ✅ app-worker (VM ID: 114) - 192.168.0.14

---

## 📊 驗證方法

### 檢查 EFI disk 是否正確創建

在 Proxmox Web UI 中檢查 VM 配置：

```bash
# 在 Proxmox 節點上執行
qm config 111
```

**預期輸出** (應包含 efidisk0):
```
...
efidisk0: nvme-vm:vm-111-disk-0,efitype=4m,pre-enrolled-keys=0,size=4M
scsi0: nvme-vm:vm-111-disk-1,discard=on,iothread=0,size=100G
...
```

### 檢查 VM 是否正常啟動

```bash
# SSH 到 VM
ssh ubuntu@192.168.0.11

# 檢查系統信息
hostnamectl
```

---

## 🎯 為什麼需要明確指定 efi_disk？

### 問題背景

1. **UEFI 需求**: 使用 `bios = "ovmf"` 的 VM 必須有 EFI disk
2. **Provider 限制**: Terraform Proxmox provider 不會自動推斷正確的 storage
3. **Storage 限制**: 不是所有 storage 都支持所有 content types

### 最佳實踐

- ✅ **總是明確指定 efi_disk**: 使用 UEFI BIOS 時必須明確配置
- ✅ **使用相同的 storage**: EFI disk 與系統磁碟使用相同的 storage
- ✅ **驗證 storage 支持**: 確保 storage 支持 `images` content type
- ✅ **使用 raw 格式**: raw 格式提供最佳性能

---

## 🔄 對現有環境的影響

### 修正要求

因為 `efi_disk` 配置的變更會導致 VM 重建（forces replacement），所以：

1. ✅ Terraform 會自動銷毀舊的 VM
2. ✅ 然後創建新的 VM（包含正確的 EFI disk 配置）
3. ✅ 新 VM 的 SSH host keys 會改變
4. ✅ 需要清理本地 `~/.ssh/known_hosts`

### 修正步驟

```bash
# 1. 應用 Terraform 配置
cd /Users/zoe/Documents/github/detectviz-gitops/terraform
terraform apply -var-file=terraform.tfvars -auto-approve

# 2. 清理舊的 SSH host keys
ssh-keygen -R 192.168.0.11
ssh-keygen -R 192.168.0.12
ssh-keygen -R 192.168.0.13
ssh-keygen -R 192.168.0.14

# 3. 重新部署 Kubernetes 集群
cd /Users/zoe/Documents/github/detectviz-gitops/ansible
ansible-playbook -i inventory.ini deploy-cluster.yml
```

---

## ✅ 相關問題修正

### 問題 2: configure_lvm 變數未定義

**錯誤訊息**:
```
Error while evaluating conditional: 'configure_lvm' is undefined
Origin: /Users/zoe/Documents/github/detectviz-gitops/ansible/roles/worker/tasks/main.yml:15:9
```

**修正**: 在 `ansible/group_vars/all.yml` 添加變數定義:

```yaml
# ============================================
# 儲存配置變數 (Storage Configuration)
# ============================================
configure_lvm: true # 是否配置 LVM 邏輯卷管理，用於 TopoLVM 動態儲存
```

---

## 📚 相關文檔

- [Proxmox UEFI/OVMF Documentation](https://pve.proxmox.com/wiki/OVMF/UEFI_Boot_Entries)
- [Terraform Proxmox Provider - EFI Disk](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm#efi_disk)
- [Proxmox Storage Content Types](https://pve.proxmox.com/wiki/Storage)

---

## 📝 總結

**問題**: VM 啟動失敗，因為 EFI disk 嘗試使用不支持 `images` content type 的 `local` storage

**修正**: 在 Terraform 配置中明確添加 `efi_disk` 區塊，指定使用 `nvme-vm` storage

**結果**: ✅ 所有 VM 成功創建並啟動，包含正確的 EFI disk 配置

**額外修正**: ✅ 添加 `configure_lvm` 變數到 Ansible 配置

**部署狀態**: 🔄 Ansible 重新部署中，預計完成 worker 節點配置
