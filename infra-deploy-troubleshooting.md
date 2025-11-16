## 故障排除

### 常見問題

#### 1. Terraform 部署失敗

**問題**: VM 創建失敗或網路配置錯誤

**解決方案**:

```bash
# 檢查 Proxmox 橋接器
ssh root@192.168.0.2 'ip link show vmbr0'
ssh root@192.168.0.2 'ip link show vmbr1'

# 清理失敗的 VM
cd terraform/
./cleanup-failed-vms.sh

# 重新部署
terraform apply -auto-approve
```

#### 2. 網路連通性問題

**問題**: VM 之間無法通訊或 DNS 無法解析

**解決方案**:

```bash
# 檢查 VM 網路介面
ssh ubuntu@192.168.0.11 'ip addr show'

# 檢查路由
ssh ubuntu@192.168.0.11 'ip route'

# 檢查 DNS
ssh ubuntu@192.168.0.11 'cat /etc/resolv.conf'
ssh ubuntu@192.168.0.11 'nslookup master-1.detectviz.internal'

# 重新執行網路配置
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags network
```

#### 3. sysctl 參數未生效

**問題**: rp_filter 或 ip_forward 未正確設定

**解決方案**:

```bash
# 在 Proxmox 檢查
ssh root@192.168.0.2 'sysctl net.ipv4.conf.all.rp_filter'
ssh root@192.168.0.2 'sysctl net.ipv4.ip_forward'

# 在 VM 檢查
ssh ubuntu@192.168.0.11 'sudo sysctl net.ipv4.conf.all.rp_filter'
ssh ubuntu@192.168.0.11 'sudo sysctl net.ipv4.ip_forward'

# 如果不正確，重新應用
ssh ubuntu@192.168.0.11 'sudo sysctl --system'
```

#### 4. Kubernetes 節點未就緒

**問題**: 節點顯示 NotReady 狀態

**解決方案**:

```bash
# 檢查節點狀態
kubectl get nodes -o wide
kubectl describe node <node-name>

# 檢查 kubelet 日誌
ssh ubuntu@<node-ip> 'sudo journalctl -u kubelet -n 100 --no-pager'

# 檢查 CNI 狀態
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl get pods -n kube-system -l k8s-app=calico-node
```

#### 5. ArgoCD 應用同步失敗

**問題**: 應用顯示 OutOfSync 或 Degraded

**解決方案**:

```bash
# 檢查應用狀態
argocd app get <app-name>

# 查看詳細錯誤
kubectl describe application <app-name> -n argocd

# 手動同步
argocd app sync <app-name> --force

# 重置應用
argocd app delete <app-name>
argocd app create <app-name> ...
```

#### 6. ApplicationSet 路徑錯誤（雞生蛋問題 #1）

**症狀**:
```
ComparisonError: Failed to load target state: failed to generate manifest
apps/infrastructure/cert-manager/overlays: app path does not exist
```

**根本原因**: ApplicationSet 生成的應用路徑缺少 `argocd/` 前綴

**診斷**:
```bash
# 檢查 Application 的實際路徑
kubectl get application infra-cert-manager -n argocd -o jsonpath='{.spec.source.path}'
# 錯誤輸出: apps/infrastructure/cert-manager/overlays
# 正確輸出: argocd/apps/infrastructure/cert-manager/overlays

# 檢查 ApplicationSet 配置
kubectl get applicationset detectviz-gitops -n argocd -o yaml | grep -A 2 "path:"
```

**解決方案**:

1. 修正 `argocd/appsets/appset.yaml`:
```yaml
elements:
  - appName: cert-manager
    path: argocd/apps/infrastructure/cert-manager/overlays  # 添加 argocd/ 前綴
```

2. 提交並推送修改
3. 刷新 root application:
```bash
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

**預防措施**: 所有 ApplicationSet 中的路徑都應包含 `argocd/` 前綴

---

#### 7. AppProject 權限不足（雞生蛋問題 #2）

**症狀**:
```
resource :Namespace is not permitted in project platform-bootstrap
resource :IngressClass is not permitted in project platform-bootstrap
```

**根本原因**: AppProject `platform-bootstrap` 的 `clusterResourceWhitelist` 缺少必要資源

**診斷**:
```bash
# 檢查 Application 錯誤
kubectl get application infra-cert-manager -n argocd -o yaml | grep -A 10 "conditions:"

