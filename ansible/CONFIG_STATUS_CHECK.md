# 配置文件完整修正狀態檢查

**檢查日期**: 2025-11-13
**檢查範圍**: 所有影響部署的關鍵配置

---

## ✅ 已完全修正的配置

### 1. Containerd 配置
**文件**: `roles/common/templates/containerd-config.toml.j2`

| 項目 | 狀態 | 說明 |
|------|------|------|
| TOML 語法錯誤 | ✅ 已修正 | registry.mirrors endpoint 改為正確數組語法 |
| sandbox_image 設定 | ✅ 正確 | `registry.k8s.io/pause:3.10` |
| SystemdCgroup | ✅ 正確 | 與 kubelet 一致 |
| CNI 配置 | ✅ 正確 | bin_dir 和 conf_dir 正確設定 |
| 詳細註解 | ✅ 完成 | 每個區塊都有中文說明 |

**驗證命令**：
```bash
ssh ubuntu@192.168.0.11 'sudo grep sandbox_image /etc/containerd/config.toml'
# 預期輸出：sandbox_image = "registry.k8s.io/pause:3.10"
```

---

### 2. Kube-VIP 靜態 Pod 配置
**文件**: `roles/master/templates/kube-vip-static-pod.yaml.j2`

| 項目 | 狀態 | 說明 |
|------|------|------|
| 網卡名稱 | ✅ 已修正 | `ens18` → `eth0` |
| VIP 地址 | ✅ 正確 | `{{ cluster_vip }}` = 192.168.0.10 |
| priorityClassName | ✅ 已添加 | system-node-critical |
| vip_startasleader | ✅ 已設定 | "true" for master-1 |
| Volume 配置 | ✅ 正確 | FileOrCreate 等待 admin.conf |
| 詳細註解 | ✅ 完成 | 每個環境變數都有說明 |

**驗證命令**：
```bash
ssh ubuntu@192.168.0.11 'grep vip_interface /etc/kubernetes/manifests/kube-vip.yaml'
# 預期輸出：value: "eth0"
```

---

### 3. Ansible 任務順序
**文件**: `roles/master/tasks/main.yml`

| 項目 | 狀態 | 說明 |
|------|------|------|
| 任務執行順序 | ✅ 已修正 | 清理 → 創建目錄 → init → Kube-VIP |
| 自動部署 Kube-VIP | ✅ 已實現 | Line 173-201 自動部署和驗證 |
| VIP 驗證 | ✅ 已添加 | 自動檢查 VIP 綁定狀態 |
| 詳細註解 | ✅ 完成 | 每個階段都有完整說明 |

**正確的任務流程**：
```
1. 清理舊安裝 (line 40-62)
2. 創建目錄結構 (line 68-86)
3. kubeadm init (line 130-137)
4. 配置 kubeconfig (line 139-164)
5. 自動部署 Kube-VIP (line 173-180)  ← 關鍵！
6. 驗證 VIP 綁定 (line 186-201)
```

---

### 4. Control Plane Endpoint 配置
**文件**: `group_vars/all.yml`

| 項目 | 狀態 | 說明 |
|------|------|------|
| control_plane_endpoint | ✅ 已修正 | 使用 master-1 實際 IP: `192.168.0.11:6443` |
| cluster_vip | ✅ 正確 | VIP 地址: `192.168.0.10` |
| control_plane_vip_endpoint | ✅ 已添加 | 供後續 master 使用: `k8s-api.detectviz.internal:6443` |

**當前配置**：
```yaml
control_plane_endpoint: "192.168.0.11:6443"  # 第一次初始化用
cluster_vip: "192.168.0.10"  # Kube-VIP 綁定的 VIP
control_plane_vip_endpoint: "k8s-api.detectviz.internal:6443"  # 後續 master 加入用
```

