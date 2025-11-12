# Detectviz Platform - Terraform 主配置
# 專案：Detectviz
# 說明：此檔案負責定義 Proxmox 基礎設施，包括 Master 和 Worker 節點的 VM 創建、網路配置、磁碟設定及 Cloud-init 初始化。
# 執行方式：`terraform init && terraform apply -var-file=terraform.tfvars`

terraform {
  required_version = ">= 1.1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">=0.46.0"
    }
  }
  # 後端配置：使用本地狀態檔案。在生產環境中，建議改用遠端後端（如 S3）以實現狀態共享與鎖定。
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Proxmox 提供者配置
provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = var.proxmox_tls_insecure

  # API Token 認證：優先使用 API Token 進行認證
  api_token = var.proxmox_api_token_id != null && var.proxmox_api_token_secret != null ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null
}

# ============================================
# Master 節點 (Control Plane Nodes)
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_masters" {
  count = 3

  name        = var.master_hostnames[count.index]
  description = "Kubernetes Master Node ${count.index + 1}"
  node_name   = var.proxmox_target_node
  vm_id       = 111 + count.index
  bios        = "ovmf" # 啟用 UEFI 模式，以支援新版 Ubuntu 與 Cloud-init

  # VM 範本複製設定
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # 啟動與 Agent 設定
  started = true
  on_boot = true
  agent {
    enabled = true
  }

  # CPU 與記憶體配置
  cpu {
    cores   = var.master_cores[count.index]
    sockets = 1
    type    = "host"
  }
  memory {
    dedicated = var.master_memory
  }

  # 磁碟配置
  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = parseint(replace(var.master_disk_size, "G", ""), 10)
    file_format  = "raw"
    replicate    = false # 單節點 Proxmox 環境不支援磁碟複製
  }

  # 雙網路配置
  # 外部網路 (vmbr0)：用於管理與應用流量
  network_device {
    bridge  = var.proxmox_bridge
    model   = "virtio"
    enabled = true
    mtu     = var.proxmox_mtu
  }
  # 內部網路 (vmbr1)：用於 Kubernetes 節點間通訊
  network_device {
    bridge  = var.k8s_overlay_bridge
    model   = "virtio"
    enabled = true
    mtu     = var.proxmox_mtu
  }

  # 序列埠與顯示配置
  serial_device {}
  vga {
    type = "serial0"
  }

  # Cloud-init 初始化配置
  initialization {
    # 外部網路 (ens18)
    ip_config {
      ipv4 {
        address = "${var.master_ips[count.index]}/24"
        gateway = var.gateway
      }
    }
    # 內部網路 (ens19)
    ip_config {
      ipv4 {
        address = "${var.master_internal_ips[count.index]}/24"
      }
    }
    dns {
      servers = [var.nameserver, var.nameserver_fallback]
    }
    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub"))]
    }
  }

  # 生命週期管理
  lifecycle {
    ignore_changes = [network_device]
  }

  # 資源標籤
  tags = ["k8s", "master", "detectviz"]
}

# ============================================
# Worker 節點 (Application Worker Node)
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_workers" {
  count = 1

  name        = "app-worker"
  description = "Kubernetes Application Worker Node"
  node_name   = var.proxmox_target_node
  vm_id       = 114
  bios        = "ovmf"

  # VM 範本複製設定
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # 啟動與 Agent 設定
  started = true
  on_boot = true
  agent {
    enabled = true
  }

  # CPU 與記憶體配置
  cpu {
    cores   = var.worker_cores[count.index]
    sockets = 1
    type    = "host"
  }
  memory {
    dedicated = var.worker_memory
  }

  # 系統磁碟配置
  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = parseint(replace(var.worker_system_disk_sizes[0], "G", ""), 10)
    file_format  = "raw"
    replicate    = false
  }

  # 雙網路配置
  network_device {
    bridge  = var.proxmox_bridge
    model   = "virtio"
    enabled = true
    mtu     = var.proxmox_mtu
  }
  network_device {
    bridge  = var.k8s_overlay_bridge
    model   = "virtio"
    enabled = true
    mtu     = var.proxmox_mtu
  }

  # 序列埠與顯示配置
  serial_device {}
  vga {
    type = "serial0"
  }

  # Cloud-init 初始化配置
  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[count.index]}/24"
        gateway = var.gateway
      }
    }
    ip_config {
      ipv4 {
        address = "${var.worker_internal_ips[count.index]}/24"
      }
    }
    dns {
      servers = [var.nameserver, var.nameserver_fallback]
    }
    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub"))]
    }
  }

  # 生命週期管理
  lifecycle {
    ignore_changes = [network_device]
  }

  # 資源標籤
  tags = ["k8s", "worker", "detectviz"]
}

