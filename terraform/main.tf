# Detectviz Platform - Terraform 主配置
# 用途：自動化在 Proxmox 上創建 5 台 VM（3 Master + 2 Worker）
# 執行方式：terraform init && terraform apply -var-file=terraform.tfvars

terraform {
  required_version = ">= 1.1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">=0.46.0"
    }
  }
  # Backend 配置（使用本地狀態文件，生產環境建議使用遠端 backend）
  backend "local" {
    path = "terraform.tfstate"
  }
}

# Proxmox Provider 配置（bpg/proxmox >= 0.46.0）
provider "proxmox" {
  endpoint = var.proxmox_api_url
  insecure = var.proxmox_tls_insecure

  # API Token 認證（推薦）
  # 格式：token_id=token_secret
  # 例如：terraform-prov@pve!terraform-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  api_token = var.proxmox_api_token_id != null && var.proxmox_api_token_secret != null ? "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}" : null

  # 或者直接使用變數（如果環境變數設定正確）
  # api_token = var.proxmox_api_token

  # 或者使用 SSH 認證（擇一使用）
  # ssh {
  #   agent    = true
  #   username = "root"
  # }
}

# ============================================
# Master 節點 (vm-1, vm-2, vm-3)
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_masters" {
  count = 3

  name        = "vm-${count.index + 1}"
  description = "Kubernetes Master Node ${count.index + 1}"
  node_name   = var.proxmox_target_node
  vm_id       = 111 + count.index

  # Clone 配置
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # 啟動配置
  started = true
  on_boot = true

  # Agent 配置
  agent {
    enabled = true
  }

  # CPU 配置
  cpu {
    cores   = var.master_cores[count.index]
    sockets = 1
    type    = "host"
  }

  # 記憶體配置
  memory {
    dedicated = var.master_memory
  }

  # 磁碟配置
  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = parseint(replace(var.master_disk_size, "G", ""), 10)
    file_format  = "raw"
  }

  # 網路配置
  network_device {
    bridge  = var.proxmox_bridge
    model   = "virtio"
    enabled = true
  }

  # Serial 設備（支援 Web Console）
  serial_device {}

  # VGA 配置
  vga {
    type = "serial0"
  }

  # Cloud-init 配置
  initialization {
    ip_config {
      ipv4 {
        address = "${var.master_ips[count.index]}/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.nameserver]
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub"))]
    }
  }

  # 生命週期配置
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }

  # Tags
  tags = ["k8s", "master", "detectviz"]

  # 依賴等待
  depends_on = []
}

# ============================================
# Worker 節點 (vm-4)
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_workers" {
  count = 1

  name        = "app-worker"
  description = "Kubernetes Application Worker Node"
  node_name   = var.proxmox_target_node
  vm_id       = 114

  # Clone 配置
  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  # 啟動配置
  started = true
  on_boot = true

  # Agent 配置
  agent {
    enabled = true
  }

  # CPU 配置
  cpu {
    cores   = var.worker_cores[count.index]
    sockets = 1
    type    = "host"
  }

  # 記憶體配置
  memory {
    dedicated = var.worker_memory
  }

  # 系統磁碟配置 (合併系統與應用儲存)
  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = parseint(replace(var.worker_system_disk_sizes[0], "G", ""), 10)
    file_format  = "raw"
  }

  # 網路配置
  network_device {
    bridge  = var.proxmox_bridge
    model   = "virtio"
    enabled = true
  }

  # Serial 設備（支援 Web Console）
  serial_device {}

  # VGA 配置
  vga {
    type = "serial0"
  }

  # Cloud-init 配置
  initialization {
    ip_config {
      ipv4 {
        address = "${var.worker_ips[count.index]}/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.nameserver]
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file("~/.ssh/id_rsa.pub"))]
    }
  }

  # 生命週期配置
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }

  # Tags
  tags = ["k8s", "worker", "detectviz"]

  # 依賴等待
  depends_on = []
}

# ============================================
# VM 創建後執行初始化（使用 null_resource）
# ============================================
resource "null_resource" "init_masters" {
  count = 1

  # VM 創建後執行
  depends_on = [proxmox_virtual_environment_vm.k8s_masters]

  # VM 創建後執行初始化腳本
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.master_hostnames[count.index]}.${var.domain}",
      "echo '127.0.0.1 ${var.master_hostnames[count.index]}.${var.domain} ${var.master_hostnames[count.index]}' | sudo tee -a /etc/hosts",
      "echo 'VM ${var.master_hostnames[count.index]} 初始化完成'",
    ]

    connection {
      type        = "ssh"
      user        = var.vm_user
      private_key = file(var.ssh_private_key_path)
      host        = var.master_ips[count.index]
      timeout     = "10m"
    }
  }
}