# 檢查 AppProject 白名單
kubectl get appproject platform-bootstrap -n argocd -o yaml | grep -A 20 "clusterResourceWhitelist"
```

**解決方案**:

修正 `argocd/bootstrap/argocd-projects.yaml`:
```yaml
clusterResourceWhitelist:
  - group: ""
    kind: Namespace       # 添加 Namespace
  - group: networking.k8s.io
    kind: IngressClass    # 添加 IngressClass
  - group: apiextensions.k8s.io
    kind: CustomResourceDefinition
  # ... 其他資源
```

**預防措施**: 在添加新基礎設施組件前，確認 AppProject 已包含所需的資源類型

---

#### 8. cluster-bootstrap CRD 依賴問題（雞生蛋問題 #3）

**症狀**:
```
cluster-bootstrap: OutOfSync, Progressing
no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

**根本原因**: cluster-bootstrap Phase 2 資源（Certificates, Ingress）依賴尚未部署的 CRDs

**這是正常且預期的行為！**

**解決方案**（已內建於部署流程）:

1. **Phase 1** (Sync Wave: -10): Namespaces → 立即成功 ✅
2. **Phase 2** (Sync Wave: 10): Certificates, Ingress → 失敗（CRDs 不存在）⚠️
3. **手動同步基礎設施**: cert-manager, ingress-nginx → CRDs 安裝 ✅
4. **Phase 2 自動重試**: Certificates, Ingress → 成功 ✅

**驗證**:
```bash
# 基礎設施同步前
kubectl get application cluster-bootstrap -n argocd
# 預期: OutOfSync, Progressing ⚠️ 這是正常的!

# 基礎設施同步後
kubectl get application cluster-bootstrap -n argocd
# 預期: Synced, Healthy ✅
```

**關鍵設定**（已配置）:
```yaml
# argocd/bootstrap/manifests/*.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
    argocd.argoproj.io/sync-wave: "10"  # 延後部署
```

---

#### 9. TopoLVM Pod 無法調度（雞生蛋問題 #4）

**症狀**:
```
Vault pods: Pending
Events: 0/1 nodes are available: 1 Insufficient topolvm.io/capacity
實際節點容量: 240GB
需求: 45GB
```

**根本原因**: 使用 Scheduler Extender 模式但 kube-scheduler 未配置 extender endpoint

**診斷**:
```bash
# 檢查 Pod 資源請求
kubectl get pod vault-0 -n vault -o yaml | grep "topolvm.io/capacity"
# 錯誤: topolvm.io/capacity: "1"  (僅 1 byte!)

# 檢查節點 annotation
kubectl get node app-worker -o jsonpath='{.metadata.annotations}' | grep topolvm
# 正確: capacity.topolvm.io/00default: "257693843456"  (240GB)

# 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 舊模式: No resources found  ❌
# 新模式: 應該顯示 topolvm 容量 ✅
```

**解決方案**（已實施）:

改用 **Storage Capacity Tracking** 模式（`argocd/apps/infrastructure/topolvm/overlays/values.yaml`）:

```yaml
scheduler:
  enabled: false  # 禁用 scheduler extender

controller:
  storageCapacityTracking:
    enabled: true  # 啟用 Storage Capacity Tracking

webhook:
  podMutatingWebhook:
    enabled: false  # 不需要 pod webhook
```

**重新部署後驗證**:
```bash
# 1. 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 預期: 應該看到 topolvm-provisioner 的容量資源

# 2. 檢查 topolvm-scheduler DaemonSet 不應存在
kubectl get daemonset -n kube-system topolvm-scheduler
# 預期: Error from server (NotFound)  ✅

# 3. 刪除舊 Vault pods 讓它們重建（清除舊 webhook mutations）
kubectl delete pod -n vault --all

# 4. 檢查新 pods 是否成功調度
kubectl get pods -n vault -o wide
# 預期: Running 狀態，調度到 app-worker
```

**為什麼這個方案更好**:
- ✅ Kubernetes 原生功能（1.21+ GA）
- ✅ 無需修改 kube-scheduler 配置
- ✅ 自動容量追蹤和更新
- ✅ 更簡單、更可靠的調度機制

