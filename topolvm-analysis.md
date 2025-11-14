# TopoLVM Scheduler 容量計算問題分析

## 發現的問題

### Scheduler 配置
```yaml
listen: "localhost:9251"
default-divisor: 1
```

`default-divisor: 1` 意味著容量會被除以 1,這應該是正確的。

### Webhook 注入的容量
Vault pod 資源請求:
```yaml
resources:
  limits:
    topolvm.io/capacity: "1"
  requests:
    topolvm.io/capacity: "1"
```

**問題**: Webhook 注入了 1 byte 而非預期的 45GB

### 節點實際容量
```
capacity.topolvm.io/00default: "257693843456" (約 240GB)
capacity.topolvm.io/ssd: "257693843456"
```

### PVC 請求
- 6 個 PVC (3×10Gi data + 3×5Gi audit) = 45Gi 總計
- StorageClass: topolvm-provisioner ✅
- VolumeBindingMode: WaitForFirstConsumer ✅

## 根本原因分析

TopoLVM mutating webhook 的容量計算邏輯:
1. Webhook 檢查 Pod 使用的 PVC
2. 計算這些 PVC 的總容量需求
3. 將計算結果注入到 Pod 的資源請求中

**可能的問題**:
1. Webhook 在 Pod 創建時,PVC 尚未綁定,無法讀取容量
2. Webhook 計算邏輯錯誤,默認返回 1 byte
3. Scheduler 配置的 divisor 導致計算錯誤

## 解決方案

### 方案 1: 檢查 webhook 是否正確處理 WaitForFirstConsumer PVC
WaitForFirstConsumer 模式下,PVC 在 Pod 調度前不會綁定。Webhook 需要能夠:
1. 讀取 PVC 的 spec.resources.requests.storage
2. 而非從已綁定的 PV 讀取容量

### 方案 2: 手動指定容量請求
在 vault values.yaml 中添加 pod annotations 或資源請求

### 方案 3: 檢查 namespace label
確認 vault namespace 沒有 `topolvm.io/webhook: ignore` label
