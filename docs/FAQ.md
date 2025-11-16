# DetectViz GitOps 常見問題 (FAQ)

基於實際部署日誌（deploy.log）整理的常見問題與解決方案。

## 目錄

- [雞生蛋問題](#雞生蛋問題)
- [ArgoCD 相關問題](#argocd-相關問題)
- [TopoLVM 存儲問題](#topolvm-存儲問題)
- [網路與 DNS 問題](#網路與-dns-問題)
- [Ansible 部署問題](#ansible-部署問題)
- [Vault 相關問題](#vault-相關問題)

---


## 雞生蛋問題

本部署流程已完整解決以下循環依賴問題（詳見[故障排除](#故障排除)章節）：

### 問題 #1: ApplicationSet 路徑配置
- **症狀**: ArgoCD 無法找到應用路徑
- **解決方案**: ✅ 所有 ApplicationSet 路徑已包含 `argocd/` 前綴
- **驗證**: `argocd/appsets/appset.yaml` 已修正

### 問題 #2: AppProject 權限白名單
- **症狀**: 基礎設施應用無法創建 Namespace 或 IngressClass
- **解決方案**: ✅ `platform-bootstrap` 項目已包含所有必要資源權限
- **驗證**: `argocd/bootstrap/argocd-projects.yaml` 已配置完整

### 問題 #3: CRD 依賴順序
- **症狀**: cluster-bootstrap 嘗試創建 Certificate 但 cert-manager CRD 尚未安裝
- **解決方案**: ✅ 使用 Sync Wave 分階段部署 + `SkipDryRunOnMissingResource=true`
- **預期行為**: cluster-bootstrap Phase 2 會先失敗，待基礎設施同步後自動重試成功
- **驗證**: 基礎設施同步後 cluster-bootstrap 自動變為 Synced

### 問題 #4: TopoLVM 調度模式
- **症狀**: Vault pods 顯示 "Insufficient capacity" 但實際有足夠空間
- **根本原因**: Scheduler Extender 模式未完整配置
- **解決方案**: ✅ 改用 Storage Capacity Tracking 模式（Kubernetes 1.21+ 原生）
- **驗證**: `argocd/apps/infrastructure/topolvm/overlays/values.yaml` 已啟用 `storageCapacityTracking`

### 問題 #5: Vault Pod Anti-Affinity 與單 Worker Node
- **症狀**: vault-1/vault-2 pods 持續 Pending，錯誤 "didn't match pod anti-affinity rules"
- **根本原因**: Vault Helm chart 默認使用 `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity，要求每個 pod 在不同 node 上，但測試環境只有 1 個 worker node
- **解決方案**: ✅ 改用 `preferredDuringSchedulingIgnoredDuringExecution` (weight: 100)
  - 允許多個 Vault pods 在同一 node 上運行（測試環境）
  - 當有多個 worker nodes 時仍會嘗試分散（生產環境）
- **驗證**: `argocd/apps/infrastructure/vault/overlays/values.yaml` 已添加 `server.affinity` 配置
- **生產建議**: 多 worker node 環境可考慮改回 `required` 以提高可用性

### 問題 #6: ArgoCD Server URL 配置未生效
- **症狀**: ArgoCD UI 無法正確顯示 `https://argocd.detectviz.internal` URL,影響 SSO 回調和狀態徽章
- **根本原因**: ArgoCD 由 Ansible 通過 Helm chart 安裝,`argocd-cm.yaml` 配置從未被應用到實際運行的 ConfigMap
- **解決方案**: ✅ 啟用 ArgoCD 自我管理配置
  - 添加 ArgoCD 到 ApplicationSet (`argocd/appsets/appset.yaml`)
  - 創建 config-only 管理模式（不重新部署 ArgoCD 本身）
  - 只管理配置文件 (`argocd-cm.yaml`)，避免與 Ansible 安裝衝突
- **臨時修復**: 已手動 patch ConfigMap: `kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"url":"https://argocd.detectviz.internal"}}'`
- **驗證**: `argocd/apps/infrastructure/argocd/overlays/kustomization.yaml` 已改為 config-only 模式
- **影響**: 未來配置變更可通過 GitOps 管理,無需手動操作

### 問題 #7: Ingress-Nginx LoadBalancer 無法分配 IP
- **症狀**: ingress-nginx-controller 服務 EXTERNAL-IP 為 `<pending>`，無法訪問 https://argocd.detectviz.internal
- **根本原因**:
  1. MetalLB IP 池配置不完整（缺少 192.168.0.10）
  2. 使用 deprecated `spec.loadBalancerIP` 欄位與註解衝突
  3. `externalTrafficPolicy: Local` 導致健康檢查失敗，IP 被撤回
- **解決方案**: ✅ 完整修復配置
  - 添加 `192.168.0.10/32` 到 MetalLB IPAddressPool
  - 移除 deprecated `spec.loadBalancerIP` 欄位
  - 使用 `externalTrafficPolicy: Cluster` 模式
  - 通過 strategic merge patch 正確配置服務
- **驗證**: EXTERNAL-IP 成功分配為 192.168.0.10，HTTPS 正常訪問
- **相關文件**: `ingress-nginx-loadbalancer-fix.md`
- **Commits**: bbab4f2, 16bb52d, 8bafac7, 959332d

**部署建議**:
- ⚠️ **cluster-bootstrap 顯示 OutOfSync 是正常的**，在基礎設施同步前會持續此狀態
- ✅ **所有配置文件已修正**，無需手動調整
- 📋 **遵循本文件步驟**，問題會自動解決


## ArgoCD 相關問題

### Q1: ArgoCD 顯示 "app path does not exist" 錯誤

**完整錯誤訊息**:
```
ComparisonError: Failed to load target state: failed to generate manifest for source 1 of 1
rpc error: code = Unknown desc = apps/infrastructure/cert-manager/overlays: app path does not exist
```

**原因**: ApplicationSet 生成的應用路徑缺少 `argocd/` 前綴

**診斷步驟**:
```bash
# 1. 檢查 Application 的實際路徑
kubectl get application infra-cert-manager -n argocd -o jsonpath='{.spec.source.path}'

# 錯誤輸出: apps/infrastructure/cert-manager/overlays
# 正確輸出: argocd/apps/infrastructure/cert-manager/overlays

# 2. 檢查 ApplicationSet 配置
kubectl get applicationset detectviz-gitops -n argocd -o yaml | grep -A 5 "elements:"
```

**解決方案**:

1. 修正 `argocd/appsets/appset.yaml`:
```yaml
generators:
  - list:
      elements:
        - appName: cert-manager
          path: argocd/apps/infrastructure/cert-manager/overlays  # ✅ 添加 argocd/ 前綴
        - appName: metallb
          path: argocd/apps/infrastructure/metallb/overlays
        # ... 其他應用
```

2. 提交修改並刷新 root application:
```bash
git add argocd/appsets/appset.yaml
git commit -m "fix: Add argocd/ prefix to application paths"
git push

# 刷新 root application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge
```

**預防措施**: 所有 ApplicationSet 路徑都應使用完整路徑，包含 `argocd/` 前綴。

---

### Q2: ArgoCD 顯示 "resource is not permitted in project" 錯誤

**完整錯誤訊息**:
```
resource :Namespace is not permitted in project platform-bootstrap
resource :IngressClass is not permitted in project platform-bootstrap
```

**原因**: AppProject 的 `clusterResourceWhitelist` 未包含必要的資源類型

**診斷步驟**:
```bash
# 1. 檢查 Application 錯誤詳情
kubectl get application infra-cert-manager -n argocd -o yaml | grep -A 20 "conditions:"

# 2. 檢查 AppProject 白名單
kubectl get appproject platform-bootstrap -n argocd -o yaml | grep -A 30 "clusterResourceWhitelist"
```

**解決方案**:

修正 `argocd/bootstrap/argocd-projects.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-bootstrap
spec:
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace          # ✅ 添加 Namespace
    - group: networking.k8s.io
      kind: IngressClass       # ✅ 添加 IngressClass
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
    - group: storage.k8s.io
      kind: StorageClass
    - group: rbac.authorization.k8s.io
      kind: ClusterRole
    - group: rbac.authorization.k8s.io
      kind: ClusterRoleBinding
    # ... 其他必要資源
```

**提交修改**:
```bash
git add argocd/bootstrap/argocd-projects.yaml
git commit -m "fix: Add missing resources to AppProject whitelist"
git push
```

**常見缺少的資源類型**:
- `Namespace` (core/v1)
- `IngressClass` (networking.k8s.io/v1)
- `StorageClass` (storage.k8s.io/v1)
- `PriorityClass` (scheduling.k8s.io/v1)

---

### Q3: cluster-bootstrap 持續顯示 OutOfSync 和 "CRDs are not installed" 錯誤

**完整錯誤訊息**:
```
cluster-bootstrap: OutOfSync, Progressing
no matches for kind "Certificate" in version "cert-manager.io/v1"
ensure CRDs are installed first
```

**重要**: **這是正常且預期的行為！**

**原因**: cluster-bootstrap Phase 2 資源（Certificates, Ingress, IngressClass）依賴 cert-manager 和 ingress-nginx 的 CRDs，但這些基礎設施尚未部署。

**設計原理**: 使用 Sync Wave 分階段部署
- **Phase 1** (Sync Wave: -10): Namespaces → 立即成功 ✅
- **Phase 2** (Sync Wave: 10): Certificates, Ingress → 等待 CRDs ⏳

**解決步驟**:

1. **確認這是預期行為** - 在基礎設施同步前看到此錯誤是正常的：
```bash
kubectl get application cluster-bootstrap -n argocd
# 預期輸出: OutOfSync, Progressing ⏳
```

2. **手動同步基礎設施 Applications**（按順序）:
```bash
# 在 ArgoCD UI 中點擊 SYNC，或使用 CLI:
kubectl patch application infra-cert-manager -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge

kubectl patch application infra-ingress-nginx -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge
```

3. **等待 CRDs 安裝**:
```bash
# 檢查 cert-manager CRDs
kubectl get crd | grep cert-manager
# 預期: certificates.cert-manager.io, clusterissuers.cert-manager.io

# 檢查 ingress-nginx CRDs
kubectl get ingressclass
# 預期: nginx
```

4. **驗證 cluster-bootstrap 自動重試成功**:
```bash
# 等待 1-2 分鐘後檢查
kubectl get application cluster-bootstrap -n argocd
# 預期輸出: Synced, Healthy ✅
```

**關鍵配置**（已內建）:
```yaml
# argocd/bootstrap/manifests/*.yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
    argocd.argoproj.io/sync-wave: "10"
```

**時間線**:
```
T+0min:  cluster-bootstrap 部署 → Phase 1 成功, Phase 2 失敗（CRDs 不存在）
T+5min:  手動同步基礎設施 → cert-manager, ingress-nginx 安裝
T+7min:  cluster-bootstrap 自動重試 → Phase 2 成功 ✅
```

---

### Q4: ArgoCD Applications 顯示 Unknown 狀態且不自動同步

**症狀**:
```
NAME                              SYNC STATUS   HEALTH STATUS
infra-cert-manager                Unknown       Healthy
infra-ingress-nginx               Unknown       Unknown
```

**可能原因**:
1. ApplicationSet 剛生成 Applications，尚未觸發首次同步
2. ArgoCD repo-server 有錯誤
3. Git repository 認證失敗

**診斷步驟**:

```bash
# 1. 檢查 repo-server 日誌
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50 | grep -i error

# 2. 檢查 Application 詳細狀態
kubectl get application infra-cert-manager -n argocd -o yaml | grep -A 10 "conditions:"

# 3. 檢查 Git repository 連接
kubectl get application root -n argocd -o yaml | grep -A 5 "repoURL"
```

**解決方案**:

**方案 A: 手動觸發同步**
```bash
# 刷新 root application
kubectl patch application root -n argocd \
  -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' --type=merge

# 等待 30 秒
sleep 30

# 檢查狀態
kubectl get applications -n argocd
```

**方案 B: 如果是 Git SSH 認證問題**
```bash
# 檢查 SSH secret 是否存在
kubectl get secret detectviz-gitops-repo -n argocd

# 如果不存在，創建 secret（需要先有 SSH 私鑰）
kubectl create secret generic detectviz-gitops-repo \
  --from-file=sshPrivateKey=/path/to/ssh/key \
  -n argocd

kubectl label secret detectviz-gitops-repo \
  argocd.argoproj.io/secret-type=repository -n argocd

kubectl patch secret detectviz-gitops-repo -n argocd \
  -p='{"stringData":{"type":"git","url":"git@github.com:detectviz/detectviz-gitops.git"}}'
```

**方案 C: 重啟 repo-server（最後手段）**
```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd --timeout=60s
```

---

### Q5: Kustomize build 失敗，提示 "unknown field buildOptions" 或需要 --enable-helm

**完整錯誤訊息**:
```
`kustomize build` failed: Error: invalid Kustomization: json: unknown field "buildOptions"
或
Error: accumulating resources: accumulation err='accumulating resources from 'helmCharts':
must build at root': must specify --enable-helm
```

**原因**:
- Kustomize 不支援 `buildOptions` 欄位（這是 ArgoCD 特有配置）
- Kustomize 處理 Helm charts 需要 `--enable-helm` 標誌

**解決方案**:

**錯誤配置** ❌:
```yaml
# argocd/appsets/appset.yaml
source:
  path: "{{.path}}"
  kustomize:
    buildOptions: "--enable-helm"  # ❌ Kustomize 不認識此欄位
```

**正確配置** ✅:

**方案 A: 使用 ArgoCD 全局配置**（推薦）
```yaml
# argocd/apps/infrastructure/argocd/overlays/argocd-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  kustomize.buildOptions: "--enable-helm"  # ✅ 全局啟用
```

**方案 B: 調整 Kustomize 結構**（不使用 Helm）
```yaml
# base/kustomization.yaml
resources:
  - namespace.yaml
  - deployment.yaml

# 移除 helmCharts 區塊，改用 Helm Application
```

**驗證修復**:
```bash
# 測試本地 kustomize build
cd argocd/apps/infrastructure/cert-manager/overlays
kustomize build .

# 如果成功，提交修改
git add .
git commit -m "fix: Remove invalid kustomize buildOptions"
git push
```

---

## TopoLVM 存儲問題

### Q6: Vault Pods 無法調度，顯示 "Insufficient topolvm.io/capacity"

**完整錯誤訊息**:
```
0/4 nodes are available:
1 Insufficient topolvm.io/capacity,
3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }

實際節點容量: 240GB
PVC 需求: 45GB (10Gi + 10Gi + 10Gi + 5Gi + 5Gi + 5Gi)
```

**根本原因**: TopoLVM 使用了 Scheduler Extender 模式，但 kube-scheduler 未配置 extender endpoint，導致：
- Webhook 注入錯誤的容量值 `topolvm.io/capacity: "1"` (僅 1 byte)
- Scheduler 認為節點容量不足

**診斷步驟**:

```bash
# 1. 檢查 Pod 資源請求（應該看到錯誤的容量值）
kubectl get pod vault-0 -n vault -o yaml | grep "topolvm.io/capacity"
# 錯誤輸出: topolvm.io/capacity: "1"  ❌ (僅 1 byte!)

# 2. 檢查節點 annotation（實際容量是正確的）
kubectl get node app-worker -o jsonpath='{.metadata.annotations}' | jq 'with_entries(select(.key | contains("topolvm")))'
# 正確輸出: capacity.topolvm.io/00default: "257693843456"  ✅ (240GB)

# 3. 檢查 CSIStorageCapacity 資源
kubectl get csistoragecapacity -A
# 舊模式: No resources found  ❌
# 新模式: 應該顯示 topolvm-provisioner 容量 ✅

# 4. 檢查是否有 scheduler extender DaemonSet
kubectl get daemonset -n kube-system topolvm-scheduler
# 舊模式: 存在但無作用 ❌
# 新模式: NotFound ✅
```

**解決方案**: 改用 **Storage Capacity Tracking** 模式（Kubernetes 1.21+ 原生功能）

修正 `argocd/apps/infrastructure/topolvm/overlays/values.yaml`:
```yaml
# --- TopoLVM Helm Values ---

# 1. 禁用 Scheduler Extender
scheduler:
  enabled: false  # ✅ 不需要 scheduler extender DaemonSet

# 2. 啟用 Storage Capacity Tracking
controller:
  storageCapacityTracking:
    enabled: true  # ✅ 使用 Kubernetes 原生功能

# 3. 禁用 Pod Mutating Webhook
webhook:
  podMutatingWebhook:
    enabled: false  # ✅ Storage Capacity 模式不需要注入資源請求

# 4. 其他配置保持不變
lvmd:
  deviceClasses:
    - name: ssd
      volume-group: topolvm-vg
      default: true
```

**提交修改並重新部署**:
```bash
git add argocd/apps/infrastructure/topolvm/overlays/values.yaml
git commit -m "fix: Enable TopoLVM StorageCapacity tracking instead of scheduler extender"
git push

# 在 ArgoCD UI 中同步 infra-topolvm，或使用 CLI:
kubectl patch application infra-topolvm -n argocd \
  -p='{"operation":{"sync":{"prune":true}}}' --type=merge
```

**驗證修復**:

```bash
# 1. 等待 TopoLVM 重新部署
kubectl get pods -n topolvm-system --watch

# 2. 檢查 CSIStorageCapacity 資源（應該出現）
kubectl get csistoragecapacity -A
# 預期輸出:
# NAMESPACE      NAME                           STORAGECLASS           CAPACITY
# kube-system    topolvm-app-worker-<hash>      topolvm-provisioner    257693843456

# 3. 檢查 scheduler DaemonSet 已移除
kubectl get daemonset -n kube-system topolvm-scheduler
# 預期: Error from server (NotFound)  ✅

# 4. 刪除舊 Vault pods（清除舊 webhook mutations）
kubectl delete pod -n vault --all

# 5. 檢查新 pods 是否成功調度
kubectl get pods -n vault -o wide
# 預期: Running 狀態，調度到 app-worker ✅

# 6. 檢查 PVC 綁定狀態
kubectl get pvc -n vault
# 預期: 所有 PVC 都是 Bound 狀態 ✅
```

**為什麼這個方案更好**:
- ✅ Kubernetes 原生功能（1.21+ GA）
- ✅ 無需修改 kube-scheduler 配置
- ✅ 無需 webhook 注入資源請求
- ✅ 自動容量追蹤和更新
- ✅ 更簡單、更可靠的調度機制

**參考文檔**:
- [TopoLVM Storage Capacity Tracking](https://github.com/topolvm/topolvm/blob/main/docs/design.md#storage-capacity-tracking)
- [Kubernetes CSI Storage Capacity](https://kubernetes.io/docs/concepts/storage/storage-capacity/)

---

### Q7: TopoLVM PVC 一直處於 Pending 狀態

**症狀**:
```bash
kubectl get pvc -n vault
NAME              STATUS    VOLUME   CAPACITY   STORAGECLASS
data-vault-0      Pending                        topolvm-provisioner
```

**可能原因**:

**原因 1: VolumeBindingMode 為 WaitForFirstConsumer**
```bash
# 檢查 StorageClass
kubectl get storageclass topolvm-provisioner -o yaml | grep volumeBindingMode
# 輸出: volumeBindingMode: WaitForFirstConsumer
```

**解決方案**: 這是正常的！PVC 會等到 Pod 被調度後才創建 PV。

驗證 Pod 狀態:
```bash
kubectl get pods -n vault
# 如果 Pod 是 Running，PVC 應該變成 Bound
# 如果 Pod 是 Pending，檢查 Pod 的調度問題
```

**原因 2: Volume Group 不存在或名稱不匹配**
```bash
# 檢查 TopoLVM values
kubectl get configmap -n kube-system topolvm-lvmd -o yaml | grep volume-group

# SSH 到 worker 節點檢查 VG
ssh ubuntu@192.168.0.14 'sudo vgs'
# 預期看到: topolvm-vg
```

**解決方案**: 確保 VG 名稱一致

```bash
# 如果 VG 名稱不對，修正 values.yaml
# argocd/apps/infrastructure/topolvm/overlays/values.yaml
lvmd:
  deviceClasses:
    - name: ssd
      volume-group: topolvm-vg  # ✅ 必須與實際 VG 名稱一致
```

**原因 3: 磁碟空間不足**
```bash
# 檢查 VG 剩餘空間
ssh ubuntu@192.168.0.14 'sudo vgs'
# 查看 VFree 欄位

# 如果空間不足，需要：
# 1. 刪除不需要的 PVC
kubectl delete pvc <unused-pvc> -n <namespace>

# 2. 或者添加更多磁碟到 VG
```

---

### Q8: TopoLVM Volume Group 名稱配置不一致

**症狀**: 配置文件中出現不同的 VG 名稱（`data-vg`, `nvme-vg`, `topolvm-vg`）

**檢查配置一致性**:

```bash
# 1. 檢查 Ansible 配置
grep -r "lvm_volume_groups" ansible/group_vars/

# 2. 檢查 TopoLVM values
grep "volume-group" argocd/apps/infrastructure/topolvm/overlays/values.yaml

# 3. 檢查實際 VG 名稱
ssh ubuntu@192.168.0.14 'sudo vgs --noheadings -o vg_name | grep -v ubuntu'

# 4. 檢查文檔
grep -n "topolvm-vg\|data-vg\|nvme-vg" deploy.md
```

**標準配置**（當前統一為 `topolvm-vg`）:

| 檔案 | 配置項 | 值 |
|------|--------|-----|
| `ansible/group_vars/all.yml` | `lvm_volume_groups[0].name` | `topolvm-vg` |
| `argocd/apps/infrastructure/topolvm/overlays/values.yaml` | `lvmd.deviceClasses[0].volume-group` | `topolvm-vg` |
| `deploy.md` | 文檔說明 | `topolvm-vg` |

**修正步驟**:

1. **統一配置文件**:
```bash
# 確保所有引用都是 topolvm-vg
rg "data-vg|nvme-vg" --type yaml

# 如果有發現，逐一修正
```

2. **如果實際 VG 名稱不同，需要重建**:
```bash
# ⚠️ 警告：此操作會刪除所有數據！
ssh ubuntu@192.168.0.14 'sudo vgremove <old-vg-name>'
ssh ubuntu@192.168.0.14 'sudo vgcreate topolvm-vg /dev/sdb'
```

3. **驗證一致性**:
```bash
# 運行驗證腳本
cat > /tmp/check-topolvm-vg.sh << 'EOF'
#!/bin/bash
echo "=== Checking TopoLVM VG Configuration ==="

echo "1. Ansible config:"
grep -A 2 "lvm_volume_groups:" ansible/group_vars/all.yml | grep "name:"

echo "2. TopoLVM Helm values:"
grep "volume-group:" argocd/apps/infrastructure/topolvm/overlays/values.yaml

echo "3. Actual VG on worker:"
ssh ubuntu@192.168.0.14 'sudo vgs --noheadings -o vg_name | grep topolvm'

echo "4. Documentation:"
grep -c "topolvm-vg" deploy.md
EOF

chmod +x /tmp/check-topolvm-vg.sh
/tmp/check-topolvm-vg.sh
```

---

## 網路與 DNS 問題

### Q9: VM 之間無法通過 cluster.internal 域名解析

**症狀**:
```bash
ssh ubuntu@192.168.0.11 'getent hosts master-2.cluster.internal'
# 無輸出或錯誤
```

**診斷步驟**:

```bash
# 1. 檢查 VM 的 /etc/resolv.conf
ssh ubuntu@192.168.0.11 'cat /etc/resolv.conf'
# 應該包含: nameserver 192.168.0.2

# 2. 檢查 /etc/hosts
ssh ubuntu@192.168.0.11 'cat /etc/hosts | grep cluster.internal'

# 3. 測試 DNS 服務器
ssh ubuntu@192.168.0.11 'dig @192.168.0.2 master-2.cluster.internal +short'

# 4. 檢查 Proxmox dnsmasq 配置
ssh root@192.168.0.2 'cat /etc/dnsmasq.d/detectviz.conf | grep cluster.internal'
```

**解決方案**:

**方案 A: 修正 dnsmasq 配置**（如果缺少 cluster.internal 記錄）
```bash
# 在 Proxmox 上編輯
ssh root@192.168.0.2

cat >> /etc/dnsmasq.d/detectviz.conf << 'EOF'
# 內部集群網路域名
local=/cluster.internal/

# 內部網路記錄 (vmbr1 - 10.0.0.0/24)
address=/master-1.cluster.internal/10.0.0.11
address=/master-2.cluster.internal/10.0.0.12
address=/master-3.cluster.internal/10.0.0.13
address=/app-worker.cluster.internal/10.0.0.14
EOF

# 重啟 dnsmasq
systemctl restart dnsmasq
systemctl status dnsmasq
```

**方案 B: 使用 Ansible 重新配置網路**
```bash
# 重新運行網路配置 playbook
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml --tags network

# 驗證
ansible all -i inventory.ini -m shell -a "cat /etc/hosts | grep cluster.internal"
```

---

### Q10: MTU 設定問題導致網路不穩定

**症狀**:
- 設定 MTU 9000 後 VM 無法連線
- 大封包傳輸失敗
- SSH 連接不穩定

**診斷步驟**:

```bash
# 1. 測試標準 MTU (1472 + 28 = 1500)
ping -c 3 -M do -s 1472 192.168.0.11
# 應該成功

# 2. 測試巨型幀 MTU (8972 + 28 = 9000)
ping -c 3 -M do -s 8972 192.168.0.11
# 如果失敗，表示不支援 MTU 9000

# 3. 逐步測試找出最大 MTU
ping -c 3 -M do -s 3972 192.168.0.11  # MTU 4000
ping -c 3 -M do -s 7972 192.168.0.11  # MTU 8000

# 4. 檢查當前 MTU 設定
ssh ubuntu@192.168.0.11 'ip link show eth0 | grep mtu'
ssh ubuntu@192.168.0.11 'ip link show eth1 | grep mtu'
```

**解決方案**: 改回 MTU 1500

**步驟 1: 修正 Proxmox 網路配置**
```bash
ssh root@192.168.0.2

# 編輯網路配置
vi /etc/network/interfaces

# 修改 MTU
auto vmbr0
iface vmbr0 inet static
    ...
    mtu 1500  # ✅ 改回標準 MTU

auto vmbr1
iface vmbr1 inet static
    ...
    mtu 1500  # ✅ 改回標準 MTU

# 重啟網路
systemctl restart networking
```

**步驟 2: 修正 Terraform 配置**
```bash
# 編輯 terraform/terraform.tfvars
vi terraform/terraform.tfvars

# 修改 MTU 設定
proxmox_mtu = 1500  # ✅ 標準 MTU
```

**步驟 3: 使用 Ansible 重新配置 VM 網路**
```bash
cd ansible/
ansible-playbook -i inventory.ini deploy-cluster.yml --tags network

# 驗證 MTU
ansible all -i inventory.ini -m shell -a "ip link show | grep mtu"
# 所有介面應該顯示 mtu 1500
```

**MTU 最佳實踐**:
- ✅ **標準環境**: 使用 MTU 1500（適用於所有硬體）
- ⚠️ **企業級環境**: MTU 9000 需要整條路徑都支援（網卡、交換機、線材）
- 📊 **性能影響**: 對於 Kubernetes 小型集群，MTU 1500 vs 9000 差異可忽略

---

## Ansible 部署問題

### Q11: Ansible 任務失敗，提示權限不足

**錯誤訊息**:
```
TASK [common : Install required packages] *****
fatal: [master-1]: FAILED! => {"msg": "This task requires superuser privileges"}
```

**原因**: Ansible 任務缺少 `become: true`

**解決方案**:

檢查並修正 Ansible role:
```yaml
# ansible/roles/common/tasks/main.yml
---
- name: Install required packages
  become: true  # ✅ 添加此行
  apt:
    name:
      - apt-transport-https
      - ca-certificates
      - curl
    state: present
    update_cache: yes
```

**批量檢查**:
```bash
# 查找所有缺少 become 的 apt 任務
grep -r "^- name:" ansible/roles/*/tasks/main.yml | while read line; do
  file=$(echo $line | cut -d: -f1)
  grep -A 5 "$line" "$file" | grep -q "become: true" || echo "Missing become in: $file"
done
```

---

### Q12: Ansible 變數未定義錯誤

**錯誤訊息**:
```
fatal: [master-1]: FAILED! => {"msg": "The task includes an option with an undefined variable.
The error was: 'domain' is undefined"}
```

**診斷步驟**:

```bash
# 1. 檢查變數定義位置
grep -r "domain:" ansible/group_vars/
grep -r "domain:" ansible/host_vars/

# 2. 檢查變數引用
grep -r "{{ domain }}" ansible/roles/
```

**解決方案**:

**選項 A: 添加缺失的變數**
```yaml
# ansible/group_vars/all.yml
---
domain: detectviz.internal
cluster_domain: cluster.internal
```

**選項 B: 使用條件檢查**
```yaml
# ansible/roles/example/tasks/main.yml
- name: Configure domain
  when: domain is defined
  template:
    src: config.j2
    dest: /etc/app/config.yaml
```

**選項 C: 提供默認值**
```yaml
# Jinja2 template
domain: {{ domain | default('example.local') }}
```

---

## Vault 相關問題

### Q13: Vault Pods 啟動後立即顯示 "not ready"

**症狀**:
```bash
kubectl get pods -n vault
NAME      READY   STATUS    RESTARTS   AGE
vault-0   0/1     Running   0          2m
vault-1   0/1     Running   0          2m
vault-2   0/1     Running   0          2m
```

**原因**: Vault 需要手動初始化和解封

**這是正常的！** Vault 的安全設計要求手動初始化。

**解決步驟**:

**1. 初始化第一個 Vault 實例**:
```bash
kubectl exec -n vault vault-0 -c vault -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-keys.json

# ⚠️ 重要：安全保存 vault-keys.json！
chmod 600 vault-keys.json
```

**2. 解封所有 Vault 實例**:
```bash
# 提取 unseal keys
UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' vault-keys.json)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' vault-keys.json)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' vault-keys.json)

# 解封 vault-0（需要 3 個 keys）
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-0 -c vault -- vault operator unseal $UNSEAL_KEY_3

# 解封 vault-1
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-1 -c vault -- vault operator unseal $UNSEAL_KEY_3

# 解封 vault-2
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-2 -c vault -- vault operator unseal $UNSEAL_KEY_3
```

**3. 驗證狀態**:
```bash
# 檢查所有 pods
kubectl get pods -n vault
# 預期: 所有 pods READY 1/1

# 檢查 Vault 狀態
kubectl exec -n vault vault-0 -c vault -- vault status
# 預期: Sealed: false
```

**自動化腳本**:
```bash
# 創建解封腳本供後續使用
cat > unseal-vault.sh << 'EOF'
#!/bin/bash
KEYS_FILE=${1:-vault-keys.json}

if [ ! -f "$KEYS_FILE" ]; then
  echo "Error: $KEYS_FILE not found"
  exit 1
fi

UNSEAL_KEY_1=$(jq -r '.unseal_keys_b64[0]' $KEYS_FILE)
UNSEAL_KEY_2=$(jq -r '.unseal_keys_b64[1]' $KEYS_FILE)
UNSEAL_KEY_3=$(jq -r '.unseal_keys_b64[2]' $KEYS_FILE)

for pod in vault-0 vault-1 vault-2; do
  echo "Unsealing $pod..."
  kubectl exec -n vault $pod -c vault -- vault operator unseal $UNSEAL_KEY_1
  kubectl exec -n vault $pod -c vault -- vault operator unseal $UNSEAL_KEY_2
  kubectl exec -n vault $pod -c vault -- vault operator unseal $UNSEAL_KEY_3
done

echo "Vault unsealed successfully!"
EOF

chmod +x unseal-vault.sh
```

---

## 快速參考

### 常用診斷命令

```bash
# ArgoCD 狀態檢查
kubectl get applications -n argocd
kubectl get applicationset -n argocd
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# TopoLVM 狀態檢查
kubectl get pods -n topolvm-system
kubectl get csistoragecapacity -A
kubectl get storageclass topolvm-provisioner -o yaml

# 集群健康檢查
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running
kubectl top nodes

# 網路診斷
ip addr show
ip route
ping -c 3 -M do -s 1472 <target-ip>

# 存儲診斷
ssh ubuntu@192.168.0.14 'sudo vgs && sudo pvs && sudo lvs'
kubectl get pvc -A
kubectl get pv
```

### 相關文檔

- 主部署文檔: `deploy.md`
- 網路配置: `docs/infrastructure/00-planning/configuration-network.md`
- 域名配置: `docs/infrastructure/00-planning/configuration-domain.md`
- 存儲配置: `docs/infrastructure/00-planning/configuration-storage.md`
- ArgoCD Bootstrap: `argocd/bootstrap/PHASE_DEPLOYMENT.md`

---

**最後更新**: 2025-11-14
**基於**: deploy.log 實際部署日誌分析
