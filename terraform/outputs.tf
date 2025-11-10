# Detectviz Platform - Terraform 輸出定義
# 用途：定義部署完成後輸出的資訊

# ============================================
# 節點資訊輸出
# ============================================
output "cluster_summary" {
  description = "Kubernetes 叢集摘要資訊"
  value = {
    master_count       = length(proxmox_virtual_environment_vm.k8s_masters)
    worker_count       = length(proxmox_virtual_environment_vm.k8s_workers)
    total_nodes        = length(proxmox_virtual_environment_vm.k8s_masters) + length(proxmox_virtual_environment_vm.k8s_workers)
    environment        = var.environment
    project            = var.project
    cluster_name       = var.cluster_name
    kubernetes_version = var.kubernetes_version
    proxmox_host       = var.proxmox_host_id
  }
}

output "master_nodes_details" {
  description = "Master 節點詳細資訊"
  value = {
    for i, vm in proxmox_virtual_environment_vm.k8s_masters :
    var.master_hostnames[i] => {
      vm_id     = vm.vm_id
      ip        = var.master_ips[i]
      hostname  = "${var.master_hostnames[i]}.${var.domain}"
      fqdn      = "${var.master_hostnames[i]}.${var.domain}"
      cores     = vm.cpu[0].cores
      memory    = "${vm.memory[0].dedicated / 1024} GB"
      disk      = var.master_disk_size
      ssh       = "ssh ${var.vm_user}@${var.master_ips[i]}"
      host_id   = var.proxmox_host_id
      node_role = "control-plane"
      node_type = "master"
    }
  }
}

output "worker_nodes_details" {
  description = "Worker 節點詳細資訊"
  value = {
    for i, vm in proxmox_virtual_environment_vm.k8s_workers :
    var.worker_hostnames[i] => {
      vm_id             = vm.vm_id
      ip                = var.worker_ips[i]
      hostname          = "${var.worker_hostnames[i]}.${var.domain}"
      fqdn              = "${var.worker_hostnames[i]}.${var.domain}"
      cores             = vm.cpu[0].cores
      memory            = "${vm.memory[0].dedicated / 1024} GB"
      system_disk       = var.worker_system_disk_sizes[i]
      data_disk         = length(var.worker_data_disks) > i ? var.worker_data_disks[i].size : ""
      data_disk_storage = length(var.worker_data_disks) > i ? var.worker_data_disks[i].storage : ""
      ssh               = "ssh ${var.vm_user}@${var.worker_ips[i]}"
      host_id           = var.proxmox_host_id
      node_role         = "worker"
      node_type         = format("%s-worker", var.worker_hostnames[i])
    }
  }
}

# ============================================
# 網路資訊輸出
# ============================================
output "network_config" {
  description = "網路配置資訊"
  value = {
    control_plane_vip = var.control_plane_vip
    control_plane_api = "https://${var.control_plane_vip}:6443"
    domain            = var.domain
    gateway           = var.gateway
    nameserver        = var.nameserver
    pod_network_cidr  = var.pod_network_cidr
    service_cidr      = var.service_cidr
  }
}

# ============================================
# Ansible 相關輸出
# ============================================
output "ansible_inventory_path" {
  description = "Ansible Inventory 檔案路徑"
  value       = "../ansible/inventory.ini"
}

output "ansible_command" {
  description = "Ansible 執行指令範例"
  value       = "ansible-playbook -i ../ansible/inventory.ini ../ansible/init-nodes.yml"
}

# ============================================
# SSH 連接資訊
# ============================================
output "ssh_connections" {
  description = "所有節點的 SSH 連接指令"
  value = {
    masters = [
      for i, ip in var.master_ips :
      "ssh ${var.vm_user}@${ip}  # ${var.master_hostnames[i]}"
    ]
    workers = [
      for i, ip in var.worker_ips :
      "ssh ${var.vm_user}@${ip}  # ${var.worker_hostnames[i]}"
    ]
  }
}

# ============================================
# /etc/hosts 片段
# ============================================
output "hosts_fragment" {
  description = "/etc/hosts 設定片段（需附加到各節點）"
  value       = <<-EOT
# Detectviz Platform Hosts (自動生成)
${join("\n", [for i, ip in var.master_ips : "${ip} ${var.master_hostnames[i]}.${var.domain} ${var.master_hostnames[i]}"])}
${join("\n", [for i, ip in var.worker_ips : "${ip} ${var.worker_hostnames[i]}.${var.domain} ${var.worker_hostnames[i]}"])}
${var.control_plane_vip} k8s-api.${var.domain} k8s-api
EOT
}