---

#### 11. Ingress-Nginx LoadBalancer 無法分配 IP

**症狀**:
- ingress-nginx-controller 服務 EXTERNAL-IP 顯示 `<pending>`
- 無法訪問 https://argocd.detectviz.internal
- curl 連接被拒絕 (Connection refused)
- 所有通過 Ingress 暴露的服務都無法訪問

**根本原因**:

1. **MetalLB IP 池配置不完整**: IP 池缺少 `192.168.0.10`
   ```yaml
   # 錯誤配置
   spec:
     addresses:
       - 192.168.0.200-192.168.0.220  # 缺少 .10
   ```

2. **使用 deprecated `spec.loadBalancerIP` 欄位**: 與 MetalLB 註解 `metallb.universe.tf/loadBalancerIPs` 衝突
   ```
   MetalLB 錯誤: service can not have both metallb.universe.tf/loadBalancerIPs and svc.Spec.LoadBalancerIP
   ```

3. **`externalTrafficPolicy: Local` 導致健康檢查失敗**: MetalLB speaker 宣告 IP 後立即撤回
   ```
   MetalLB 日誌:
   "service has IP, announcing" ips=["192.168.0.10"]
   "withdrawing service announcement" reason="noIPAllocated"
   ```

**診斷步驟**:

```bash
# 1. 檢查服務狀態
kubectl get svc ingress-nginx-controller -n ingress-nginx
# 症狀: EXTERNAL-IP = <pending>

# 2. 檢查 MetalLB IP 池
kubectl get ipaddresspool -n metallb-system default-pool -o yaml
# 檢查是否包含 192.168.0.10

# 3. 檢查 MetalLB speaker 日誌
kubectl logs -n metallb-system -l component=speaker --tail=50
# 尋找 "withdrawing service announcement" 或其他錯誤

# 4. 檢查服務配置衝突
kubectl get svc ingress-nginx-controller -n ingress-nginx -o yaml | grep -E "loadBalancerIP|loadBalancerIPs"
# 檢查是否同時使用了 spec.loadBalancerIP 和註解
```

**解決方案**:

1. **添加 `192.168.0.10/32` 到 MetalLB IPAddressPool**:

   編輯 `argocd/apps/infrastructure/metallb/overlays/ipaddresspool.yaml`:
   ```yaml
   apiVersion: metallb.io/v1beta1
   kind: IPAddressPool
   metadata:
     name: default-pool
     namespace: metallb-system
   spec:
     addresses:
       - 192.168.0.10/32  # ✅ 添加 Ingress Controller VIP
       - 192.168.0.200-192.168.0.220  # 動態 IP 池
   ```

2. **移除 deprecated `spec.loadBalancerIP` 欄位**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/ingress-nginx-service.yaml`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: ingress-nginx-controller
     namespace: ingress-nginx
   spec:
     type: LoadBalancer
     # ❌ 移除這一行:
     # loadBalancerIP: 192.168.0.10
   ```

3. **使用 `externalTrafficPolicy: Cluster` 模式**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/ingress-nginx-service.yaml`:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: ingress-nginx-controller
     namespace: ingress-nginx
   spec:
     type: LoadBalancer
     externalTrafficPolicy: Cluster  # ✅ 改為 Cluster 模式
     ports:
       - name: http
         port: 80
         protocol: TCP
         targetPort: http
       - name: https
         port: 443
         protocol: TCP
         targetPort: https
     selector:
       app.kubernetes.io/name: ingress-nginx
       app.kubernetes.io/instance: ingress-nginx
       app.kubernetes.io/component: controller
   ```

4. **確保 Helm values.yaml 配置一致**:

   編輯 `argocd/apps/infrastructure/ingress-nginx/overlays/values.yaml`:
   ```yaml
   ingress-nginx:
     controller:
       service:
         enabled: true
         type: LoadBalancer
         externalTrafficPolicy: Cluster  # 與 patch 一致
   ```

5. **通過 Strategic Merge Patch 正確配置服務**:

   確保 `argocd/apps/infrastructure/ingress-nginx/overlays/kustomization.yaml` 包含:
   ```yaml
   patchesStrategicMerge:
     - ingress-nginx-service.yaml  # 明確的服務配置
   ```

