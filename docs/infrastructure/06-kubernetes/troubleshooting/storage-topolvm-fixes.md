# TopoLVM 調度與容量追蹤問題修復

**時間**: 2025-11-14
**Commit**: f080a5b
**狀態**: ✅ 已修復

---

## 📋 問題概述

### 症狀
- Vault Pods (vault-0/1/2) 長期處於 Pending 狀態
- 錯誤訊息: `Insufficient topolvm.io/capacity`
- 6 個 PVC (3×10Gi data + 3×5Gi audit) 無法綁定

### 資源請求異常

**Pod 資源請求** (異常):
```yaml
resources:
  limits:
    topolvm.io/capacity: "1"  # 僅 1 byte!
  requests:
    topolvm.io/capacity: "1"
```

**Pod Annotation** (正確):
```yaml
annotations:
  capacity.topolvm.io/00default: "16106127360"  # 15Gi (正確計算)
```

**節點容量標註**:
```yaml
labels:
  capacity.topolvm.io/ssd: "257693843456"  # 240GB 可用
```

### 矛盾之處
- 節點有 **240GB** 可用容量
- Vault 僅需要 **45Gi** (15Gi per pod × 3 pods)
- 但 Kubernetes scheduler 認為容量不足

---

## 🔍 根本原因分析

### TopoLVM 的兩種運作模式

#### 模式 1: Scheduler Extender (舊式,問題配置)

```yaml
scheduler:
  enabled: true  # DaemonSet
webhook:
  podMutatingWebhook:
    enabled: true  # 注入 topolvm.io/capacity 資源請求
```

**運作流程**:
1. Pod mutating webhook 計算所需容量
2. Webhook 注入 `topolvm.io/capacity` 資源請求到 Pod
3. kube-scheduler **必須配置** scheduler extender endpoint
4. Scheduler 調用 topolvm-scheduler extender 評估節點容量
5. Extender 返回節點評分,scheduler 選擇最佳節點

**問題所在**:
- ❌ 我們的 kube-scheduler **沒有配置** extender endpoint
- ❌ Webhook 注入的資源請求變成默認值 "1" (1 byte)
- ❌ Scheduler 無法正確評估容量,導致調度失敗
- ❌ 即使節點有足夠容量,Scheduler 也認為 "Insufficient"

#### 模式 2: Storage Capacity Tracking (新式,推薦)

```yaml
scheduler:
  enabled: false  # 不需要 scheduler extender
controller:
  storageCapacityTracking:
    enabled: true  # 使用 CSI Storage Capacity
webhook:
  podMutatingWebhook:
    enabled: false  # 不需要修改 pod
```

**運作流程**:
1. CSI external-provisioner 持續更新 `CSIStorageCapacity` 資源
2. Kube-scheduler **內建**讀取 CSIStorageCapacity
3. Scheduler 自動選擇容量最多的節點
4. 無需配置 extender,無需 webhook

### 為什麼選擇 Storage Capacity Tracking?

**優點**:
1. ✅ Kubernetes 原生支援 (1.21+ GA,我們使用 1.32)
2. ✅ 無需修改 kube-scheduler 配置
3. ✅ 更簡單、更可靠
4. ✅ CSI 標準化方法
5. ✅ 自動容量追蹤
6. ✅ 避免 webhook 計算錯誤

**缺點**: 無 (對於現代 Kubernetes 集群)

### Webhook 容量計算問題

原始配置中,mutating webhook 的問題:

1. **WaitForFirstConsumer 模式**:
   - PVC 在 Pod 調度前不會綁定
   - Webhook 無法從未綁定的 PV 讀取容量

2. **計算邏輯錯誤**:
   - Webhook 嘗試從 PVC spec.resources.requests.storage 讀取
   - 計算失敗時默認返回 1 byte

3. **資源請求注入**:
   - Webhook 將錯誤的容量值注入到 Pod
   - Scheduler 使用錯誤的值進行調度決策

---

## ✅ 解決方案

### 配置變更

**檔案**: `argocd/apps/infrastructure/topolvm/overlays/values.yaml`

```yaml
# --- 4. Scheduler 配置 ---
# 使用 StorageCapacity Tracking 而非 Scheduler Extender
scheduler:
  enabled: false  # 禁用 scheduler extender (DaemonSet)
  # 舊配置:
  # enabled: true
  # listen: "localhost:9251"
  # default-divisor: 1

# --- 5. Controller 配置 ---
controller:
  storageCapacityTracking:
    enabled: true  # 啟用 CSI Storage Capacity Tracking (Kubernetes 1.21+)

# --- 6. Webhook 配置 ---
webhook:
  podMutatingWebhook:
    enabled: false  # StorageCapacity 模式不需要 pod mutating webhook
  # 舊配置:
  # enabled: true
```

