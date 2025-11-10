# Terraform 規格與最佳實踐指南

本文檔定義了 Detectviz 平台在使用 Terraform 管理 Proxmox 基礎設施時的技術規格與最佳實踐。

---

## 1. 平台規格 (Platform Specifications)

本節詳述在 Detectviz 環境中，Terraform 的具體設定與標準化流程。

### 1.1 Provider 組態

所有 Proxmox 資源的管理均透過 `hashicorp/proxmox` 提供者。標準組態如下：

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9.14" # 鎖定 provider 版本以確保一致性
    }
  }
}

provider "proxmox" {
  pm_api_url = var.proxmox_api_url # "https://192.168.0.2:8006/api2/json"

  # 優先使用 API Token 進行認證
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret

  # 開發或初始設定階段可接受自簽憑證
  pm_tls_insecure = true

  # 調試設定（疑難排除時才使用）
  # pm_log_enable = true
  # pm_log_levels = {
  #   _default = "debug"
  #   _capturelog = ""
  # }
  # pm_debug = true
}
```

**版本需求**：Terraform >= 1.5.0，於進入 Phase 0 前確認 `terraform --version`。

- **版本鎖定**：Provider 版本必須固定，避免因版本更新導致非預期的行為變更。
- **認證**：**必須**使用 Proxmox API Token 進行認證，禁止使用帳號密碼。相關變數應透過 `terraform.tfvars` 或環境變數傳入，不得硬編碼在 `.tf` 檔案中。

### 1.2 Proxmox 權限管理

Terraform 在 Proxmox 中的操作權限應遵循**最小權限原則**。

1.  **建立專用角色**：
    - 角色名稱：`TerraformProv`
    - 權限列表 (Proxmox 9.x+)：`Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit`, `Pool.Allocate`, `Sys.Audit`, `Sys.Console`, `Sys.Modify`, `VM.Allocate`, `VM.Audit`, `VM.Clone`, `VM.Config.CDROM`, `VM.Config.Cloudinit`, `VM.Config.CPU`, `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`, `VM.Migrate`, `VM.PowerMgmt`, `SDN.Use`。
    - Proxmox 8.x：需額外加入 `VM.Monitor` 權限。

2.  **建立專用使用者**：
    - 使用者名稱：`terraform-prov@pve`
    - 註解：Terraform Provisioner

3.  **指派角色與 API Token**：
    - 將 `TerraformProv` 角色指派給 `/` 路徑下的 `terraform-prov@pve` 使用者。
    - 為此使用者建立專用的 API Token (`terraform-token`)，並停用權限分離 (`privsep=0`)。

### 1.3 變數管理 (`terraform.tfvars`)

所有環境相關的變數**必須**定義在 `terraform/terraform.tfvars` 檔案中。此檔案不應提交至版本控制。

- **標準變數檔結構**：
  ```hcl
  # terraform.tfvars.example

  # Proxmox API 認證
  proxmox_api_token_id     = "terraform-prov@pve!terraform-token"
  proxmox_api_token_secret = "your-secret-uuid"

  # 叢集與節點配置
  cluster_name           = "detectviz-prod"
  kubernetes_version     = "1.32.0"
  proxmox_host_id        = "pve"

  # 網路配置
  master_ips = ["192.168.0.11", "192.168.0.12", "192.168.0.13"]
  worker_ips = ["192.168.0.14", "192.168.0.15"]
  worker_hostnames = ["app", "ai"]

  # 儲存配置
  proxmox_storage = "nvme-vm" # VM 系統碟儲存池
  worker_data_disks = [
    { size = "200G", storage = "nvme-vm" },      # for vm-4 (app)
    { size = "400G", storage = "sata-backup" } # for vm-5 (ai)
  ]

  # SSH 金鑰
  ssh_public_key = "ssh-rsa AAAA..."

  # 資源配置
  master_cores = 3
  master_ram = 8  # GB
  worker_cores = [6, 7]  # app: 6 cores, ai: 7 cores
  ```

- **變數檔流程**：複製 `terraform/terraform.tfvars.example` 為 `terraform.tfvars`，依環境填入 `proxmox_api_token_id`、`proxmox_api_token_secret`，以及 `cluster_name`、`proxmox_storage`、`master_cores`、`worker_cores` 等欄位，維持控制平面 3 vCPU、工作節點 `[6,7]` 的規劃。
- **儲存池對應**：`proxmox_storage` 指向 `"nvme-vm"`，`worker_data_disks` 預設使用 `nvme-vm`，若需切換至 SATA 備份池需同步調整為 `"sata-backup"`，確保與 `detectviz-{nvme,sata}` StorageClass 對應。
- **網路與節點資訊**：於 `terraform.tfvars` 內維持 `master_ips`、`worker_ips`、`worker_hostnames` 與 README 拓撲一致，包含 VIP `192.168.0.10` 與 `*.detectviz.internal` DNS。
- **SSH 金鑰**：`ssh_public_key` 必須填入完整公鑰或 `file()` 呼叫，確保 Terraform 可透過 Cloud-init 建立初始連線。

### 1.4 資源定義與命名慣例

- **VM 資源**：使用 `proxmox_vm_qemu` 資源進行定義。
- **命名慣例**：VM 名稱 (`name`) 與主機名稱 (`hostname`) 應保持一致，格式為 `${var.cluster_name}-${node_name}`，例如 `detectviz-prod-master-1`。
- **Cloud-Init**：所有 VM **必須**使用 Cloud-Init 進行初始化，以設定主機名稱、IP 位址與 SSH 金鑰。
- **標籤 (Tags)**：為 VM 加入 `terraform-managed` 標籤，便於在 Proxmox UI 中識別由 Terraform 管理的資源。
- **Proxmox 整合**：`provider "proxmox"` 使用 `https://192.168.0.2:8006/api2/json`，`pm_api_url` 與 Token 值須對應 README 虛擬化節點，並於 `terraform apply` 後透過 `terraform state show` 核對 VM `vmid` 與 Proxmox 節點 `pve`。