**驗證修復**:

```bash
# 1. 同步 MetalLB 配置
kubectl apply -k argocd/apps/infrastructure/metallb/overlays/

# 2. 同步 Ingress-Nginx 配置
kubectl apply -k argocd/apps/infrastructure/ingress-nginx/overlays/

# 3. 等待服務重新創建
kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx

# 4. 檢查 EXTERNAL-IP
kubectl get svc ingress-nginx-controller -n ingress-nginx
# 預期: EXTERNAL-IP = 192.168.0.10

# 5. 檢查 Ingress 資源
kubectl get ingress -n argocd argocd-server
# 預期: ADDRESS = 192.168.0.10

# 6. 測試 HTTPS 連接
curl -k -I https://argocd.detectviz.internal
# 預期: HTTP/2 307 (ArgoCD 重定向)

# 7. 檢查 MetalLB speaker 日誌
kubectl logs -n metallb-system -l component=speaker --tail=20
# 預期: "service has IP, announcing" 且沒有 "withdrawing" 訊息
```

**externalTrafficPolicy 模式對比**:

| 特性 | Local | Cluster |
|-----|-------|---------|
| 保留源 IP | ✅ 是 | ❌ 否 (SNAT) |
| 負載均衡 | 僅本地 Pod | 全集群 Pod |
| 健康檢查 | 需要 healthCheckNodePort | 不需要 |
| MetalLB 相容性 | ⚠️ 需要健康檢查通過 | ✅ 無額外要求 |
| 適用場景 | 生產環境 (需要源 IP) | 測試/開發環境 |

**為何選擇 Cluster 模式**:
- ✅ 避免 MetalLB L2 模式下的健康檢查問題
- ✅ 更簡單的配置,無需額外的健康檢查設置
- ⚠️ 缺點: 無法保留客戶端源 IP (對於 Ingress 通常不重要)

**相關文件**:
- `ingress-nginx-loadbalancer-fix.md` - 完整修復過程和技術洞察
- Commits:
  - `bbab4f2` - "fix: Add 192.168.0.10 to MetalLB IP pool"
  - `16bb52d` - "fix: Remove deprecated loadBalancerIP field"
  - `8bafac7` - "fix: Configure externalTrafficPolicy=Cluster"
  - `959332d` - "fix: Re-add ingress-nginx-service.yaml with correct config"

**預期結果**:
- ✅ EXTERNAL-IP: 192.168.0.10 成功分配
- ✅ HTTPS 正常訪問: https://argocd.detectviz.internal
- ✅ MetalLB 穩定運行,無 IP 撤回問題
- ✅ 所有 Ingress 資源正常工作

---

#### 10. MTU 問題

**問題**: 設定 MTU 9000 後無法連線或封包丟失

**原因**: 網卡、交換機或線材不支援巨型幀（Jumbo Frames）

**診斷步驟**:

```bash
# 1. 測試標準 MTU (1472 bytes payload + 28 bytes header = 1500 bytes)
ping -c 3 -M do -s 1472 192.168.0.11
# 預期: 成功

# 2. 測試巨型幀 MTU (8972 bytes payload + 28 bytes header = 9000 bytes)
ping -c 3 -M do -s 8972 192.168.0.11
# 如果失敗，表示路徑中有設備不支援 MTU 9000

# 3. 檢查 Proxmox 網卡最大支援
ip link show enp4s0
# 查看 "mtu" 欄位的最大值

# 4. 檢查所有 VM 的 MTU
ansible all -i ansible/inventory.ini -m shell -a "ip link show | grep mtu"
```

**解決方案**:

```bash
# 方案 A: 改回 MTU 1500（建議）
# 1. 修改 terraform/terraform.tfvars
#    proxmox_mtu = 1500
# 2. 修改 Proxmox /etc/network/interfaces
#    mtu 1500
# 3. 重啟網路
systemctl restart networking

# 方案 B: 逐步提升 MTU 找出最大支援值
# 測試不同的 MTU 值
ping -c 3 -M do -s 1972 192.168.0.11  # 2000 MTU
ping -c 3 -M do -s 3972 192.168.0.11  # 4000 MTU
ping -c 3 -M do -s 7972 192.168.0.11  # 8000 MTU
# 找出可用的最大值後設定

# 重新配置 VM 網路
ansible-playbook -i ansible/inventory.ini ansible/deploy-cluster.yml --tags network
```

