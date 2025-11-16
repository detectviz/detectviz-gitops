# 整體部署流程完整性檢查

## 基於文件 (檢查改善後必要同步修正此檔案)
[infra-deploy-sop.md](infra-deploy-sop.md)
[infra-deploy-troubleshooting.md](infra-deploy-troubleshooting.md)
[README.md](README.md)
README.md

- [Phase 0: 前置作業](#phase-0-前置作業)
  - [1. Proxmox 雙網路配置](#1-proxmox-雙網路配置)
  - [2. DNS 伺服器配置](#2-dns-伺服器配置)
  - [3. VM 模板準備](#3-vm-模板準備)
  - [4. SSH 金鑰準備](#4-ssh-金鑰準備)
- [部署流程](#部署流程)
  - [Phase 1: Terraform 基礎設施佈建](#phase-1-terraform-基礎設施佈建)
  - [Phase 2: 網路配置驗證](#phase-2-網路配置驗證)
  - [Phase 3: Ansible 自動化部署](#phase-3-ansible-自動化部署)
  - [Phase 4: GitOps 基礎設施同步](#phase-4-gitops-基礎設施同步)
  - [Phase 5: Vault 初始化](#phase-5-vault-初始化)
---

# 1. Proxmox Host 層

[x] **單節點 Proxmox 正常運作**
   - 設定位置：手動配置（Proxmox VE 8.x）
[x] **SATA（OS）+ NVMe（VM）分離**
   - 設定位置：手動配置（SATA SSD + NVMe SSD）
[x] **LVM-thin 重新建立完成**
   - 設定位置：手動配置（LVM-thin pool）
[x] **網卡 vmbr0(enp4s0) / vmbr1(enp5s0) 清楚規劃**
   - 設定位置：手動配置（vmbr0: 192.168.0.0/24, vmbr1: 10.0.0.0/24）
[x] **Proxmox Host sysctl / rp_filter 調整：已做但需記錄**：
   - 設定位置：ansible/roles/network/tasks/configure-sysctl.yml
   - 設定位置：[deploy.md#1.2-配置-sysctl-參數](deploy.md#1.2-配置-sysctl-參數)
[ ] **Tailscale 已規劃，可作為 optional remote access**
   - 設定位置：手動配置（已安裝但未啟用）
[ ] **Uptime-Keepalive（保留 SSH 與 Web 連線）未配置**：
   - 設定位置：尚未配置
   - 建議新增：
     * `systemd-logind.conf` IdleTimeout
     * sshd keepalive
[ ] **Proxmox Host 防火牆策略尚未定義**
   - 設定位置：尚未配置
   - 建議 minimum:
     * 允許 Tailscale
     * 允許 inbound 8006/22 only 内網


---

# 2. Terraform 建置 VM 階段

[x] **VM 設計（master-1/2/3, worker）**
   - 設定位置：terraform/main.tf (resource "proxmox_virtual_environment_vm")
   - Cloud-init network + ssh key
[x] **Applied configuration 基本無誤**
   - 設定位置：terraform/main.tf
[x] **QEMU guest agent 已確保**
   - 設定位置：terraform/main.tf (agent { enabled = true })
[x] **VM 多網卡正確 eth0=192.168.x.x / eth1=10.0.0.x**
   - 設定位置：terraform/main.tf (network_device blocks)
[x] **Template（VM 9000）未完全調整為 OVMF + virtio boot**
   - 設定位置：terraform/main.tf (bios = "ovmf", network_device model = "virtio")
   - 已實作：bios = "ovmf", machine = "q35", scsi0 = nvme-vg, efidisk0 = nvme-vg
* Terraform variables 未加入：
[x] **`vmbr1/vmbr2 MTU 自動帶入`**
   - 設定位置：terraform/main.tf (mtu = var.proxmox_mtu)

---

# 3. Ansible 初始化階段

[x] **準備 init-nodes.yml**
   - 設定位置：ansible/deploy-cluster.yml
[x] **SSH reachable（已確認成功）**
   - 設定位置：ansible/inventory.ini
[ ] **swap off** 是否有自動設定
[ ] **SSH 設定** PasswordAuthentication no (禁用 SSH 密碼登入)
[ ] **自動化檢查 outbound + DNS + ImagePull**
   範例：
   ```yaml
   - name: Check Internet Connectivity
   shell: |
      ping -c1 8.8.8.8
   register: ping_result
   failed_when: ping_result.rc != 0
   ```
[x] **Container Runtime 安裝方式**
   - 設定位置：ansible/roles/common/templates/containerd-config.toml.j2, ansible/roles/common/tasks/main.yml
   - [x] containerd - ansible/roles/common/tasks/main.yml (安裝 containerd)
   - [x] crictl - ansible/roles/common/tasks/main.yml (安裝 crictl)
   - [x] kubelet CRI 設定 - ansible/roles/master/templates/kubeadm-config.yaml.j2 (criSocket: "unix:///var/run/containerd/containerd.sock")


若缺失 → kubeadm init/join 會出問題。

---

# 4. Kubernetes Control Plane

[x] **kubeadm init 指令（已產生）**
   - 設定位置：`ansible`
[x] **VIP（kube-vip 或 metalLB API VIP）規劃正確**
   - 設定位置：terraform/main.tf (control_plane_vip = var.control_plane_vip)
[x] **Pod CIDR 與 Service CIDR 正確**
   - 設定位置：terraform/main.tf (pod_network_cidr, service_cidr)
[ ] **kube-vip Deployment manifest（DaemonSet）未放入 GitOps**
   - 參考檔案：[kube-vip 修正配置](task.md#kube-vip-修正配置)
[ ] **Calico Overlay 目前還未區分「bootstrap 與 runtime」兩層 manifest**
   - 參考檔案：[Calico 修正配置](task.md#calico-修正配置)
[ ] **CNI MTU 需配合 vmbr0 MTU 1500，自動修正 (9000 不支援，需改為 1500)**
   - 參考檔案：[Calico 修正配置](task.md#calico-修正配置)
   - 若 MTU 不當，會發生 NodeReady=false / Cilium/Calico 掛掉

# 5. Vault（Phase 5）

- [ ] Vault Seal/Unseal 流程正確 [Phase 5: Vault 初始化](infra-deploy-sop.md#phase-5-vault-初始化)
- [ ] Vault backup snapshot / sys/health readinessProbe