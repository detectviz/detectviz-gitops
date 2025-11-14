# Detectviz Platform - Terraform 變數定義
# 專案：Detectviz
# 說明：此檔案定義所有 Terraform 設定檔中使用的變數，包含 Proxmox 連接資訊、VM 模板、節點規格、網路配置及 Kubernetes 參數。
# 使用方式：請複製 `terraform.tfvars.example` 為 `terraform.tfvars`，並填入您的環境實際值。

# ============================================
# Proxmox 連接配置 (Proxmox Connection Settings)
# ============================================
variable "proxmox_api_url" {
  description = "Proxmox API 的 URL。請確保此 URL 可從執行 Terraform 的機器訪問。"
  type        = string
  default     = "https://192.168.0.2:8006/api2/json"
}

variable "proxmox_tls_insecure" {
  description = "是否跳過 TLS 憑證驗證。在開發或測試環境中，若 Proxmox 使用自簽章憑證，可設為 `true`。"
  type        = bool
  default     = true
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID，用於 Terraform 的認證。格式為 `user@realm!token-name`。"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret，與 Token ID 配套使用。"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_target_node" {
  description = "執行 VM 佈建的 Proxmox 節點名稱。"
  type        = string
  default     = "proxmox"
}

variable "proxmox_storage" {
  description = "用於存放 VM 磁碟的 Proxmox 儲存池名稱，建議使用高效能儲存（如 NVMe）。"
  type        = string
  default     = "nvme-vm"
}

variable "proxmox_snippets_storage" {
  description = "用於存放 Cloud-init snippets 的 Proxmox 儲存池名稱，通常為 `local`。"
  type        = string
  default     = "local"
}

variable "proxmox_bridge" {
  description = "Proxmox 外部網路橋接器，通常為 `vmbr0`，用於管理與應用流量。"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_mtu" {
  description = "Proxmox 橋接器與 VM 網卡的 MTU（最大傳輸單元）。標準值為 1500，如需啟用巨型幀（Jumbo Frames）且硬體支援可設為 9000。"
  type        = number
  default     = 1500
}

variable "k8s_overlay_bridge" {
  description = "Kubernetes 內部集群網路橋接器，通常為 `vmbr1`，專用於節點間通訊（如 etcd、Pod 網路）。"
  type        = string
  default     = "vmbr1"
}

# ============================================
# VM 範本配置 (VM Template Configuration)
# ============================================
variable "vm_template_name" {
  description = "用於建立 VM 的 Cloud-init 範本名稱，需在 Proxmox 中預先建立。"
  type        = string
  default     = "ubuntu-2204-template"
}

variable "vm_template_id" {
  description = "Cloud-init VM 範本的 ID，需與 Proxmox 中的設定一致。"
  type        = number
  default     = 9000
}

variable "vm_user" {
  description = "VM 內部的預設使用者名稱，用於 SSH 連接與 Ansible 操作。"
  type        = string
  default     = "ubuntu"
}