**注意事項**:
- MTU 9000 需要**整條路徑**（Proxmox 網卡→交換機→VM 網卡）都支援
- 一般家用網卡和交換機只支援 MTU 1500
- 企業級 NIC 和交換機通常支援 MTU 9000
- 對於小型 Kubernetes 集群，MTU 1500 已足夠，不會有明顯效能差異

---

### 清理與重新部署

#### 清理失敗的 VM 部署

如果 Terraform 部署中途失敗：

```bash
cd terraform/
./cleanup-failed-vms.sh
```

此腳本將：
- 檢查並清理 Terraform 狀態
- 提供手動清理 Proxmox VM 的詳細指令

#### 完全重新部署

如果需要從頭開始整個集群部署：

```bash
cd terraform/
./cleanup-and-redeploy.sh
```

此腳本將：
- 自動銷毀所有現有資源
- 重新初始化並部署新基礎設施
- 適用於開發測試或重大配置變更

#### 手動清理步驟

如果自動化腳本無法使用：

1. **銷毀 Terraform 資源**:
   ```bash
   cd terraform/
   terraform destroy -auto-approve
   ```

2. **手動刪除 Proxmox VM**:
   ```bash
   # 在 Proxmox 上執行
   qm stop 111 && qm destroy 111
   qm stop 112 && qm destroy 112
   qm stop 113 && qm destroy 113
   qm stop 114 && qm destroy 114
   ```

3. **清理 Terraform 狀態**:
   ```bash
   rm -rf .terraform/
   rm terraform.tfstate*
   ```

4. **清理 Ansible 生成的文件**:
   ```bash
   rm -rf ansible/kubeconfig/
   rm ansible/inventory.ini
   ```

5. **重置 Proxmox 網路**（如需要）:
   ```bash
   # 在 Proxmox 上執行
   systemctl restart networking
   ```

---

### 診斷工具

#### 網路診斷

```bash
# 執行完整網路驗證
./scripts/validate-dual-network.sh

# 分段驗證
./scripts/validate-dual-network.sh --proxmox
./scripts/validate-dual-network.sh --vms
./scripts/validate-dual-network.sh --dns
./scripts/validate-dual-network.sh --connectivity
```

#### 集群診斷

```bash
# 檢查集群健康狀態
./scripts/health-check.sh

# 檢查 DNS
./scripts/test-cluster-dns.sh

# 診斷特定節點網路問題
./scripts/diagnose-vm1-network.sh
```

---

### 參考文檔

- **網路規劃**: `docs/infrastructure/00-planning/configuration-network.md`
- **域名配置**: `docs/infrastructure/00-planning/configuration-domain.md`
- **儲存規劃**: `docs/infrastructure/00-planning/configuration-storage.md`
- **Proxmox 配置**: `docs/infrastructure/02-proxmox/`
- **Terraform 文檔**: `terraform/README.md`
- **Ansible 文檔**: `ansible/README.md`

---

> [!IMPORTANT]
> **生產環境注意事項**:
> - 定期備份 Vault 金鑰 (`vault-keys.json`)
> - 定期備份 kubeconfig (`ansible/kubeconfig/admin.conf`)
> - 定期備份 Terraform 狀態 (`terraform/terraform.tfstate`)
> - 監控磁碟空間和網路流量
> - 定期更新 Kubernetes 版本和應用組件

> [!TIP]
> **效能優化建議**:
> - **MTU 設定**: 預設使用 1500，僅在確認硬體支援時才啟用 MTU 9000（巨型幀）
> - **rp_filter**: 使用 `rp_filter = 2` (寬鬆模式) 以支援非對稱路由
> - **sysctl 參數**: 定期檢查參數是否正確應用
> - **雙網路架構**: 使用內部集群網路 (vmbr1) 進行 Kubernetes 節點間通訊以提升效能
> - **MTU 測試**: 使用 `ping -M do -s <size>` 測試路徑最大 MTU