# ============================================
# Kubernetes 初始化指令
# ============================================
output "kubeadm_init_command" {
  description = "Kubernetes 第一個 Master 節點初始化指令"
  value       = <<-EOT
# 在 ${var.master_hostnames[0]} (${var.master_ips[0]}) 上執行：
sudo kubeadm init \
  --control-plane-endpoint="${var.control_plane_vip}:6443" \
  --upload-certs \
  --pod-network-cidr="${var.pod_network_cidr}" \
  --service-cidr="${var.service_cidr}" \
  --apiserver-advertise-address="${var.master_ips[0]}"
EOT
}

# ============================================
# 驗證指令
# ============================================
output "verification_commands" {
  description = "部署驗證指令"
  value = {
    ping_test = "for ip in ${join(" ", concat(var.master_ips, var.worker_ips))}; do ping -c 1 $ip && echo \"✓ $ip reachable\" || echo \"✗ $ip unreachable\"; done"

    ssh_test = "for ip in ${join(" ", concat(var.master_ips, var.worker_ips))}; do ssh -o ConnectTimeout=5 ${var.vm_user}@$ip 'hostname' && echo \"✓ SSH to $ip OK\" || echo \"✗ SSH to $ip failed\"; done"

    ansible_ping = "ansible all -i ../ansible/inventory.ini -m ping"
  }
}

# ============================================
# 資源使用統計
# ============================================
output "resource_allocation" {
  description = "資源分配統計"
  value = {
    total_cores = (
      sum(var.master_cores) +
      sum(var.worker_cores)
    )
    total_memory_gb = (
      (length(proxmox_virtual_environment_vm.k8s_masters) * var.master_memory +
      length(proxmox_virtual_environment_vm.k8s_workers) * var.worker_memory) / 1024
    )
    master_cores_total = sum(var.master_cores)
    worker_cores_total = sum(var.worker_cores)
    master_memory_gb   = (length(proxmox_virtual_environment_vm.k8s_masters) * var.master_memory) / 1024
    worker_memory_gb   = (length(proxmox_virtual_environment_vm.k8s_workers) * var.worker_memory) / 1024
  }
}

# ============================================
# 下一步指引
# ============================================
output "next_steps_guide" {
  description = "部署完成後的下一步操作指引"
  value       = <<-EOT

╔════════════════════════════════════════════════════════════════╗
║          ✅ Terraform 部署成功完成！                            ║
╚════════════════════════════════════════════════════════════════╝

📋 已創建資源：
   • Master 節點: ${length(proxmox_virtual_environment_vm.k8s_masters)} 台
   • Worker 節點: ${length(proxmox_virtual_environment_vm.k8s_workers)} 台
   • 總 CPU 核心: ${(sum(var.master_cores) + sum(var.worker_cores))} 核
   • 總記憶體: ${(length(proxmox_virtual_environment_vm.k8s_masters) * var.master_memory + length(proxmox_virtual_environment_vm.k8s_workers) * var.worker_memory) / 1024} GB

🔧 下一步操作：

1️⃣  驗證 VM 連接性：
   ${join("\n   ", [for ip in concat(var.master_ips, var.worker_ips) : "ssh ${var.vm_user}@${ip} 'hostname'"])}

2️⃣  更新本地 /etc/hosts：
   cat ../hosts-fragment.txt | sudo tee -a /etc/hosts

3️⃣  分發 hosts 到所有節點（自動化）：
   for ip in ${join(" ", concat(var.master_ips, var.worker_ips))}; do
     scp ../hosts-fragment.txt ${var.vm_user}@$ip:/tmp/hosts-fragment.txt
     ssh ${var.vm_user}@$ip 'sudo sh -c "cat /tmp/hosts-fragment.txt >> /etc/hosts"'
   done

4️⃣  執行 Ansible 初始化：
   cd ../ansible
   ansible-playbook -i inventory.ini init-nodes.yml

5️⃣  初始化 Kubernetes 叢集：
   請參考 deployment.md Phase 2 步驟

📁 生成的檔案：
   • Ansible Inventory: ../ansible/inventory.ini
   • Hosts 片段: ../hosts-fragment.txt

🔗 Control Plane VIP: ${var.control_plane_vip}:6443

EOT
}
