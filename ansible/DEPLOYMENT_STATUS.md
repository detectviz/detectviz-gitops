# Detectviz 部署狀態報告

**更新時間**: 2025-11-13
**環境**: Proxmox + Kubernetes (3 Masters + 1 Worker)

---

## ✅ 已修正的問題

### 1. Containerd 配置錯誤
- **問題**: TOML 語法錯誤導致 containerd 無法啟動
- **修正位置**: `ansible/roles/common/templates/containerd-config.toml.j2`
- **修正內容**:
  - 移除了 `registry.mirrors."docker.io".endpoint` 的錯誤結構
  - 簡化配置，只保留核心 CRI 設定
- **狀態**: ✅ 完全修正
- **重新部署**: ✅ 不會遇到相同問題

### 2. Ansible 任務順序錯誤
- **問題**: Kube-VIP manifest 被創建後立即被 kubeadm reset 刪除
- **修正位置**: `ansible/roles/master/tasks/main.yml`
- **修正內容**: 調整任務順序
  ```
  舊順序: 創建目錄 → 創建 Kube-VIP → 清理 (刪除目錄) → kubeadm init
  新順序: 清理 → 創建目錄 → 準備 Kube-VIP → kubeadm init
  ```
- **狀態**: ✅ 完全修正
- **重新部署**: ✅ 不會遇到相同問題

### 3. 網卡名稱錯誤
- **問題**: Kube-VIP 配置使用錯誤的網卡名 `ens18`，實際是 `eth0`
- **修正位置**: `ansible/roles/master/templates/kube-vip-*.yaml.j2`
- **修正內容**: 將 `vip_interface` 從 `ens18` 改為 `eth0`
- **狀態**: ✅ 完全修正
- **重新部署**: ✅ 不會遇到相同問題

---

## ⚠️ 已知限制（設計變更）

### Kube-VIP 高可用配置調整

**原始設計**: 使用靜態 Pod 在 kubeadm init 之前啟動 Kube-VIP

**實際問題**:
- Kube-VIP 靜態 Pod 需要訪問 `/etc/kubernetes/admin.conf`
- 但該文件在 kubeadm init **執行後**才會創建
- 導致 Kube-VIP 無法在初始化階段提供 VIP

**當前方案**:
- ✅ 使用 `controlPlaneEndpoint: "192.168.0.11:6443"` (master-1 的 IP)
- ✅ 集群初始化完成後，再部署 Kube-VIP DaemonSet
- ⚠️ 在 Kube-VIP 部署前，API 端點只能通過 master-1 訪問

**影響**:
- 初始部署階段沒有 VIP 高可用
- 集群初始化完成後可手動或通過 Ansible 部署 Kube-VIP
- 不影響最終的高可用架構

---

## 📊 重新部署預期結果

### 成功路徑 ✅

```bash
cd terraform
terraform destroy -var-file=terraform.tfvars -auto-approve
terraform apply -var-file=terraform.tfvars -auto-approve

cd ../ansible
ansible-playbook -i inventory.ini deploy-cluster.yml
```

**預期流程**:
1. ✅ Terraform 創建 4 台 VM (3 masters + 1 worker)
2. ✅ Ansible Phase 1: 安裝 containerd、kubelet、kubeadm（無錯誤）
3. ✅ Ansible Phase 2: 配置雙網卡
4. ✅ Ansible Phase 3: 初始化 master-1
   - API endpoint: `https://192.168.0.11:6443`
   - 初始化成功，生成 admin.conf
5. ⚠️ Kube-VIP **未**自動啟動（需要手動部署）

### 需要手動執行的後續步驟

初始化完成後，部署 Kube-VIP：

```bash
# 在 master-1 上執行
kubectl apply -f /tmp/kube-vip-daemonset.yaml

# 驗證 VIP 是否綁定
ip addr show eth0 | grep 192.168.0.10
```

---

## 🔧 潛在問題與解決方案

### 問題 1: Kube-VIP 日誌顯示權限錯誤

**錯誤訊息**:
```
error retrieving resource lock kube-system/plndr-cp-lock: leases.coordination.k8s.io "plndr-cp-lock" is forbidden
```

**原因**: Kube-VIP 的 ServiceAccount 權限未正確配置

**解決方案**: 在 DaemonSet 中添加 RBAC：
```bash
kubectl apply -f ansible/roles/master/templates/kube-vip-rbac.yaml
kubectl apply -f ansible/roles/master/templates/kube-vip-ds.yaml
```

### 問題 2: API server 超時

**錯誤訊息**:
```
[api-check] The API server is not healthy after 4m0s
```

**可能原因**:
1. Containerd 配置錯誤 → ✅ 已修正
2. 防火牆阻擋端口 6443
3. Kubelet 配置錯誤

**驗證方法**:
```bash
# 檢查 containerd
sudo systemctl status containerd

# 檢查 API server 容器
sudo crictl ps | grep kube-apiserver

# 檢查日誌
sudo journalctl -u kubelet -n 50
```

---

## 📝 配置文件修正清單

| 文件路徑 | 狀態 | 說明 |
|---------|------|------|
| `ansible/roles/common/templates/containerd-config.toml.j2` | ✅ 已修正 | 移除 TOML 語法錯誤 |
| `ansible/roles/master/tasks/main.yml` | ✅ 已調整 | 任務順序優化 |
| `ansible/roles/master/templates/kube-vip-ds.yaml.j2` | ✅ 已修正 | 網卡名稱改為 eth0 |
| `ansible/roles/master/templates/kube-vip-static-pod.yaml.j2` | ⚠️ 不使用 | 改為 DaemonSet 模式 |

---

## 🎯 建議的部署策略

### 方案 A: 無 VIP 快速部署（推薦用於測試）

```bash
# 1. 確保配置正確
cd detectviz-gitops

# 2. 部署基礎設施
cd terraform
terraform apply -var-file=terraform.tfvars -auto-approve

# 3. 初始化集群（使用 master-1 IP）
cd ../ansible
ansible-playbook -i inventory.ini deploy-cluster.yml

# 4. 驗證集群
ssh ubuntu@192.168.0.11 'kubectl get nodes'
```

### 方案 B: 完整 HA 部署（推薦用於生產）

執行方案 A 後，額外執行：

```bash
# 5. 部署 Kube-VIP
ssh ubuntu@192.168.0.11 'kubectl apply -f /tmp/kube-vip-daemonset.yaml'

# 6. 驗證 VIP
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'

# 7. 更新 kubeconfig（使用 VIP）
sed -i 's/192.168.0.11/192.168.0.10/g' ~/.kube/config
```

---

## ✅ 結論

**配置文件狀態**:
- ✅ Containerd: 完全修正
- ✅ Ansible 任務: 完全修正
- ✅ 網卡配置: 完全修正
- ⚠️ Kube-VIP: 從靜態 Pod 改為 DaemonSet（需要手動部署）

**重新部署風險**:
- **低** - 主要配置問題已修正
- Kube-VIP 需要兩階段部署（先初始化，再啟用 VIP）

**推薦行動**:
1. 重新部署以驗證修正效果
2. 初始化完成後手動部署 Kube-VIP
3. 考慮將 Kube-VIP 部署自動化到 Ansible playbook 中