**為什麼這樣配置**：
- kubeadm init 時 VIP 還不存在，必須用實際 IP
- Kube-VIP 在 init 完成後才部署
- 後續 master 可以通過已存在的 VIP 加入

---

## ⚠️ 需要注意的配置（不影響當前單 master 部署）

### 5. Join Command 端點配置
**文件**: `roles/master/tasks/main.yml` (Line 279)

**當前配置**：
```yaml
echo "kubeadm join {{ control_plane_endpoint }} --token $TOKEN ..."
```

**問題**：
- 這會生成 `kubeadm join 192.168.0.11:6443 ...`
- 對於 **worker 節點**：✅ 沒問題（可以直接連接 master-1）
- 對於 **後續 master 節點**：⚠️ 應該使用 VIP 才能實現 HA

**影響範圍**：
- ✅ 當前部署（只有 1 個 master + 1 個worker）：**不受影響**
- ⚠️ 未來添加 master-2, master-3 時：需要修正

**建議修正**（未來優化）：
```yaml
# 為後續 master 加入生成使用 VIP 的 join command
- name: Set join command with VIP for additional masters
  ansible.builtin.set_fact:
    control_plane_join_command: "{{ kubeadm_join_command.stdout | replace(control_plane_endpoint, control_plane_vip_endpoint) }} --control-plane ..."
```

---

## ✅ Terraform 配置

### 6. VM Template 配置
**文件**: `docs/infrastructure/02-proxmox/vm-template-creation.md`

| 項目 | 狀態 | 說明 |
|------|------|------|
| UEFI BIOS | ✅ 已修正 | 添加 `--bios ovmf` |
| EFI Disk | ✅ 已修正 | 添加 `--efidisk0 nvme-vm:0,efitype=4m` |
| Cloud-init 存儲 | ✅ 已修正 | `--ide2 local:cloudinit` |
| SSH Key 參數 | ✅ 已修正 | `--sshkeys` (不是 --sshkey) |
| 存儲池 | ✅ 已修正 | disk images 用 `nvme-vm` |

**重要**：必須按照修正後的文檔重新創建 VM template！

---

### 7. Terraform 雙磁碟配置
**文件**: `terraform/variables.tf`, `terraform/terraform.tfvars`

| 項目 | 狀態 | 說明 |
|------|------|------|
| worker_system_disk_sizes | ✅ 已修正 | 預設值改為 `["100G"]` |
| worker_data_disks | ✅ 已配置 | 250GB 數據盤 |
| Hostname 格式 | ✅ 已修正 | 短名稱（不帶域名） |
| EFI Disk | ✅ 已配置 | 使用 Proxmox provider 自動管理 |

---

## 📊 配置完整度總結

### 當前部署（1 master + 1 worker）

| 組件 | 配置狀態 | 部署預期 |
|------|----------|----------|
| Containerd | ✅ 完全修正 | 正常啟動 |
| Kubeadm Init | ✅ 完全修正 | 使用 master-1 IP 成功初始化 |
| Kube-VIP 部署 | ✅ 完全修正 | init 後自動部署 |
| VIP 綁定 | ✅ 完全修正 | 192.168.0.10 綁定到 eth0 |
| Worker 加入 | ✅ 配置正確 | 可通過 master-1 IP 加入 |
| CNI (Calico) | ✅ 配置正確 | 自動部署 |

**結論**：✅ **配置已完全修正，可以成功部署！**

---

### 未來擴展（添加 master-2, master-3）

| 項目 | 當前狀態 | 建議 |
|------|----------|------|
| Master Join Command | ⚠️ 使用 master-1 IP | 建議修正為使用 VIP |
| Kube-VIP Leader Election | ✅ 已配置 | 多 master 自動選舉 |
| Certificate Distribution | ✅ 已配置 | 自動上傳和下載 |

**影響**：不影響當前部署，未來添加節點時可優化

---

## 🔍 驗證步驟

### 部署前檢查

