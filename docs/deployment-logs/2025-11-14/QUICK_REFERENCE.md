# Detectviz Kubernetes 集群 - 快速參考

**最後更新**: 2025-11-13
**集群狀態**: ✅ 完全可用

---

## 🚀 快速部署

```bash
# 1. 部署基礎設施
cd /Users/zoe/Documents/github/detectviz-gitops/terraform
terraform apply -var-file=terraform.tfvars -auto-approve

# 2. 部署 Kubernetes 集群
cd /Users/zoe/Documents/github/detectviz-gitops/ansible
ansible-playbook -i inventory.ini deploy-cluster.yml

# 3. 驗證
ssh ubuntu@192.168.0.11 'kubectl get nodes'
curl -k https://192.168.0.10:6443/healthz
```

**部署時間**: 約 15-20 分鐘

---

## 🔧 常用命令

### 集群訪問

```bash
# SSH 到 master-1
ssh ubuntu@192.168.0.11

# 在本地使用 kubectl（需要先拷貝 kubeconfig）
scp ubuntu@192.168.0.11:/etc/kubernetes/admin.conf ~/.kube/config
kubectl get nodes
```

### 檢查狀態

```bash
# 檢查所有節點
kubectl get nodes -o wide

# 檢查所有 Pod
kubectl get pods -A

# 檢查系統組件
kubectl get pods -n kube-system

# 檢查 VIP 綁定
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'
```

### API 訪問

```bash
# 通過 VIP 訪問
curl -k https://192.168.0.10:6443/healthz

# 通過 master-1 訪問
curl -k https://192.168.0.11:6443/healthz
```

---

## 📋 集群配置

### 網路配置

| 項目 | 值 | 說明 |
|------|-----|------|
| Pod CIDR | 10.244.0.0/16 | Pod 網路範圍 |
| Service CIDR | 10.96.0.0/12 | Service 網路範圍 |
| VIP | 192.168.0.10 | Control Plane VIP |
| Master-1 IP | 192.168.0.11 | 第一個 master 節點 |
| Master-2 IP | 192.168.0.12 | 第二個 master 節點 |
| Master-3 IP | 192.168.0.13 | 第三個 master 節點 |
| Worker IP | 192.168.0.14 | Worker 節點 |

### 組件版本

| 組件 | 版本 |
|------|------|
| Kubernetes | 1.32.0 |
| Containerd | 2.1.5 |
| Calico | 3.27.3 |
| Kube-VIP | 0.7.1 |
| Ubuntu | 22.04.5 LTS |

---

## 🔍 故障排除

### 節點 NotReady

```bash
# 檢查 kubelet 狀態
ssh ubuntu@192.168.0.11 'sudo systemctl status kubelet'

# 檢查 kubelet 日誌
ssh ubuntu@192.168.0.11 'sudo journalctl -u kubelet -n 50'

# 檢查網路插件
kubectl get pods -n kube-system -l k8s-app=calico-node
```

### VIP 未綁定

```bash
# 檢查 VIP
ssh ubuntu@192.168.0.11 'ip addr show eth0 | grep 192.168.0.10'

# 手動綁定 VIP
ssh ubuntu@192.168.0.11 'sudo ip addr add 192.168.0.10/32 dev eth0'

# 檢查 Kube-VIP Pod
kubectl get pods -n kube-system -l app=kube-vip
kubectl logs -n kube-system -l app=kube-vip
```

### Pod 無法啟動

```bash
# 檢查 Pod 狀態
kubectl describe pod <pod-name> -n <namespace>

# 檢查 Pod 日誌
kubectl logs <pod-name> -n <namespace>

# 檢查 events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### API Server 無法訪問

```bash
# 檢查 API Server Pod
kubectl get pods -n kube-system -l component=kube-apiserver

# 檢查 API Server 日誌
ssh ubuntu@192.168.0.11 'sudo crictl logs $(sudo crictl ps -a | grep kube-apiserver | awk "{print \$1}")'

