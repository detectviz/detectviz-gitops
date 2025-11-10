# Proxmox VE 配置指南

## 概述

本指南說明 Proxmox VE 的基本配置，包括網路、儲存和系統優化設置。

## 初始系統配置

### 系統更新

登入 Proxmox Web UI (https://192.168.0.2:8006) 後，首先更新系統：

```bash
# SSH 連接到 Proxmox 主機
ssh root@192.168.0.2
```

Proxmox 預設使用企業訂閱源，但我們使用免費版本：

```bash
# 編輯企業源配置
vi /etc/apt/sources.list.d/pve-enterprise.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise

# 編輯 Ceph 源配置
vi /etc/apt/sources.list.d/ceph.list
# 註解掉以下行：
# deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise
```

更新系統

```bash
apt update && apt upgrade -y
```

## 認證設置

### 建立 Terraform 專用角色、API Token

Terraform 需要專用的 Proxmox API 權限來管理資源。

```bash
# 在 Proxmox 節點上執行
ssh root@192.168.0.2

# 建立專用使用者（若已存在可略過）
pveum user add terraform-prov@pve --comment "Terraform Provisioner"

# 建立專用角色（依版本挑選指令）

# Proxmox 8.x：需額外加入 VM.Monitor 權限
pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Migrate VM.PowerMgmt SDN.Use"

# Proxmox 9.x
# pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

# 指派權限（可視需求限制在特定節點或資源樹狀）
pveum aclmod / -user terraform-prov@pve -role TerraformProv

# 建立 API Token（建議使用 token 取代密碼登入）
pveum user token add terraform-prov@pve terraform-token -comment "Detectviz IaC"

# ⚠️ 記下返回的 Token Secret（只顯示一次！）
```

### 配置 Terraform 認證

```bash
# 匯出 Token 環境變數（用於 Terraform 變數）
export TF_VAR_proxmox_api_token_id='terraform-prov@pve!terraform-token'
export TF_VAR_proxmox_api_token_secret='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# 或直接設定 Proxmox provider 環境變數
export PM_API_TOKEN_ID='terraform-prov@pve!terraform-token'
export PM_API_TOKEN_SECRET='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Proxmox 8.x 不會自動繼承使用者 (terraform-prov@pve) 的角色權限，需要另外手動授權
pveum aclmod / -token 'terraform-prov@pve!terraform-token' -role TerraformProv
```

### 驗證認證設置

```bash
# 1.確認 Token 有足夠權限
pveum user permissions terraform-prov@pve

# 2.嘗試用 curl 測試 API
curl -k -H 'Authorization: PVEAPIToken=terraform-prov@pve!terraform-token='$PM_API_TOKEN_SECRET \
https://192.168.0.2:8006/api2/json/access/users

# 如果無回應，重新建立憑證並重新載入 proxy
systemctl restart pvedaemon pveproxy pve-cluster
```

> **權限清單說明**: 權限清單請與 Terraform provider 官方文檔保持一致，升級 Proxmox 時僅需依官方建議增減條目即可。


## 網路配置

### Bridge 設置

Proxmox 使用 Linux Bridge 提供網路連接。詳見：[網路配置指南](../networking/bridge-config.md)

### DNS 配置

Proxmox 主機應使用內部 DNS 伺服器。詳見：[DNS 設置指南](../networking/dns-setup.md)

## 儲存配置

### 儲存架構

DetectViz 使用混合儲存架構：
- 系統層：SATA SSD (Acer RE100 512GB)
- 高效層：NVMe SSD (TEAM MP44 2TB)

詳見：[儲存架構指南](../storage/storage-architecture.md)

### 儲存池設置

詳見：[儲存設置指南](../storage/storage-setup.md)

## 網路優化

### rp_filter 設置

解決 KVM/Bridge/Tap 網路封包遺失問題。詳見：[網路優化指南](../networking/network-optimization.md)

## 系統優化

### 時間同步

確保系統時間同步：

```bash
# 安裝 chrony
apt install chrony -y

# 檢查時間同步狀態
chronyc tracking
```

### 防火牆設置

Proxmox 預設啟用防火牆，根據需要配置：

```bash
# 檢查防火牆狀態
pve-firewall status

# Web UI 配置：Datacenter → Firewall
```

## 監控和維護

### 訂閱狀態

雖然使用免費版本，但建議監控訂閱狀態：

```bash
# 檢查訂閱狀態
pveversion --verbose
```

### 日誌管理

```bash
# 查看系統日誌
journalctl -u pve-cluster

# 查看 VM 日誌
tail -f /var/log/pve/tasks/
```

## 下一步

配置完成後，請參考：
- [VM 管理指南](vm-management.md) - 虛擬機創建和管理
- [Terraform 配置](../../terraform/README.md) - 自動化 VM 部署
