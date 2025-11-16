# StorageClass 架構設計

**版本**: 1.0
**最後更新**: 2025-11-15

---

## 📋 概述

DetectViz 平台使用兩種 StorageClass 策略來優化儲存資源分配：

1. **topolvm-provisioner** - app-worker 節點的本地高性能儲存
2. **local-path** - master 節點的本地儲存(用於觀測性堆疊)

## 🏗️ 架構拓撲

```
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   master-1      │  │   master-2      │  │   master-3      │  │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤  │
│  │ local-path      │  │ local-path      │  │ local-path      │  │
│  │ /var/lib/       │  │ /var/lib/       │  │ /var/lib/       │  │
│  │ k8s-storage/    │  │ k8s-storage/    │  │ k8s-storage/    │  │
│  │ ├─prometheus    │  │ ├─mimir         │  │ ├─loki          │  │
│  │ └─local-pv      │  │ └─local-pv      │  │ └─local-pv      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    app-worker (VM-4)                       │  │
│  ├───────────────────────────────────────────────────────────┤  │
│  │ TopoLVM                                                     │  │
│  │ data-vg (250GB SSD)                                         │  │
│  │ ├─ PostgreSQL (10Gi)                                        │  │
│  │ ├─ Grafana (10Gi)                                           │  │
│  │ ├─ Vault (10Gi)                                             │  │
│  │ ├─ Tempo (20Gi)                                             │  │
│  │ ├─ Keycloak (10Gi)                                          │  │
│  │ └─ ... (其他應用)                                            │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📦 StorageClass 定義

### 1. topolvm-provisioner

**提供者**: TopoLVM (CSI Driver)
**節點**: app-worker
**後端**: LVM Volume Group `data-vg` (250GB SSD)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: topolvm-provisioner
provisioner: topolvm.io
parameters:
  "csi.storage.k8s.io/fstype": "ext4"
  "topolvm.io/device-class": "ssd"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
```

**使用場景**:
- ✅ 需要高性能 I/O 的有狀態應用
- ✅ 資料庫 (PostgreSQL)
- ✅ 快取/會話儲存 (Grafana, Keycloak)
- ✅ 分散式追蹤 (Tempo)
- ✅ 安全儲存 (Vault)

**特性**:
- ✅ 動態供應
- ✅ 支援擴容
- ✅ 基於拓撲的智能調度
- ✅ 本地 SSD 性能

**限制**:
- ⚠️ 僅限 app-worker 節點
- ⚠️ 無法跨節點遷移 PV

---

### 2. local-path