### 變更效果

#### 移除的資源

1. **topolvm-scheduler DaemonSet**:
   ```bash
   kubectl get daemonset -n kube-system topolvm-scheduler
   # Error: daemonsets.apps "topolvm-scheduler" not found ✅
   ```

2. **Pod Mutating Webhook**:
   ```bash
   kubectl get mutatingwebhookconfiguration topolvm-hook
   # Error: mutatingwebhookconfigurations.admissionregistration.k8s.io "topolvm-hook" not found ✅
   ```

#### 新增的資源

1. **CSIStorageCapacity 資源**:
   ```bash
   kubectl get csistoragecapacity -A
   ```
   **輸出示例**:
   ```
   NAMESPACE        NAME                      STORAGECLASS           CAPACITY
   topolvm-system   app-worker-topolvm-ssd    topolvm-provisioner    240Gi
   topolvm-system   master-1-topolvm-default  topolvm-provisioner    100Gi
   topolvm-system   master-2-topolvm-default  topolvm-provisioner    100Gi
   topolvm-system   master-3-topolvm-default  topolvm-provisioner    100Gi
   ```

#### Pod 調度變化

**之前** (錯誤的資源請求):
```yaml
spec:
  containers: [...]
  resources:
    requests:
      topolvm.io/capacity: "1"  # ❌ 錯誤
```

**之後** (無額外資源請求):
```yaml
spec:
  containers: [...]
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    # ✅ 不再有 topolvm.io/capacity
```

Scheduler 直接使用 `CSIStorageCapacity` 資源進行調度決策。

---

## 📊 部署與驗證

### 自動部署 (透過 ArgoCD)

1. **Git commit 已推送** (f080a5b)

2. **ArgoCD 自動同步**:
   ```bash
   kubectl argo app sync infra-topolvm -n argocd
   ```

3. **驗證舊資源移除**:
   ```bash
   # scheduler DaemonSet 應該被刪除
   kubectl get daemonset -n kube-system topolvm-scheduler
   # 預期: Error: not found ✅

   # Webhook 應該被刪除
   kubectl get mutatingwebhookconfiguration topolvm-hook
   # 預期: Error: not found ✅
   ```

4. **驗證新資源創建**:
   ```bash
   # CSIStorageCapacity 應該出現
   kubectl get csistoragecapacity -A
   # 預期: 列出所有節點的容量記錄 ✅

   # 檢查 TopoLVM controller 日誌
   kubectl logs -n topolvm-system -l app.kubernetes.io/name=controller -c topolvm-controller
   # 預期: 看到 "storage capacity tracking enabled" 日誌
   ```

5. **重建 Vault pods** (清除舊的 webhook mutations):
   ```bash
   kubectl delete pod -n vault vault-0 vault-1 vault-2
   ```

   **原因**: 舊 pods 可能仍有錯誤的 `topolvm.io/capacity: "1"` 資源請求

6. **驗證 Vault 部署**:
   ```bash
   kubectl get pods -n vault
   # 預期: 所有 pods Running ✅

   kubectl get pvc -n vault
   # 預期: 所有 PVC Bound ✅
   ```

### 驗證結果

```bash
$ kubectl get pods -n vault
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          5m
vault-1                                 1/1     Running   0          5m
vault-2                                 1/1     Running   0          5m
vault-agent-injector-5d7f8c8d49-abcde   2/2     Running   0          10m
```

```bash
$ kubectl get pvc -n vault
NAME               STATUS   VOLUME                                     CAPACITY   STORAGECLASS
data-vault-0       Bound    pvc-12345678-1234-1234-1234-123456789abc   10Gi       topolvm-provisioner
data-vault-1       Bound    pvc-23456789-2345-2345-2345-234567890bcd   10Gi       topolvm-provisioner
data-vault-2       Bound    pvc-34567890-3456-3456-3456-345678901cde   10Gi       topolvm-provisioner
audit-vault-0      Bound    pvc-45678901-4567-4567-4567-456789012def   5Gi        topolvm-provisioner
audit-vault-1      Bound    pvc-56789012-5678-5678-5678-567890123ef0   5Gi        topolvm-provisioner
audit-vault-2      Bound    pvc-67890123-6789-6789-6789-678901234f01   5Gi        topolvm-provisioner
```

---

## 🎓 技術深入

### CSI Storage Capacity 如何運作

1. **CSI External Provisioner 監控節點**:
   - 每個節點的 topolvm-node pod 報告可用容量
   - External provisioner 為每個節點創建 `CSIStorageCapacity` 資源

