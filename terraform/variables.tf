# Detectviz Platform - Terraform 變數定義
# 用途：定義所有可配置的變數及其預設值
# 使用方式：複製 terraform.tfvars.example 為 terraform.tfvars 並填入實際值

# ============================================
# Proxmox 連接配置
# ============================================
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://192.168.0.2:8006/api2/json"
}

variable "proxmox_tls_insecure" {
  description = "是否跳過 TLS 憑證驗證（開發環境使用）"
  type        = bool
  default     = true
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (格式：user@pve!token-name)"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
  default     = null
}

variable "proxmox_target_node" {
  description = "Proxmox 目標節點名稱"
  type        = string
  default     = "proxmox"
}

variable "proxmox_storage" {
  description = "Proxmox 儲存池名稱（用於 VM 磁碟）"
  type        = string
  default     = "nvme-vm"
}

variable "proxmox_snippets_storage" {
  description = "Proxmox 儲存池名稱（用於 Cloud-init snippets）"
  type        = string
  default     = "local" # local 存儲通常支持 snippets
}

variable "proxmox_bridge" {
  description = "Proxmox 網路橋接器"
  type        = string
  default     = "vmbr0"
}

variable "proxmox_mtu" {
  description = "Proxmox 橋接器 MTU"
  type        = number
  default     = 9000
}

variable "k8s_overlay_bridge" {
  description = "Kubernetes Overlay 網路橋接器（階段一：同主網路）"
  type        = string
  default     = "vmbr0"
}

# ============================================
# VM 模板配置
# ============================================
variable "vm_template_name" {
  description = "Cloud-init VM 模板名稱（需先建立）- Telmate provider 使用"
  type        = string
  default     = "ubuntu-2204-template"
}

variable "vm_template_id" {
  description = "Cloud-init VM 模板 ID（需先建立）- bpg/proxmox provider 使用"
  type        = number
  default     = 9000
}

variable "vm_user" {
  description = "VM 預設使用者名稱"
  type        = string
  default     = "ubuntu"
}

# ============================================
# SSH 金鑰配置
# ============================================
variable "ssh_public_key" {
  description = "SSH 公鑰（用於 Cloud-init）"
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "SSH 私鑰路徑（用於 Provisioner 連接）"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# ============================================
# Master 節點配置
# ============================================
variable "master_cores" {
  description = "Master 節點 CPU 核心數（依序對應 master_hostnames）"
  type        = list(number)
  default     = [3, 3, 3]
}

variable "master_memory" {
  description = "Master 節點記憶體 (MB)"
  type        = number
  default     = 8192
}

variable "master_disk_size" {
  description = "Master 節點磁碟大小"
  type        = string
  default     = "100G"
}

variable "master_ips" {
  description = "Master 節點 IP 位址清單"
  type        = list(string)
  default     = ["192.168.0.11", "192.168.0.12", "192.168.0.13"]
}

variable "master_hostnames" {
  description = "Master 節點主機名稱清單"
  type        = list(string)
  default     = ["master-1", "master-2", "master-3"]
}

# ============================================
# Worker 節點配置
# ============================================
variable "worker_hostnames" {
  description = "Worker 節點主機名稱清單"
  type        = list(string)
  default     = ["app-worker"]
}

variable "worker_cores" {
  description = "Worker 節點 CPU 核心數（依序對應 worker_hostnames）"
  type        = list(number)
  default     = [12]
}

variable "worker_memory" {
  description = "Worker 節點記憶體 (MB)"
  type        = number
  default     = 24576
}

variable "worker_system_disk_sizes" {
  description = "Worker 節點系統磁碟大小（依序對應 worker_hostnames）"
  type        = list(string)
  default     = ["320G"]
}

variable "worker_data_disks" {
  description = "Worker 節點資料磁碟配置（可留空陣列以略過）"
  type = list(object({
    size    = string
    storage = string
  }))
  default = []
}

variable "worker_ips" {
  description = "Worker 節點 IP 位址清單"
  type        = list(string)
  default     = ["192.168.0.14"]
}

# ============================================
# 網路配置
# ============================================
variable "domain" {
  description = "內部域名"
  type        = string
  default     = "detectviz.internal"
}

variable "gateway" {
  description = "預設閘道"
  type        = string
  default     = "192.168.0.1"
}

variable "nameserver" {
  description = "DNS 伺服器"
  type        = string
  default     = "8.8.8.8"
}

variable "vlan_id" {
  description = "VLAN ID（-1 表示不使用 VLAN）"
  type        = number
  default     = -1
}

# ============================================
# Kubernetes 配置
# ============================================
variable "kubernetes_version" {
  description = "Kubernetes 版本"
  type        = string
  default     = "1.32.0"
}

variable "pod_network_cidr" {
  description = "Pod 網路 CIDR"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Service 網路 CIDR"
  type        = string
  default     = "10.96.0.0/12"
}

variable "control_plane_vip" {
  description = "Kubernetes 控制平面 VIP (HAProxy/Keepalived)"
  type        = string
  default     = "192.168.0.10"
}

# ============================================
# Tags 與 Metadata
# ============================================
variable "environment" {
  description = "環境標籤 (dev/staging/prod)"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "專案名稱"
  type        = string
  default     = "detectviz"
}

variable "cluster_name" {
  description = "Kubernetes 叢集名稱（對應 monitoring externalLabels.cluster）"
  type        = string
  default     = "detectviz-prod"
}

variable "proxmox_host_id" {
  description = "Proxmox Host ID（供監控層級標籤使用）"
  type        = string
  default     = "proxmox"
}

# ============================================
# 驗證規則（確保配置正確性）
# ============================================
locals {
  # 驗證 Master 節點數量必須是奇數（etcd 投票需要）
  master_count_valid = length(var.master_ips) % 2 == 1

  # 驗證 IP 與 Hostname 數量一致
  master_config_valid = length(var.master_ips) == length(var.master_hostnames)
  master_cores_valid  = length(var.master_cores) == length(var.master_hostnames)
  worker_config_valid = length(var.worker_ips) == length(var.worker_hostnames)

  # 驗證 VIP 不在節點 IP 範圍內
  all_node_ips = concat(var.master_ips, var.worker_ips)
  vip_unique   = !contains(local.all_node_ips, var.control_plane_vip)

  # 驗證 Worker 節點配置長度一致
  worker_cores_valid             = length(var.worker_cores) == length(var.worker_hostnames)
  worker_system_disk_sizes_valid = length(var.worker_system_disk_sizes) == length(var.worker_hostnames)
  worker_data_disks_valid        = length(var.worker_data_disks) == 0 || length(var.worker_data_disks) == length(var.worker_hostnames)
}

# 配置驗證錯誤檢查
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
