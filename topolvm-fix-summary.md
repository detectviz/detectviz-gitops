# TopoLVM Vault Pod 調度問題 - 完整分析與解決方案

**時間**: 2025-11-14
**Commit**: f080a5b

## 問題現象

### Vault Pods 無法調度
- 3 個 vault pods (vault-0/1/2) 長期處於 Pending 狀態
- 錯誤訊息: `Insufficient topolvm.io/capacity`
- 6 個 PVC (3×10Gi data + 3×5Gi audit) 也處於 Pending

### 資源請求異常
```yaml
Pod 資源請求:
  topolvm.io/capacity: "1"  # 僅 1 byte!

Pod Annotation (正確):
  capacity.topolvm.io/00default: "16106127360"  # 15Gi (正確計算)

節點容量標註:
  capacity.topolvm.io/ssd: "257693843456"  # 240GB 可用
```

### 矛盾之處
- 節點有 240GB 可用容量
- Vault 僅需要 45Gi (15Gi per pod × 3 pods)
- 但 scheduler 認為容量不足

## 根本原因分析

### 技術背景

TopoLVM 有兩種運作模式:

#### 1. Scheduler Extender 模式 (舊式,我們原本的配置)
```yaml
scheduler:
  enabled: true  # DaemonSet
webhook:
  podMutatingWebhook:
    enabled: true  # 注入 topolvm.io/capacity 資源請求
```

**運作流程**:
1. Pod mutating webhook 計算所需容量,注入 `topolvm.io/capacity` 資源請求
2. kube-scheduler **必須配置** scheduler extender endpoint
3. Scheduler 調用 topolvm-scheduler extender 評估節點容量
4. Extender 返回節點評分,scheduler 選擇最佳節點

**問題**: 
- 我們的 kube-scheduler 沒有配置 extender endpoint
- Webhook 注入的資源請求變成默認值 "1"
- Scheduler 無法正確評估容量,導致調度失敗

#### 2. Storage Capacity Tracking 模式 (新式,Kubernetes 1.21+)
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
1. ✅ Kubernetes 原生支援 (1.21+ GA)
2. ✅ 無需修改 kube-scheduler 配置
3. ✅ 更簡單、更可靠
4. ✅ CSI 標準化方法
5. ✅ 自動容量追蹤

**缺點**: 無 (對於現代 Kubernetes 集群)

## 解決方案

### 配置變更

檔案: `argocd/apps/infrastructure/topolvm/overlays/values.yaml`

```yaml
# --- 4. Scheduler 配置 ---
# 使用 StorageCapacity Tracking 而非 Scheduler Extender
scheduler:
  enabled: false  # 禁用 scheduler extender (DaemonSet)

# --- 5. Controller 配置 ---
controller:
  storageCapacityTracking:
    enabled: true  # 啟用 CSI Storage Capacity Tracking (Kubernetes 1.21+)

# --- 6. Webhook 配置 ---
webhook:
  podMutatingWebhook:
    enabled: false  # StorageCapacity 模式不需要 pod mutating webhook
```

### 預期效果

1. **移除 topolvm-scheduler DaemonSet**
   - 不再需要 scheduler extender
   
2. **移除 pod mutating webhook**
   - MutatingWebhookConfiguration `topolvm-hook` 將被刪除
   - Pods 不再被注入 `topolvm.io/capacity` 資源請求
   
3. **創建 CSIStorageCapacity 資源**
   ```bash
   kubectl get csistoragecapacity -A
   ```
   - 每個節點會有對應的容量記錄
   - Kube-scheduler 自動使用這些信息
   
4. **Vault pods 成功調度**
   - Scheduler 正確評估節點容量
   - PVC 綁定並創建 LV
   - Pods 進入 Running 狀態

## 部署步驟

### 自動部署 (透過 ArgoCD)

1. **Git push 已完成** (Commit: f080a5b)
   
2. **ArgoCD 自動同步** (或手動觸發)
   ```bash
   kubectl argo app sync infra-topolvm -n argocd
   ```

3. **驗證舊資源移除**
   ```bash
   # scheduler DaemonSet 應該被刪除
   kubectl get daemonset -n kube-system topolvm-scheduler
   
   # Webhook 應該被刪除
   kubectl get mutatingwebhookconfiguration topolvm-hook
   ```

4. **驗證新資源創建**
   ```bash
   # CSIStorageCapacity 應該出現
   kubectl get csistoragecapacity -A
   ```

5. **刪除並重建 Vault pods** (清除舊的 webhook mutations)
   ```bash
   kubectl delete pod -n vault vault-0 vault-1 vault-2
   ```

6. **驗證 Vault 部署**
   ```bash
   kubectl get pods -n vault
   kubectl get pvc -n vault
   ```

## 相關資源

### GitHub Issues & Discussions
- [TopoLVM #841](https://github.com/topolvm/topolvm/discussions/841) - 相同問題討論

### 文檔
- [TopoLVM Storage Capacity Tracking](https://github.com/topolvm/topolvm/blob/main/docs/getting-started.md)
- [Kubernetes Storage Capacity](https://kubernetes.io/docs/concepts/storage/storage-capacity/)

## 後續行動

1. ⏳ 等待 Ansible 部署完成 (ArgoCD 重新安裝)
2. ⏳ 等待 ArgoCD 同步 TopoLVM 配置
3. ⏳ 驗證 TopoLVM 部署狀態
4. ⏳ 刪除並重建 Vault pods
5. ⏳ 驗證 Vault 正常運行
6. ⏳ 生成最終部署狀態報告

## Git 提交

```
Commit: f080a5b
Author: Claude
Message: fix: Enable TopoLVM StorageCapacity tracking instead of scheduler extender
```
