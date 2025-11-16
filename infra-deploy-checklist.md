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
   - **狀態**: ❌ 未配置
   - **說明**: 在所有 Ansible roles 中未找到禁用 swap 的任務
   - **建議**: 在 `ansible/roles/common/tasks/main.yml` 中添加 swap 禁用任務
   - **參考配置**:
     ```yaml
     - name: Disable swap
       become: true
       ansible.builtin.command: swapoff -a
       changed_when: false

     - name: Disable swap permanently
       become: true
       ansible.builtin.lineinfile:
         path: /etc/fstab
         regexp: '.*swap.*'
         state: absent
     ```
[ ] **SSH 設定** PasswordAuthentication no (禁用 SSH 密碼登入)
   - **狀態**: ❌ 未配置
   - **說明**: 沒有配置 SSH 安全強化
   - **建議**: 在 `ansible/roles/common/tasks/main.yml` 中添加 SSH 安全配置
   - **參考配置**:
     ```yaml
     - name: Harden SSH configuration
       become: true
       ansible.builtin.lineinfile:
         path: /etc/ssh/sshd_config
         regexp: '^#?PasswordAuthentication'
         line: 'PasswordAuthentication no'
         state: present
       notify: Restart sshd
     ```
[ ] **自動化檢查 outbound + DNS + ImagePull**
   - **狀態**: ❌ 未配置
   - **說明**: 沒有預檢查任務驗證網路連通性、DNS 解析和容器鏡像拉取
   - **建議**: 在 `ansible/roles/common/tasks/main.yml` 中添加預檢查任務
   - **範例**:
     ```yaml
     - name: Check Internet Connectivity
       ansible.builtin.shell: ping -c1 8.8.8.8
       register: ping_result
       failed_when: ping_result.rc != 0
       changed_when: false

     - name: Check DNS Resolution
       ansible.builtin.shell: nslookup registry.k8s.io
       register: dns_result
       failed_when: dns_result.rc != 0
       changed_when: false

     - name: Test Container Image Pull
       ansible.builtin.shell: crictl pull registry.k8s.io/pause:3.10
       register: pull_result
       failed_when: pull_result.rc != 0
       changed_when: false
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
[x] **kube-vip Deployment manifest（DaemonSet）已放入 GitOps**
   - **狀態**: ✅ 已完成
   - **設定位置**:
     - `argocd/apps/infrastructure/kube-vip/base/kube-vip-daemonset.yaml`
     - `argocd/apps/infrastructure/kube-vip/base/kube-vip-rbac.yaml`
     - `argocd/apps/infrastructure/kube-vip/base/kustomization.yaml`
     - `argocd/apps/infrastructure/kube-vip/overlays/kustomization.yaml`
   - **說明**: kube-vip 已有完整的 GitOps manifest,包含:
     - DaemonSet 配置 (使用 v0.8.9 版本)
     - RBAC 配置 (ServiceAccount, ClusterRole, ClusterRoleBinding)
     - Health probes (readinessProbe + livenessProbe)
     - VIP 配置 (192.168.0.10)
     - Sync wave: -3 (優先於其他基礎設施部署)
   - **注意**: kube-vip 在 Ansible 階段作為 Static Pod 部署於第一個 master,GitOps manifest 用於後續管理
[ ] **Calico Overlay 目前還未區分「bootstrap 與 runtime」兩層 manifest**
   - **狀態**: ❌ 未完成
   - **說明**: Calico 目前只在 Ansible master role 中部署 (一次性),沒有 GitOps manifest
   - **設定位置**: `ansible/roles/master/tasks/main.yml:359-380`
   - **建議**:
     1. 保留 Ansible 部署的 Calico 作為 bootstrap (必要,用於集群初始化)
     2. 在 `argocd/apps/infrastructure/calico/` 創建 GitOps manifest (可選,用於後續配置管理)
     3. 使用 ArgoCD sync-wave 確保不會衝突
   - **參考**: Calico manifest URL: `https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml`
[x] **CNI MTU 已配合 vmbr0 MTU 1500 設定**
   - **狀態**: ✅ 已配置
   - **設定位置**:
     - `ansible/inventory.ini:32` (network_mtu=1500)
     - `ansible/roles/network/templates/netplan-50-custom-network.yaml.j2`
     - `ansible/roles/network/tasks/configure-interfaces.yml`
   - **說明**: MTU 已正確設定為 1500,符合標準網路環境
   - **驗證**: 網路介面配置中已包含 MTU 設定和驗證步驟
   - **注意**: Calico CNI 會自動偵測底層網路 MTU,無需額外配置

# 5. Vault（Phase 5）

[x] **Vault Seal/Unseal 流程正確**
   - **狀態**: ✅ 已記錄
   - **參考文件**: [Phase 5: Vault 初始化](infra-deploy-sop.md#phase-5-vault-初始化)
   - **設定位置**: `argocd/apps/infrastructure/vault/overlays/values.yaml`
   - **說明**: Vault 配置包含:
     - HA 模式 (3 replicas)
     - Raft 儲存後端
     - 自動 retry_join 配置
     - 數據持久化 (10Gi PVC)
     - 稽核日誌 (5Gi PVC)
   - **部署後操作**: 需手動執行 `vault operator init` 和 `vault operator unseal`
   - **注意**: Unseal keys 和 root token 必須安全保存於 Bitwarden/1Password

[~] **Vault Health Probes 配置**
   - **狀態**: ⚠️ 部分完成
   - **設定位置**: `argocd/apps/infrastructure/vault/overlays/charts/vault-0.28.0/vault/values.yaml`
   - **當前配置**:
     - ✅ **readinessProbe**: enabled: true (已啟用)
       - 使用 `vault status -tls-skip-verify` 命令檢查
       - failureThreshold: 2, periodSeconds: 2
     - ❌ **livenessProbe**: enabled: false (預設禁用)
       - 路徑: `/v1/sys/health?standbyok=true`
       - 需在 `argocd/apps/infrastructure/vault/overlays/values.yaml` 中覆蓋啟用
   - **建議配置**:
     ```yaml
     server:
       livenessProbe:
         enabled: true
         path: "/v1/sys/health?standbyok=true"
         port: 8200
         failureThreshold: 2
         initialDelaySeconds: 60  # Vault 需要較長啟動時間
         periodSeconds: 5
         successThreshold: 1
         timeoutSeconds: 3
     ```

[ ] **Vault Backup/Snapshot 配置**
   - **狀態**: ❌ 未配置
   - **說明**: 目前沒有自動化備份/快照機制
   - **建議**:
     1. **手動備份**: 使用 `vault operator raft snapshot save` 命令
     2. **自動化備份**: 創建 CronJob 定期執行快照
     3. **備份儲存**: 將快照保存到外部儲存 (S3/NFS/本地)
   - **參考配置** (創建 `argocd/apps/infrastructure/vault/overlays/backup-cronjob.yaml`):
     ```yaml
     apiVersion: batch/v1
     kind: CronJob
     metadata:
       name: vault-backup
       namespace: vault
     spec:
       schedule: "0 2 * * *"  # 每天凌晨 2 點
       jobTemplate:
         spec:
           template:
             spec:
               serviceAccountName: vault
               containers:
               - name: backup
                 image: hashicorp/vault:1.15.6
                 command:
                 - /bin/sh
                 - -c
                 - |
                   vault operator raft snapshot save /backup/vault-snapshot-$(date +%Y%m%d-%H%M%S).snap
                 env:
                 - name: VAULT_ADDR
                   value: "http://vault-0.vault-internal:8200"
                 volumeMounts:
                 - name: backup
                   mountPath: /backup
               volumes:
               - name: backup
                 persistentVolumeClaim:
                   claimName: vault-backup-pvc
               restartPolicy: OnFailure
     ```
   - **手動執行備份**:
     ```bash
     kubectl exec -n vault vault-0 -- vault operator raft snapshot save /tmp/vault-backup.snap
     kubectl cp vault/vault-0:/tmp/vault-backup.snap ./vault-backup-$(date +%Y%m%d).snap
     ```