# 檢查證書
ssh ubuntu@192.168.0.11 'sudo kubeadm certs check-expiration'
```

---

## 📚 文檔索引

### 配置和修正

- **`FIXES_APPLIED.md`** - 已應用的所有修正總結
- **`KUBE_VIP_ISSUES.md`** - Kube-VIP 問題詳細分析
- **`CONFIG_STATUS_CHECK.md`** - 配置完整性檢查清單
- **`CONFIG_CHANGES_SUMMARY.md`** - 配置修正和註解總結
- **`MULTI_MASTER_JOIN_FIX.md`** - 多 Master 加入配置指南

### 部署和狀態

- **`DEPLOYMENT_STATUS.md`** - 部署狀態和已知限制
- **`update.md`** - API Server 啟動失敗問題診斷
- **`FINAL_CONFIG_SUMMARY.md`** - 最終配置修正總結

### 基礎設施

- **`docs/infrastructure/02-proxmox/vm-template-creation.md`** - VM Template 創建指南
- **`terraform/TROUBLESHOOTING.md`** - Terraform 故障排除
- **`terraform/FIX_TEMPLATE.md`** - VM Template 修正指南

---

## 🎯 下一步

### 立即可做

1. ✅ **部署應用** - 集群已就緒，可以開始部署應用
2. ✅ **添加 Worker** - 使用生成的 worker join command
3. ⏳ **添加 Master-2/3** - 使用生成的 master join command

### 後續優化

1. 🔄 **Kube-VIP DaemonSet** - 切換到更可靠的部署模式
2. 🔄 **持久化 VIP** - 確保重啟後 VIP 自動綁定
3. 🔄 **監控部署** - Prometheus + Grafana
4. 🔄 **日誌收集** - ELK Stack 或 Loki

---

## 📞 支持

### 問題回報

如遇問題，請提供以下信息：

```bash
# 收集診斷信息
kubectl get nodes -o wide > cluster-nodes.txt
kubectl get pods -A > cluster-pods.txt
kubectl get events -A --sort-by='.lastTimestamp' > cluster-events.txt

# 收集日誌
ssh ubuntu@192.168.0.11 'sudo journalctl -u kubelet -n 200' > kubelet.log
ssh ubuntu@192.168.0.11 'sudo journalctl -u containerd -n 200' > containerd.log
```

### 常見問題

**Q: VIP 重啟後消失？**
A: 目前 VIP 是手動綁定的，重啟後需要重新執行綁定命令。建議切換到 Kube-VIP DaemonSet 模式。

**Q: 如何添加新節點？**
A: 在 master-1 上運行 `kubeadm token create --print-join-command` 獲取 join command。

**Q: Master-2 加入失敗？**
A: 確保使用的是包含 `--control-plane` 和 `--certificate-key` 的完整 join command。

**Q: Calico Pod CrashLoop？**
A: 確保 kube-proxy 已部署（檢查是否有 `--skip-phases=addon/kube-proxy`）。

---

## ✅ 驗證清單

部署後驗證：

- [ ] 所有節點 Status = Ready
- [ ] 所有系統 Pod Status = Running
- [ ] VIP (192.168.0.10) 可訪問
- [ ] Master-1 (192.168.0.11) 可訪問
- [ ] CoreDNS Pod 正常運行
- [ ] Calico Pod 正常運行
- [ ] kube-proxy DaemonSet 已部署
- [ ] 可以創建 Pod

**集群健康檢查**:
```bash
kubectl get --raw='/readyz?verbose' | grep 'check passed'
kubectl get componentstatuses  # 已廢棄但仍可參考
```

---

## 🎉 集群已就緒！

您的 Kubernetes 集群已完全配置並可用。可以開始部署應用了！

**快速測試**:
```bash
# 創建測試 Pod
kubectl run nginx --image=nginx --port=80

# 檢查 Pod 狀態
kubectl get pod nginx -o wide

# 清理測試 Pod
kubectl delete pod nginx
```