# ============================================
# 本地執行器：生成 Ansible Inventory 與 Hosts 片段
# ============================================
resource "null_resource" "generate_ansible_inventory" {
  # 確保在 VM 創建完成後執行
  depends_on = [
    proxmox_virtual_environment_vm.k8s_masters,
    proxmox_virtual_environment_vm.k8s_workers,
  ]

  # 生成 Ansible inventory 檔案
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ../ansible
      cat > ../ansible/inventory.ini <<EOF
# ============================================
# Detectviz Platform - Ansible Inventory
# Detectviz 平台 Ansible 主機清單
# ============================================
# 自動生成於：$(date)
# 此檔案由 Terraform 自動產生，請勿手動編輯。

# Master 節點組：控制平面，運行 Kubernetes API Server、Scheduler 等核心組件。
[masters]
${join("\n", [for i, ip in var.master_ips : "${var.master_hostnames[i]} ansible_host=${ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path}  # ${var.master_hostnames[i]}.${var.domain}"])}

# Worker 節點組：工作節點，用於運行應用程式 Pod。
[workers]
${join("\n", [for i, ip in var.worker_ips : "${var.worker_hostnames[i]} ansible_host=${ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path}      # ${var.worker_hostnames[i]}.${var.domain}"])}

# Kubernetes 集群組：包含所有 Master 和 Worker 節點。
[k8s_cluster:children]
masters
workers

# 集群全域變數：適用於所有 Kubernetes 節點。
[k8s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3
kubernetes_version="${var.kubernetes_version}"      # Kubernetes 版本
pod_network_cidr="${var.pod_network_cidr}"        # Pod 網路 CIDR
service_cidr="${var.service_cidr}"                # Service 網路 CIDR
control_plane_vip="${var.control_plane_vip}"      # 控制平面虛擬 IP

# 網路配置
network_mtu=${var.proxmox_mtu}                      # 網路 MTU (巨型幀)
k8s_overlay_bridge="${var.k8s_overlay_bridge}"        # Kubernetes Overlay 網路橋接器
cluster_network="10.0.0.0/24"                       # 內部集群網路
cluster_domain="${var.cluster_domain}"              # 內部集群域名

# 網路介面對應 (ens18: 外部網路, ens19: 內部網路)
EOF
      chmod 644 ../ansible/inventory.ini
      echo "[✓] Ansible inventory 已生成至：../ansible/inventory.ini"
    EOT
  }

  # 生成 /etc/hosts 片段，用於 Proxmox dnsmasq 或本地開發環境。
  provisioner "local-exec" {
    command = <<-EOT
      cat > ../hosts-fragment.txt <<EOF
# Detectviz Platform Hosts (Terraform 自動生成)
# 自動生成於：$(date)

# 外部網路 (vmbr0 - 192.168.0.0/24)
${join("\n", [for i, ip in var.master_ips : "${ip} ${var.master_hostnames[i]}.${var.domain} ${var.master_hostnames[i]}"])}
${join("\n", [for i, ip in var.worker_ips : "${ip} ${var.worker_hostnames[i]}.${var.domain} ${var.worker_hostnames[i]}"])}
${var.control_plane_vip} k8s-api.${var.domain} k8s-api

# 內部集群網路 (vmbr1 - 10.0.0.0/24)
${join("\n", [for i, ip in var.master_internal_ips : "${ip} ${var.master_hostnames[i]}.${var.cluster_domain} ${var.master_hostnames[i]}-cluster"])}
${join("\n", [for i, ip in var.worker_internal_ips : "${ip} ${var.worker_hostnames[i]}.${var.cluster_domain} ${var.worker_hostnames[i]}-cluster"])}
EOF
      echo "[✓] Hosts 片段已生成至：../hosts-fragment.txt"
    EOT
  }
}

# ============================================
# 輸出 VM 資訊 (Outputs)
# ============================================
output "master_nodes" {
  description = "Master 節點的詳細資訊。"
  value = {
    for i, vm in proxmox_virtual_environment_vm.k8s_masters :
    var.master_hostnames[i] => {
      ip       = var.master_ips[i]
      hostname = "${var.master_hostnames[i]}.${var.domain}"
      cores    = vm.cpu[0].cores
      memory   = vm.memory[0].dedicated
    }
  }
}

output "worker_nodes" {
  description = "Worker 節點的詳細資訊。"
  value = {
    for i, vm in proxmox_virtual_environment_vm.k8s_workers :
    var.worker_hostnames[i] => {
      ip       = var.worker_ips[i]
      hostname = "${var.worker_hostnames[i]}.${var.domain}"
      cores    = vm.cpu[0].cores
      memory   = vm.memory[0].dedicated
    }
  }
}

output "control_plane_vip" {
  description = "Kubernetes 控制平面的虛擬 IP。"
  value       = var.control_plane_vip
}

output "next_steps" {
  description = "後續步驟指引。"
  value       = <<-EOT

  ========================================
  [✓] Terraform 基礎設施部署完成！
  ========================================

  下一步：
  1. 驗證 VM 連線：
     ${join("\n     ", [for ip in concat(var.master_ips, var.worker_ips) : "ssh ${var.vm_user}@${ip} 'hostname'"])}

  2. 執行 Ansible 自動化部署：
     cd ../ansible
     ansible-playbook -i inventory.ini deploy-cluster.yml
  ========================================
  EOT
}