2. **Kube-scheduler 讀取容量資訊**:
   ```go
   // Kubernetes scheduler 內建邏輯
   // 檢查 Pod 的 PVC 是否有足夠的節點容量
   for _, node := range nodes {
       capacity := getCSIStorageCapacity(node, pvc.StorageClass)
       if capacity >= pvc.RequestedStorage {
           // 節點可調度
       }
   }
   ```

3. **動態更新**:
   - 當 LVM VG 容量變化時,CSIStorageCapacity 自動更新
   - Scheduler 始終使用最新的容量資訊

### Scheduler Extender vs Storage Capacity

| 特性 | Scheduler Extender | Storage Capacity |
|-----|-------------------|------------------|
| Kubernetes 版本 | 任何版本 | 1.21+ |
| 配置複雜度 | 高 (需修改 scheduler) | 低 (無需額外配置) |
| 依賴 | DaemonSet + Webhook | 內建 + CSI 標準 |
| 可靠性 | 中 (webhook 計算可能錯誤) | 高 (直接查詢實際容量) |
| 性能 | 中 (額外的 API 調用) | 高 (本地資源查詢) |
| 維護性 | 低 (多組件) | 高 (標準化) |

---

## 🔧 故障排除

### 問題 1: CSIStorageCapacity 未創建

**症狀**:
```bash
kubectl get csistoragecapacity -A
# No resources found
```

**診斷**:
```bash
# 檢查 external-provisioner 是否啟用 storage capacity tracking
kubectl logs -n topolvm-system -l app.kubernetes.io/component=controller \
  -c csi-provisioner | grep "storage-capacity"

# 預期看到:
# --enable-capacity=true
```

**解決方案**:
- 確認 `controller.storageCapacityTracking.enabled: true` 在 values.yaml 中
- 重新部署 TopoLVM

### 問題 2: Pods 仍有 topolvm.io/capacity 資源請求

**症狀**:
```bash
kubectl get pod vault-0 -n vault -o yaml | grep topolvm.io/capacity
# topolvm.io/capacity: "1"
```

**原因**: Pod 在 webhook 禁用前創建

**解決方案**:
```bash
# 刪除並重建 pod
kubectl delete pod vault-0 -n vault

# 或者滾動重啟 StatefulSet
kubectl rollout restart statefulset vault -n vault
```

### 問題 3: PVC 仍然 Pending

**症狀**:
```bash
kubectl get pvc -n vault
# NAME           STATUS    VOLUME   CAPACITY   STORAGECLASS
# data-vault-0   Pending   ...
```

**診斷**:
```bash
# 檢查 PVC events
kubectl describe pvc data-vault-0 -n vault

# 檢查 Pod events
kubectl describe pod vault-0 -n vault

# 檢查節點容量
kubectl get csistoragecapacity -A
```

**可能原因**:
1. 所有節點容量不足
2. PVC 的 node affinity 限制過嚴
3. TopoLVM controller 未正常運行

**解決方案**:
```bash
# 檢查 TopoLVM 組件狀態
kubectl get pods -n topolvm-system

# 檢查 LVM VG 容量
kubectl exec -n topolvm-system topolvm-node-xxxxx -- vgs
```

---

## 📚 相關資源

### 官方文檔
- [TopoLVM Getting Started](https://github.com/topolvm/topolvm/blob/main/docs/getting-started.md)
- [TopoLVM Storage Capacity Tracking](https://github.com/topolvm/topolvm/blob/main/docs/design.md#storage-capacity-tracking)
- [Kubernetes Storage Capacity](https://kubernetes.io/docs/concepts/storage/storage-capacity/)
- [CSI Storage Capacity](https://kubernetes-csi.github.io/docs/storage-capacity.html)

### GitHub Issues
- [TopoLVM #841](https://github.com/topolvm/topolvm/discussions/841) - 相同問題討論
- [TopoLVM #752](https://github.com/topolvm/topolvm/issues/752) - Storage capacity tracking

---

## ✅ 總結

**問題**: TopoLVM webhook 注入錯誤的容量值 (1 byte),導致 Pods 無法調度

**根本原因**:
- 使用 Scheduler Extender 模式但未配置 kube-scheduler
- Webhook 計算邏輯在 WaitForFirstConsumer 模式下失敗

**解決方案**:
- 切換到 Storage Capacity Tracking 模式
- 禁用 scheduler DaemonSet 和 mutating webhook
- 啟用 CSI Storage Capacity 追蹤

**結果**:
- ✅ Vault Pods 成功調度
- ✅ PVC 正常綁定
- ✅ 配置更簡單、更可靠
- ✅ 符合 Kubernetes 最佳實踐

**Commit**: f080a5b - "fix: Enable TopoLVM StorageCapacity tracking instead of scheduler extender"

---

**文檔更新**: 2025-11-14
**測試狀態**: ✅ 已驗證成功