**提供者**: Rancher Local Path Provisioner
**節點**: master-1, master-2, master-3
**後端**: 本地檔案系統 `/var/lib/k8s-storage/*`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: false
```

**使用場景**:
- ✅ 觀測性堆疊 (Prometheus, Loki, Mimir)
- ✅ 控制平面組件的本地儲存
- ✅ 不需要高IOPS的應用

**特性**:
- ✅ 輕量級,無需 LVM
- ✅ 直接使用檔案系統
- ✅ master 節點容忍汙點

**限制**:
- ❌ 不支援擴容
- ❌ 僅限 master 節點
- ⚠️ 無跨節點遷移

---

## 🗺️ 應用 StorageClass 對應表

### app-worker 節點應用 (topolvm-provisioner)

| 應用 | 命名空間 | StorageClass | 容量 | 理由 |
|------|---------|--------------|------|------|
| PostgreSQL | postgresql | topolvm-provisioner | 10Gi×3 | 資料庫需高 IOPS |
| Grafana | grafana | topolvm-provisioner | 10Gi | Plugins/Sessions |
| Vault | vault | topolvm-provisioner | 10Gi×3 | Raft 資料 + 安全性 |
| Tempo | tempo | topolvm-provisioner | 20Gi | Trace 資料高頻寫入 |
| Keycloak | keycloak | topolvm-provisioner | 10Gi | Session/Cache |
| ArgoCD | argocd | topolvm-provisioner | 5Gi | Repository cache |

### master 節點應用 (local-path)

| 應用 | 節點 | 命名空間 | StorageClass | 容量 | 理由 |
|------|------|---------|--------------|------|------|
| Prometheus | master-1 | prometheus | local-path | 50Gi | 短期 TSDB |
| Alertmanager | master-* | prometheus | local-path | 10Gi | 告警狀態 |
| Mimir (所有組件) | master-2 | mimir | local-path | 20Gi×4 | 長期 TSDB blocks |
| Loki (ingester) | master-3 | loki | local-path | 20Gi | WAL + Chunks |
| Loki (compactor) | master-3 | loki | local-path | 10Gi | Compaction |

---

## 🚀 部署前置條件

### app-worker 節點

1. **LVM Volume Group 配置**:
   ```bash
   # 在 app-worker 節點上
   sudo vgcreate data-vg /dev/sdb  # 假設 /dev/sdb 是 250GB SSD
   sudo vgs data-vg  # 驗證
   ```

2. **TopoLVM 部署**:
   - 由 ArgoCD ApplicationSet 自動部署
   - 應用: `infra-topolvm`

### master 節點

1. **儲存目錄創建**:
   ```bash
   # 在所有 master 節點上執行
   sudo mkdir -p /var/lib/k8s-storage/{prometheus,mimir,loki,local-pv}
   sudo chmod 755 /var/lib/k8s-storage
   ```

2. **local-path-provisioner 部署**:
   - 由 ArgoCD ApplicationSet 自動部署
   - 應用: `infra-local-path-provisioner`

---

## 🔧 故障排除

### PVC Pending (topolvm-provisioner)

**症狀**:
```
NAME              STATUS    VOLUME   CAPACITY   STORAGECLASS
data-postgresql-0 Pending            topolvm-provisioner
```

**可能原因**:
1. Pod 未調度到 app-worker 節點
2. data-vg 容量不足
3. TopoLVM node pod 未運行

**診斷**:
```bash
# 檢查 TopoLVM 狀態
kubectl get pods -n kube-system -l app.kubernetes.io/name=topolvm-node

# 檢查 VG 容量
kubectl exec -n kube-system topolvm-node-xxxxx -- vgs data-vg

# 檢查 Pod 調度
kubectl describe pod postgresql-0 -n postgresql | grep -A 5 Events
```

### PVC Pending (local-path)

**症狀**:
```
NAME                   STATUS    VOLUME   STORAGECLASS
prometheus-db-0        Pending            local-path
```

**可能原因**:
1. Pod 未調度到 master 節點
2. local-path-provisioner 未運行
3. 目錄權限問題

**診斷**:
```bash
# 檢查 local-path-provisioner
kubectl get pods -n kube-system -l app=local-path-provisioner

# 檢查目錄
ssh master-1 "ls -la /var/lib/k8s-storage/"

# 檢查 Pod 節點親和性
kubectl get pod prometheus-0 -n prometheus -o yaml | grep -A 10 affinity
```

---

## 📊 容量規劃

### app-worker (250GB)

```
PostgreSQL:    30Gi (3×10Gi)
Grafana:       10Gi
Vault:         30Gi (3×10Gi)
Tempo:         20Gi
Keycloak:      10Gi
ArgoCD:        5Gi
Reserved:      145Gi (可用於其他應用)
─────────────────────
Total:         250Gi
```

### master 節點

每個 master 節點建議預留至少 **100GB** 本地儲存空間:

- master-1: Prometheus (50Gi) + Alertmanager (10Gi)
- master-2: Mimir 組件 (80Gi total)
- master-3: Loki 組件 (30Gi total)

---

## 🔄 未來優化

### 考慮的改進

1. **Object Storage for Mimir/Loki**:
   - 部署 MinIO 提供 S3 相容儲存
   - Mimir/Loki 改用 S3 backend
   - 優點: 更好的擴展性、持久性

2. **Ceph RBD StorageClass**:
   - 提供跨節點的分散式儲存
   - 支援 PV 遷移
   - 優點: HA, 可遷移

3. **NFS StorageClass**:
   - 用於共享配置檔案
   - ReadWriteMany 支援

---

## 📚 相關文檔

- [TopoLVM 官方文檔](https://github.com/topolvm/topolvm)
- [Rancher Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
- [Kubernetes StorageClass](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [部署故障排除](../troubleshooting/storage-topolvm-fixes.md)

---

**維護者**: DetectViz Infrastructure Team
**聯絡**: infrastructure@detectviz.internal