resource "null_resource" "init_workers" {
  count = 0

  # VM 創建後執行
  depends_on = [proxmox_virtual_environment_vm.k8s_workers]

  # VM 創建後執行初始化腳本
  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.worker_hostnames[count.index]}.${var.domain}",
      "echo '127.0.0.1 ${var.worker_hostnames[count.index]}.${var.domain} ${var.worker_hostnames[count.index]}' | sudo tee -a /etc/hosts",
      "echo 'VM ${var.worker_hostnames[count.index]} 初始化完成'",
    ]

    connection {
      type        = "ssh"
      user        = var.vm_user
      private_key = file(var.ssh_private_key_path)
      host        = var.worker_ips[count.index]
      timeout     = "5m"
    }
  }
}

# ============================================
# 本地執行器：生成 Ansible Inventory
# ============================================
resource "null_resource" "generate_ansible_inventory" {
  # 當 VM 創建完成後執行
  depends_on = [
    proxmox_virtual_environment_vm.k8s_masters,
    proxmox_virtual_environment_vm.k8s_workers,
  ]

  # 生成 Ansible inventory 文件
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ../ansible
      cat > ../ansible/inventory.ini <<EOF
# ============================================
# Detectviz Platform - Ansible Inventory
# Detectviz 平臺 Ansible 主機庫存配置
# ============================================
# 自動生成於：$(date)
# 此檔案由 Terraform 自動產生，請勿手動編輯
# 對應文檔：deployment/02-ansible.md

# Master 節點組 - 控制平面節點，提供 Kubernetes API Server、Scheduler、Controller Manager
[masters]
${join("\n", [for i, ip in var.master_ips : "${var.master_hostnames[i]} ansible_host=${ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path}  # ${var.master_hostnames[i]}.${var.domain}"])}

# Worker 節點組 - 工作節點，用於運行應用 Pod
[workers]
${join("\n", [for i, ip in var.worker_ips : "${var.worker_hostnames[i]} ansible_host=${ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path}      # ${var.worker_hostnames[i]}.${var.domain}"])}

# 集群組 - 包含所有 Kubernetes 節點
[k8s_cluster:children]
masters    # 引用 masters 組
workers    # 引用 workers 組

# 集群全域變數 - 適用於所有 Kubernetes 節點
[k8s_cluster:vars]
ansible_python_interpreter=/usr/bin/python3
kubernetes_version=${var.kubernetes_version}                         # Kubernetes 版本號
pod_network_cidr=${var.pod_network_cidr}                    # Pod 網路 CIDR
service_cidr=${var.service_cidr}                         # Service 網路 CIDR
control_plane_vip=${var.control_plane_vip}                    # 控制平面虛擬 IP，用於負載均衡
EOF
      chmod 644 ../ansible/inventory.ini
      echo "✅ Ansible inventory 已生成: configuration/ansible/inventory.ini"
      echo ""
      echo "📋 已自動設定的參數："
      echo "   ✓ kubernetes_version: ${var.kubernetes_version}"
      echo "   ✓ control_plane_vip: ${var.control_plane_vip}"
      echo "   ✓ pod_network_cidr: ${var.pod_network_cidr}"
      echo "   ✓ service_cidr: ${var.service_cidr}"
      echo ""
      echo "📝 如需調整，請編輯 configuration/ansible/inventory.ini 的 [k8s_cluster:vars] 區段"
    EOT
  }

  # 生成 /etc/hosts 片段（用於本地 DNS 解析）
  provisioner "local-exec" {
    command = <<-EOT
      cat > ../../hosts-fragment.txt <<EOF
# Detectviz Platform Hosts
# 自動生成於：$(date)
${join("\n", [for i, ip in var.master_ips : "${ip} ${var.master_hostnames[i]}.${var.domain} ${var.master_hostnames[i]}"])}
${join("\n", [for i, ip in var.worker_ips : "${ip} ${var.worker_hostnames[i]}.${var.domain} ${var.worker_hostnames[i]}"])}
${var.control_plane_vip} k8s-api.${var.domain} k8s-api
EOF
      echo "✅ Hosts 片段已生成: hosts-fragment.txt"
      echo "   (位於專案根目錄)"
      echo ""
      echo "📝 請將以下內容加入內部 DNS 或本地 /etc/hosts："
      cat ../../hosts-fragment.txt
    EOT
  }
}

# ============================================
# 輸出 VM 資訊（用於驗證）
# ============================================
output "master_nodes" {
  description = "Master 節點資訊"
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
  description = "Worker 節點資訊"
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
  description = "Kubernetes 控制平面 VIP"
  value       = var.control_plane_vip
}

output "next_steps" {
  description = "下一步操作指引"
  value       = <<-EOT

  ========================================
  ✅ Terraform 部署完成！
  ========================================

  下一步操作：

  1. 驗證 VM 連接性：
     ${join("\n     ", [for ip in concat(var.master_ips, var.worker_ips) : "ssh ${var.vm_user}@${ip} 'hostname'"])}

  2. 更新本地 /etc/hosts：
     cat ../hosts-fragment.txt | sudo tee -a /etc/hosts

  3. 執行 Ansible 初始化：
     cd ../ansible
     ansible-playbook -i inventory.ini init-nodes.yml

  4. 初始化 Kubernetes 叢集：
     請參考 deployment.md Phase 2 步驟

  EOT
}