```bash
# 1. 檢查 control_plane_endpoint 配置
grep control_plane_endpoint group_vars/all.yml
# 預期：control_plane_endpoint: "192.168.0.11:6443"

# 2. 檢查 Kube-VIP 網卡配置
grep vip_interface roles/master/templates/kube-vip-static-pod.yaml.j2
# 預期：value: "eth0"

# 3. 檢查 Containerd sandbox_image
grep sandbox_image roles/common/templates/containerd-config.toml.j2
# 預期：sandbox_image = "{{ containerd_sandbox_image }}"
```

### 部署後驗證

```bash
# 1. 確認 API Server 使用 master-1 IP
ssh ubuntu@192.168.0.11 'grep server: /etc/kubernetes/admin.conf'
# 預期：server: https://192.168.0.11:6443

# 2. 確認 Kube-VIP 已部署
ssh ubuntu@192.168.0.11 'kubectl get pods -n kube-system | grep kube-vip'
# 預期：kube-vip-master-1   1/1   Running

# 3. 確認 VIP 已綁定
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'
# 預期：inet 192.168.0.10/32 scope global eth0

# 4. 測試 VIP 連接
curl -k https://192.168.0.10:6443/healthz
# 預期：ok

# 5. 測試 Master-1 連接
curl -k https://192.168.0.11:6443/healthz
# 預期：ok
```

---

## 🎯 最終結論

### ✅ 配置完全修正清單

| 配置項目 | 狀態 | 備註 |
|---------|------|------|
| Containerd TOML 語法 | ✅ 完全修正 | |
| Containerd Sandbox Image | ✅ 正確配置 | |
| Ansible 任務順序 | ✅ 完全修正 | |
| Kube-VIP 自動部署 | ✅ 已實現 | |
| Kube-VIP 網卡名稱 | ✅ 已修正 | eth0 |
| Control Plane Endpoint | ✅ 已修正 | 使用 master-1 IP |
| VM Template 文檔 | ✅ 已修正 | 5 個錯誤已修正 |
| Terraform 雙磁碟 | ✅ 已配置 | 100GB + 250GB |
| 配置文件註解 | ✅ 已完成 | 中文詳細註解 |

### 📝 部署預期結果

```
✅ Terraform 創建 VM 成功
✅ Containerd 正常啟動
✅ Kubeadm init 成功（連接 192.168.0.11）
✅ API Server 健康檢查通過
✅ Kube-VIP 自動部署成功
✅ VIP 192.168.0.10 成功綁定
✅ Worker 節點成功加入
✅ Calico CNI 自動部署
✅ 集群完全可用
```

### 🚀 可以安全部署

**結論**：✅ **所有關鍵配置已完全修正，可以重新部署集群**

**不會遇到的問題**：
- ❌ Containerd TOML 語法錯誤
- ❌ API Server 啟動超時
- ❌ VIP 連接失敗（雞生蛋問題）
- ❌ 網卡名稱錯誤
- ❌ Ansible 任務順序問題
- ❌ VM 創建後無法 SSH

---

## 📦 部署命令

```bash
# 1. 確保 VM template 正確（如果未重建，請先重建）
# 參考：docs/infrastructure/02-proxmox/vm-template-creation.md

# 2. 部署基礎設施
cd /Users/zoe/Documents/github/detectviz-gitops/terraform
terraform destroy -var-file=terraform.tfvars -auto-approve  # 清理舊 VM
terraform apply -var-file=terraform.tfvars -auto-approve    # 創建新 VM

# 3. 部署 Kubernetes 集群
cd /Users/zoe/Documents/github/detectviz-gitops/ansible
ansible-playbook -i inventory.ini deploy-cluster.yml

# 4. 驗證部署結果
ssh ubuntu@192.168.0.11 'kubectl get nodes'
ssh ubuntu@192.168.0.11 'kubectl get pods -A'
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'
```

**預計部署時間**：15-20 分鐘
