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
[x] **swap off 自動設定**
   - **狀態**: ✅ 已完成
   - **設定位置**: `ansible/roles/common/tasks/main.yml:6-27`
   - **實作內容**:
     - 立即禁用 swap (`swapoff -a`)
     - 永久禁用 (修改 /etc/fstab，註解掉 swap 條目)
     - 驗證 swap 已完全禁用
   - **重要性**: Kubernetes 必要條件，確保節點穩定運行
[x] **SSH 安全配置強化**
   - **狀態**: ✅ 已完成
   - **設定位置**: `ansible/roles/common/tasks/main.yml:247-287`
   - **實作內容**:
     - 禁用密碼登入 (PasswordAuthentication no)
     - 禁止 root 密碼登入 (PermitRootLogin prohibit-password)
     - 禁止空密碼 (PermitEmptyPasswords no)
     - 配置驗證 (validate sshd_config 語法)
     - 添加 sshd restart handler
   - **安全性**: 強制使用 SSH 金鑰認證，提高系統安全性
[x] **網路與服務預檢查（部署前驗證）**
   - **狀態**: ✅ 已完成
   - **設定位置**: `ansible/roles/common/tasks/main.yml:136-179`
   - **實作內容**:
     - Internet 連通性檢查 (ping 8.8.8.8)
     - 外部 DNS 解析檢查 (nslookup registry.k8s.io)
     - 內部 DNS 解析檢查 (getent hosts detectviz.internal)
     - 容器鏡像拉取測試 (crictl pull registry.k8s.io/pause:3.10)
     - 顯示檢查結果摘要
   - **好處**: 部署前驗證所有依賴，降低部署失敗率
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
[x] **Calico CNI 架構分層（Bootstrap Only）**
   - **狀態**: ✅ 正確（無需 Runtime Layer）
   - **設定位置**: `ansible/roles/master/tasks/main.yml:359-453`
   - **架構決策**: Bootstrap Only（符合 CNI 特性）
   - **實作內容**:
     - ✅ 下載 Calico v3.27.3 manifest
     - ✅ 修改 Pod CIDR (`10.244.0.0/16`)
     - ✅ 配置 VXLAN MTU (`1450`) - 使用 yq 修改 FELIX_VXLANMTU
     - ✅ 配置 Wireguard MTU (`1450`)
     - ✅ 應用 FelixConfiguration (vxlanMTU, health check, Prometheus metrics)
     - ✅ 等待 CRD 就緒後應用配置
   - **為何不需要 GitOps Layer**:
     1. CNI 是集群網路基礎，必須在 kubeadm init 後立即部署
     2. 一旦部署，通常不需要頻繁更新
     3. 讓 ArgoCD 管理 Calico DaemonSet 風險過高（可能導致網路中斷）
   - **參考**: `ARCHITECTURE_ANALYSIS.md` 第 2 節完整分析
[x] **CNI MTU 完整配置（Host MTU 1500 → VXLAN MTU 1450）**
   - **狀態**: ✅ 已完成
   - **設定位置**:
     - Host 網路: `ansible/inventory.ini:32` (network_mtu=1500)
     - Netplan 配置: `ansible/roles/network/templates/netplan-50-custom-network.yaml.j2`
     - Calico VXLAN MTU: `ansible/roles/master/tasks/main.yml:376-406`
     - FelixConfiguration: `ansible/roles/master/templates/felix-configuration.yaml.j2`
   - **完整實作**:
     - ✅ Host 網路 MTU: 1500 (eth0 + eth1)
     - ✅ Calico VXLAN MTU: 1450 (1500 - 50 bytes VXLAN overhead)
     - ✅ FELIX_VXLANMTU: 1450 (環境變數)
     - ✅ FELIX_WIREGUARDMTU: 1450 (環境變數)
     - ✅ FelixConfiguration: vxlanMTU=1450 (CRD 資源)
   - **網路模式**: VXLAN Always (虛擬化環境必要，無法使用 BGP)
   - **驗證**:
     ```bash
     # 檢查 Calico MTU
     kubectl get daemonset calico-node -n kube-system -o yaml | grep -A 2 FELIX_VXLANMTU
     # 檢查 FelixConfiguration
     kubectl get felixconfiguration default -o yaml
     ```
   - **參考**: README.md MTU 已修正為 1450

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

[x] **Vault Health Probes 配置**
   - **狀態**: ✅ 已完成
   - **設定位置**: `argocd/apps/infrastructure/vault/overlays/values.yaml:100-109`
   - **完整配置**:
     - ✅ **readinessProbe**: enabled: true (已啟用)
       - 使用 `vault status -tls-skip-verify` 命令檢查
       - failureThreshold: 2, periodSeconds: 2
     - ✅ **livenessProbe**: enabled: true (已啟用)
       - 路徑: `/v1/sys/health?standbyok=true`
       - initialDelaySeconds: 60 (Vault 需要較長啟動時間)
       - periodSeconds: 5, failureThreshold: 2
   - **好處**: 提高 Vault 可用性監控，自動重啟異常 Pod

[x] **Vault 自動備份 CronJob 配置**
   - **狀態**: ✅ 已完成
   - **設定位置**:
     - CronJob 定義: `argocd/apps/infrastructure/vault/overlays/backup-cronjob.yaml`
     - Kustomization: `argocd/apps/infrastructure/vault/overlays/kustomization.yaml:4-5`
   - **完整實作**:
     - ✅ **CronJob 排程**: 每天凌晨 2 點執行 (`0 2 * * *`)
     - ✅ **備份儲存**: 20Gi PVC (vault-backup-pvc, topolvm-provisioner)
     - ✅ **備份腳本**: Raft snapshot + 自動清理 30 天前舊備份
     - ✅ **RBAC**: ServiceAccount, Role, RoleBinding 完整配置
     - ✅ **安全性**: Pod Security Standards 合規 (runAsNonRoot, drop ALL capabilities)
     - ✅ **歷史記錄**: 保留最近 7 次成功 + 3 次失敗記錄
   - **備份流程**:
     1. 檢查 Vault 狀態 (sealed/unsealed)
     2. 執行 `vault operator raft snapshot save`
     3. 驗證備份檔案
     4. 清理超過 30 天的舊備份
     5. 列出當前所有備份
   - **手動備份命令** (緊急情況使用):
     ```bash
     kubectl exec -n vault vault-0 -- vault operator raft snapshot save /tmp/vault-backup.snap
     kubectl cp vault/vault-0:/tmp/vault-backup.snap ./vault-backup-$(date +%Y%m%d).snap
     ```
   - **驗證備份**:
     ```bash
     # 檢查 CronJob
     kubectl get cronjob vault-backup -n vault
     # 檢查最近的 Job
     kubectl get jobs -n vault -l app.kubernetes.io/name=vault-backup
     # 檢查備份檔案
     kubectl exec -n vault vault-0 -- ls -lh /backup/
     ```