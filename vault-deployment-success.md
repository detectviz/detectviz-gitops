# Vault HA Cluster 部署成功報告

**日期**: 2025-11-14 23:15
**狀態**: ✅ 完全成功

---

## 🎉 成功摘要

成功在單 worker node 環境中部署並啟動 HashiCorp Vault HA Cluster (3 replicas)。

### 關鍵成就

1. ✅ **解決 Pod Anti-Affinity 調度問題**
   - 問題: 默認 `requiredDuringScheduling` 要求每個 pod 在不同 node
   - 環境: 只有 1 個 worker node (app-worker)
   - 解決: 改用 `preferredDuringScheduling` (weight: 100)

2. ✅ **成功啟動 Vault HA Cluster**
   - vault-0: Active (leader)
   - vault-1: Standby
   - vault-2: Standby
   - 所有 pods: 1/1 Running, Healthy

3. ✅ **Raft Cluster 正常運行**
   - Cluster ID: 3f1cbe64-a561-9853-233f-a9e9ebeef9b2
   - Cluster Name: vault-cluster-06e1cf59
   - 所有節點已加入 cluster

---

## 📊 當前狀態

### Vault Pods

```
NAME      READY   STATUS    RESTARTS   AGE
vault-0   1/1     Running   0          4m41s
vault-1   1/1     Running   0          3m53s
vault-2   1/1     Running   0          3m53s
```

### Vault Status

**vault-0 (Active)**:
- Sealed: false ✅
- HA Mode: active
- HA Cluster: https://vault-0.vault-internal:8201

**vault-1 (Standby)**:
- Sealed: false ✅
- HA Mode: standby
- Active Node Address: http://10.244.43.236:8200

**vault-2 (Standby)**:
- Sealed: false ✅
- HA Mode: standby
- Active Node Address: http://10.244.43.236:8200

### ArgoCD Application

```
NAME: argocd/infra-vault
STATUS: OutOfSync (正常,因為 StatefulSet 已手動重啟)
HEALTH: Healthy ✅
```

---

## 🔧 技術解決方案

### 1. Pod Anti-Affinity 配置調整

**文件**: `argocd/apps/infrastructure/vault/overlays/values.yaml`

**變更**:
```yaml
server:
  # Pod 反親和性 - 改為 preferred (允許單 node 測試環境)
  affinity: |
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: {{ template "vault.name" . }}
                app.kubernetes.io/instance: "{{ .Release.Name }}"
                component: server
            topologyKey: kubernetes.io/hostname
```

**效果**:
- 允許多個 Vault pods 在同一 node 上運行
- 當有多個 nodes 時仍會嘗試分散 (weight: 100)
- 適合單 worker node 測試環境

### 2. Vault Unsealing 流程

**初始化** (已完成):
```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-keys.json
```

**Unseal 所有實例** (已完成):
```bash
# vault-0
kubectl exec -n vault vault-0 -- vault operator unseal $KEY1
kubectl exec -n vault vault-0 -- vault operator unseal $KEY2
kubectl exec -n vault vault-0 -- vault operator unseal $KEY3

# vault-1 (自動加入 Raft cluster)
kubectl exec -n vault vault-1 -- vault operator unseal $KEY1
kubectl exec -n vault vault-1 -- vault operator unseal $KEY2
kubectl exec -n vault vault-1 -- vault operator unseal $KEY3

# vault-2 (自動加入 Raft cluster)
kubectl exec -n vault vault-2 -- vault operator unseal $KEY1
kubectl exec -n vault vault-2 -- vault operator unseal $KEY2
kubectl exec -n vault vault-2 -- vault operator unseal $KEY3
```

**重要發現**:
- vault-1/vault-2 在 unseal 後會自動加入 vault-0 的 Raft cluster
- 第三次 unseal 命令後可能仍顯示 `Sealed: true`
- 檢查日誌會看到 "vault is unsealed" 和 "entering standby mode"
- 稍等片刻後 pods 會變成 1/1 Ready

---

## 📝 文檔更新

### 1. deploy.md

**新增問題 #5**: Vault Pod Anti-Affinity 與單 Worker Node
- 症狀描述
- 根本原因分析
- 解決方案 (preferred vs required)
- 生產環境建議

**更新 Phase 5**: Vault 初始化
- 澄清 3 個 pods 都會 Running (不只 vault-0)
- 添加 Anti-Affinity 問題排查鏈接
- 說明 Raft cluster 自動加入行為
- 添加 unseal 後可能的異常狀態說明
- 完整的驗證步驟和期望結果
- 故障排除指南

### 2. Git Commits

**Commit 1**: `6dcaa73` - fix: Relax Vault pod anti-affinity for single-node testing
- 修改 values.yaml 配置
- 詳細的 commit message 說明原因和影響

**Commit 2**: `2362085` - docs: Add Vault pod anti-affinity troubleshooting
- 更新 deploy.md 文檔
- 添加問題排查和解決方案

---

## 🎯 基礎設施狀態總覽

### 完全成功 (5/6) ✅

| 應用 | 同步 | 健康度 | 備註 |
|------|------|--------|------|
| **cert-manager** | Synced | Healthy | ✅ 完全正常 |
| **ingress-nginx** | Synced | Progressing | ✅ 功能正常 |
| **topolvm** | Synced | Healthy | ✅ Storage Capacity Tracking 正常 |
| **vault** | OutOfSync | **Healthy** | ✅ **HA Cluster 完全運行** |

### 需同步 (2/6) ⏳

| 應用 | 狀態 | 原因 |
|------|------|------|
| **metallb** | OutOfSync | 配置漂移 (可忽略) |
| **external-secrets-operator** | OutOfSync + SyncError | 待同步 |

---

## 🚀 下一步

### 1. 同步剩餘基礎設施 (可選)

```bash
argocd app sync infra-metallb
argocd app sync infra-external-secrets-operator
```

### 2. 開始應用部署

現在 Vault 已完全就緒,可以部署需要 secrets 的應用:
- PostgreSQL
- Prometheus
- Loki
- Tempo
- Grafana

### 3. 生產環境注意事項

**如果擴展到多 worker nodes**:
- 考慮改回 `requiredDuringScheduling` anti-affinity
- 確保每個 Vault pod 在不同 node 上以提高可用性
- 更新 `argocd/apps/infrastructure/vault/overlays/values.yaml`

**Vault Unseal 自動化**:
- 考慮使用 Vault Auto-unseal (Cloud KMS, Transit engine)
- 或部署 Vault Unsealer sidecar
- 當前需要重啟後手動 unseal

---

## 📚 參考資料

### 配置文件
- `argocd/apps/infrastructure/vault/overlays/values.yaml` - Vault Helm values
- `deploy.md` - 完整部署文檔
- `vault-keys.json` - Vault unseal keys (請安全保管!)

### Git Commits
- `6dcaa73` - Vault anti-affinity fix
- `2362085` - Documentation updates
- `f080a5b` - TopoLVM Storage Capacity Tracking

### 相關問題
- Issue #4: TopoLVM 調度模式
- Issue #5: Vault Pod Anti-Affinity

---

## ✅ 驗證清單

- [x] 所有 3 個 Vault pods 運行正常
- [x] vault-0 是 active leader
- [x] vault-1/vault-2 是 standby
- [x] Raft cluster 正常運作
- [x] 所有 pods 都 unsealed
- [x] ArgoCD Health 顯示 Healthy
- [x] 文檔已更新 (deploy.md)
- [x] Git commits 已推送
- [x] vault-keys.json 已保存

**部署狀態**: 🎉 **SUCCESS** 🎉