# ============================================
# SSH 金鑰配置 (SSH Key Configuration)
# ============================================
variable "ssh_public_key" {
  description = "SSH 公鑰，將注入 VM 中以進行無密碼登入。若留空，將嘗試讀取 `~/.ssh/id_rsa.pub`。"
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "SSH 私鑰的路徑，用於 Terraform Provisioner 與 Ansible 連接 VM。"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# ============================================
# Master 節點配置 (Master Node Configuration)
# ============================================
variable "master_cores" {
  description = "Master 節點的 CPU 核心數列表，依序對應 `master_hostnames`。"
  type        = list(number)
  default     = [3, 3, 3]
}

variable "master_memory" {
  description = "每個 Master 節點的記憶體大小（MB）。"
  type        = number
  default     = 8192
}

variable "master_disk_size" {
  description = "每個 Master 節點的磁碟大小（例如 `100G`）。"
  type        = string
  default     = "100G"
}

variable "master_ips" {
  description = "Master 節點的外部網路 IP 位址列表（`vmbr0`），用於管理與 API Server 存取。"
  type        = list(string)
  default     = ["192.168.0.11", "192.168.0.12", "192.168.0.13"]
}

variable "master_internal_ips" {
  description = "Master 節點的內部集群網路 IP 位址列表（`vmbr1`），用於 etcd 與節點間通訊。"
  type        = list(string)
  default     = ["10.0.0.11", "10.0.0.12", "10.0.0.13"]
}

variable "master_hostnames" {
  description = "Master 節點的主機名稱列表。"
  type        = list(string)
  default     = ["master-1", "master-2", "master-3"]
}

# ============================================
# Worker 節點配置 (Worker Node Configuration)
# ============================================
variable "worker_hostnames" {
  description = "Worker 節點的主機名稱列表。"
  type        = list(string)
  default     = ["app-worker"]
}

variable "worker_cores" {
  description = "Worker 節點的 CPU 核心數列表，依序對應 `worker_hostnames`。"
  type        = list(number)
  default     = [12]
}

variable "worker_memory" {
  description = "每個 Worker 節點的記憶體大小（MB）。"
  type        = number
  default     = 24576
}

variable "worker_system_disk_sizes" {
  description = "Worker 節點的系統磁碟大小列表（用於 OS 與系統服務）。"
  type        = list(string)
  default     = ["100G"]
}

variable "worker_data_disks" {
  description = "Worker 節點的額外資料磁碟配置列表（供 TopoLVM 等儲存系統使用）。每個元素包含 size 和 storage。範例：[{size = \"250G\", storage = \"nvme-vm\"}]，留空 [] 則不建立額外磁碟。"
  type = list(object({
    size    = string
    storage = string
  }))
  default = []
}

variable "worker_ips" {
  description = "Worker 節點的外部網路 IP 位址列表（`vmbr0`）。"
  type        = list(string)
  default     = ["192.168.0.14"]
}

variable "worker_internal_ips" {
  description = "Worker 節點的內部集群網路 IP 位址列表（`vmbr1`）。"
  type        = list(string)
  default     = ["10.0.0.14"]
}

# ============================================
# 網路配置 (Network Configuration)
# ============================================
variable "domain" {
  description = "外部域名，用於管理與應用服務，例如 `detectviz.internal`。"
  type        = string
  default     = "detectviz.internal"
}

variable "cluster_domain" {
  description = "集群內部域名，用於 Kubernetes 節點間通訊，例如 `cluster.internal`。"
  type        = string
  default     = "cluster.internal"
}

variable "gateway" {
  description = "VM 的預設閘道位址。"
  type        = string
  default     = "192.168.0.1"
}

variable "nameserver" {
  description = "主 DNS 伺服器位址，建議指向 Proxmox 上的 dnsmasq 服務。"
  type        = string
  default     = "192.168.0.2"
}

variable "nameserver_fallback" {
  description = "備用 DNS 伺服器位址，例如 `8.8.8.8`。"
  type        = string
  default     = "8.8.8.8"
}

variable "vlan_id" {
  description = "VLAN ID。設為 `-1` 表示不使用 VLAN。"
  type        = number
  default     = -1
}

# ============================================
# Kubernetes 配置 (Kubernetes Configuration)
# ============================================
variable "kubernetes_version" {
  description = "要安裝的 Kubernetes 版本號。"
  type        = string
  default     = "1.32.9"
}

variable "pod_network_cidr" {
  description = "Kubernetes Pod 網路的 CIDR，例如 `10.244.0.0/16`。"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes Service 網路的 CIDR，例如 `10.96.0.0/12`。"
  type        = string
  default     = "10.96.0.0/12"
}

variable "control_plane_vip" {
  description = "Kubernetes 控制平面的虛擬 IP（VIP），用於 API Server 的高可用性。"
  type        = string
  default     = "192.168.0.10"
}

# ============================================
# Tags 與 Metadata (Tags and Metadata)
# ============================================
variable "environment" {
  description = "環境標籤，例如 `dev`, `staging`, `prod`。"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "專案名稱，用於資源標籤。"
  type        = string
  default     = "detectviz"
}

variable "cluster_name" {
  description = "Kubernetes 叢集的全域名稱，用於監控與日誌標籤。"
  type        = string
  default     = "detectviz-prod"
}

variable "proxmox_host_id" {
  description = "Proxmox 主機的唯一識別碼，用於監控標籤。"
  type        = string
  default     = "proxmox"
}

# ============================================
# 組態驗證規則 (Configuration Validation Rules)
# ============================================
locals {
  # 驗證 Master 節點數量是否為奇數，以確保 etcd 的高可用性。
  master_count_valid = length(var.master_ips) % 2 == 1

  # 驗證 Master 節點的 IP、主機名稱與 CPU 核心數配置長度是否一致。
  master_config_valid = length(var.master_ips) == length(var.master_hostnames)
  master_cores_valid  = length(var.master_cores) == length(var.master_hostnames)

  # 驗證 Worker 節點的 IP 與主機名稱配置長度是否一致。
  worker_config_valid = length(var.worker_ips) == length(var.worker_hostnames)

  # 驗證 VIP 是否與任何節點 IP 衝突。
  all_node_ips = concat(var.master_ips, var.worker_ips)
  vip_unique   = !contains(local.all_node_ips, var.control_plane_vip)

  # 驗證 Worker 節點的 CPU、磁碟等配置長度是否一致。
  worker_cores_valid             = length(var.worker_cores) == length(var.worker_hostnames)
  worker_system_disk_sizes_valid = length(var.worker_system_disk_sizes) == length(var.worker_hostnames)
  worker_data_disks_valid        = length(var.worker_data_disks) == 0 || length(var.worker_data_disks) == length(var.worker_hostnames)
}

# 若驗證失敗，此資源將觸發錯誤並停止執行。
resource "null_resource" "validate_config" {
  count = (
    local.master_count_valid &&
    local.master_config_valid &&
    local.master_cores_valid &&
    local.worker_config_valid &&
    local.vip_unique &&
    local.worker_cores_valid &&
    local.worker_system_disk_sizes_valid &&
    local.worker_data_disks_valid
  ) ? 0 : 1

  provisioner "local-exec" {
    command = <<-EOT
      echo "❌ Terraform 配置驗證失敗："
      echo ""
      ${!local.master_count_valid ? "echo '  - Master 節點數量必須是奇數（當前：${length(var.master_ips)}）'" : ""}
      ${!local.master_config_valid ? "echo '  - Master 節點 IP 與 Hostname 數量不一致'" : ""}
      ${!local.master_cores_valid ? "echo '  - Master CPU 核心數與 Hostname 數量不一致'" : ""}
      ${!local.worker_config_valid ? "echo '  - Worker 節點 IP 與 Hostname 數量不一致'" : ""}
      ${!local.worker_cores_valid ? "echo '  - Worker CPU 核心數與 Hostname 數量不一致'" : ""}
      ${!local.worker_system_disk_sizes_valid ? "echo '  - Worker 系統磁碟配置數量不一致'" : ""}
      ${!local.worker_data_disks_valid ? "echo '  - Worker 資料磁碟配置數量不一致'" : ""}
      ${!local.vip_unique ? "echo '  - Control Plane VIP 與節點 IP 衝突'" : ""}
      echo ""
      echo "請檢查 terraform.tfvars 配置後重新執行。"
      exit 1
    EOT
  }
}