### 1.5 輸出管理

Terraform 執行完畢後，**必須**自動生成下游工具所需的設定檔。

- **Ansible Inventory**：透過 `local_file` 資源生成 `ansible/inventory.ini`，動態填入 master 與 worker 節點的 IP 位址。
- **Hosts 檔案片段**：生成 `hosts-fragment.txt`，包含所有節點的 IP 與 FQDN 對應，方便批次更新本地 `/etc/hosts`。

---

## 2. 最佳實踐指南 (Best Practices Guide)

本節提供在使用 Terraform 管理 Proxmox 時應遵循的最佳實踐。

### 2.1 狀態管理 (State Management)

- **遠端後端 (Remote Backend)**：在團隊協作環境中，**強烈建議**使用遠端後端 (如 S3, Terraform Cloud, a backend implemented in Go) 儲存 `.tfstate` 檔案。這能提供狀態鎖定 (State Locking) 功能，防止多人同時執行 `apply` 造成狀態損毀。
- **狀態保護**：切勿手動修改 `.tfstate` 檔案。若需進行變更，應使用 `terraform state` 子命令。
- **敏感資訊**：`.tfstate` 檔案可能包含敏感資訊。確保後端儲存的存取權限受到嚴格控管。

### 2.2 程式碼組織與模組化

- **根模組 (Root Module)**：保持根模組的簡潔，主要用於定義 `provider`、`backend` 與呼叫其他模組。
- **功能模組化**：將可重複使用的資源組合 (例如，一個完整的 Kubernetes 節點定義) 封裝成獨立的模組。這有助於提高程式碼的可讀性、可維護性與複用性。
- **檔案結構**：
  ```
  terraform/
  ├── main.tf         # 主要進入點，呼叫模組
  ├── variables.tf    # 定義所有輸入變數
  ├── outputs.tf      # 定義模組輸出
  ├── terraform.tfvars # 環境特定變數 (不提交)
  └── modules/
      └── k8s_node/
          ├── main.tf
          ├── variables.tf
          └── outputs.tf
  ```

### 2.3 安全性

- **最小權限原則**：如平台規格所述，務必為 Terraform 建立專用的、權限受限的 Proxmox 使用者與角色。
- **Secrets 管理**：**嚴禁**將任何敏感資訊 (API Token, 密碼, SSH 私鑰) 硬編碼在 `.tf` 檔案中或提交至版本控制。應使用 `terraform.tfvars` (並加入 `.gitignore`)、環境變數或整合 Vault 等外部密鑰管理工具。
- **權限管理最佳實踐**：在 Proxmox 為 Terraform 建立專用角色與使用者（`terraform-prov@pve`），並依版本選用是否包含 `VM.Monitor` 權限，避免使用 cluster-wide Administrator。
- **認證方式**：透過 `pveum user token add terraform-prov@pve terraform` 建立 Token，並在 shell 匯出 `PM_API_TOKEN_ID`、`PM_API_TOKEN_SECRET`，減少密碼曝露。
- **Provider 設定**：使用環境變數或 Vault 管理敏感資訊，`pm_tls_insecure` 僅於自簽憑證驗證階段暫時啟用。

### 2.4 執行流程

- **`terraform fmt`**：在提交程式碼前，務必執行 `terraform fmt -recursive` 以確保程式碼格式一致。
- **`terraform validate`**：執行 `validate` 以檢查語法是否正確。
- **`terraform plan`**：在執行 `apply` 之前，**永遠**先執行 `terraform plan` 並仔細檢視變更計畫。將計畫儲存成檔案 (`-out=tfplan`) 可確保 `apply` 時執行的內容與計畫完全一致。
  ```bash
  terraform plan -var-file=terraform.tfvars -out=tfplan
  terraform apply "tfplan"
  ```
- **調試設定**：若需疑難排除，可在 Provider 組態中啟用 `pm_log_enable`、`pm_log_levels` 或 `pm_debug`，但避免在常態部署中產生大量日誌。

### 2.5 資源生命週期

- **`prevent_destroy`**：對於關鍵的、不可輕易重建的資源 (例如掛載重要資料的磁碟)，考慮在 `lifecycle` 區塊中設定 `prevent_destroy = true` 以防止意外刪除。
- **`ignore_changes`**：若某些資源屬性會被 Proxmox 或其他外部系統修改，可使用 `ignore_changes` 來避免 Terraform 在下次執行時將其還原。但此做法應謹慎使用，以免造成設定漂移 (Configuration Drift)。
