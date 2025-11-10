在 Kubernetes 中，**Taint（汙染）** 和 **Toleration（容忍）** 是節點調度的機制：

## 🔍 Taint 和 Toleration 的概念

- **Taint**：節點上的"標籤"，用來**排斥**某些 Pod 在該節點運行
- **Toleration**：Pod 上的設定，用來**容忍**特定的 Taint，讓 Pod 可以調度到有該 Taint 的節點

## 🎯 Master 節點的 Taint 歷史

### 新版 Kubernetes (v1.24+)
```yaml
node-role.kubernetes.io/control-plane:NoSchedule
```

### 舊版 Kubernetes (v1.24 之前)  
```yaml
node-role.kubernetes.io/master:NoSchedule
```

## 📋 為什麼需要雙重容忍？

在 `patch-alloy-tolerations.yaml` 中同時包含兩種 Toleration，是為了**相容性考量**：

```yaml
tolerations:
  # 容忍控制平面節點的 Taint (新版 K8s)
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
  # 容忍舊版 Master 節點的 Taint (舊版 K8s)
  - key: "node-role.kubernetes.io/master" 
    operator: "Exists"
    effect: "NoSchedule"
```

## 🎪 實際應用場景

**grafana-alloy** 作為 **DaemonSet** 需要在**所有節點**上運行，包括：
- ✅ Worker 節點（無 Taint）
- ✅ Master/Control Plane 節點（有 Taint）

雙重容忍確保無論使用哪種 Kubernetes 版本，都能正常部署收集所有節點的監控數據。

## 📚 參考資料

- [Kubernetes Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Control Plane Node Isolation](https://kubernetes.io/docs/setup/best-practices/cluster-large/#isolate-control-plane-nodes)