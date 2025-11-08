# Proxmox Terraform 認證設定

---

## 建立 Terraform 專用角色、API Token
> 同步 references/terraform-provider-proxmox/README.md

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

# 匯出 Token 環境變數（用於 Terraform 變數）
export TF_VAR_proxmox_api_token_id='terraform-prov@pve!terraform-token'
export TF_VAR_proxmox_api_token_secret='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# 或直接設定 Proxmox provider 環境變數
export PM_API_TOKEN_ID='terraform-prov@pve!terraform-token'
export PM_API_TOKEN_SECRET='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

# Proxmox 8.x 不會自動繼承使用者 (terraform-prov@pve) 的角色權限，需要另外手動授權。
pveum aclmod / -token 'terraform-prov@pve!terraform-token' -role TerraformProv

# ========== 驗證 ==========

# 1.確認 Token 有足夠權限
pveum user permissions terraform-prov@pve

# 2.嘗試用 curl 測試 API
curl -k -H 'Authorization: PVEAPIToken=terraform-prov@pve!terraform-token='$PM_API_TOKEN_SECRET \
https://192.168.0.2:8006/api2/json/access/users

# 如果無回應，重新建立憑證並重新載入 proxy
systemctl restart pvedaemon pveproxy pve-cluster
```
> 對應 `terraform.tfvars` 中的 Token ID 和 Secret
> 權限清單請與 `references/terraform-provider-proxmox/README.md` 保持一致，升級 Proxmox 時僅需依官方建議增減條目即可。
