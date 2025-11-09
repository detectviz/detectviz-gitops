# **任務紀錄** 
部署過程中，如果有發現遺漏步驟，同時同步於檔案 @deploy-guide.md @deploy-troubleshooting.md 

## 基本認證

argocd sshkey : `id_ed25519_detectviz`
vm-1~vm-4 sshkey : `id_rsa`
kubectl : `kubeconfig/admin.conf`
proxmox 主機 ：ssh root@192.168.0.2
vm-1~vm-4 主機 ：ssh ubuntu@192.168.0.11 ~ 192.168.0.14


## 📋 **部署過程發現的遺漏步驟總結**

在 DetectViz 平台部署過程中，我們發現並修復了多個關鍵的遺漏步驟：

### ✅ **已修復的關鍵問題**

1. **🔧 etcd 連接問題** (Phase 2)
   - **問題**: `dial tcp 127.0.0.1:2379: connect: connection refused`
   - **修復**: 重置 etcd 數據目錄並重新初始化
   - **文檔**: 已添加到 `deploy-troubleshooting.md`

2. **🔐 RBAC 權限配置** (Phase 3)
   - **問題**: `kubernetes-admin` 用戶權限不足
   - **修復**: 更新 cluster-admin ClusterRoleBinding 包含 `kubeadm:cluster-admins` 群組
   - **文檔**: 已記錄權限修復步驟

3. **🌐 CNI 網路插件** (Phase 3)
   - **問題**: 集群缺少網路插件，pods 無法創建網路
   - **修復**: 安裝 Flannel CNI，修復橋接模塊配置
   - **文檔**: 新增完整的 CNI 故障排除指南

4. **📝 ApplicationSet Schema 錯誤** (Phase 3)
   - **問題**: `targetRevision: field not declared in schema`
   - **修復**: 將所有 `targetRevision` 字段替換為 `revision`
   - **文檔**: 新增 Schema 兼容性修復指南

### ❌ **當前阻塞問題**

5. **🌍 網路連通性問題** (Phase 3)
   - **問題**: 節點無法訪問外部網路，導致容器鏡像拉取失敗
   - **影響**: 阻止所有應用部署和功能驗證
   - **狀態**: **緊急待修復**
   - **文檔**: 已新增完整的網路診斷和修復指南

### 📊 **部署狀態總結**

| 階段 | 組件 | 狀態 | 備註 |
|------|------|------|------|
| ✅ Phase 1 | MetalLB | 完成 | 26資源正常運行 |
| ✅ Phase 2 | cert-manager | 完成 | 46資源正常運行 |
| ✅ Phase 3 | ArgoCD | 完成 | HA模式，資源限制已配置 |
| ✅ Phase 3 | CNI網路 | 完成 | Flannel運行中 |
| ✅ Phase 3 | ApplicationSets | 完成 | Schema錯誤已修復 |
| ⏸️ Phase 4 | ESO | 阻塞 | 等待網路連通性修復 |
| ⏸️ Phase 4 | 功能驗證 | 阻塞 | 等待網路連通性修復 |

### 🎯 **關鍵教訓**

1. **網路基礎設施是首要依賴** - 確保節點有外部網路訪問權限
2. **CNI 插件需在應用部署前配置** - 網路是 Kubernetes 的核心組件
3. **RBAC 配置變更需重啟服務** - API Server 需要重啟才能識別權限變更
4. **版本兼容性需持續檢查** - ArgoCD 版本升級可能引入配置變更
5. **文檔需與實際部署同步** - 及時記錄問題和解決方案

### 📝 **文檔更新**

已同步更新以下文件：
- `deploy-guide.md`: 添加了狀態總結和修復記錄
- `deploy-troubleshooting.md`: 新增了4個故障排除章節


### ⚡ **當前狀態**

- ✅ 已完成：etcd修復、RBAC配置、CNI安裝、ApplicationSet修復、ArgoCD部署
- ❌ 阻塞：網路連通性問題 - **需要基礎設施層面修復**
- ⏸️ 等待：ESO部署和功能驗證


## **vm-1 與 Proxmox 主機（192.168.0.1）之間的連線並非完全中斷，而是週期性 freeze 約 40 秒。**
表示封包有時被阻擋或延遲在 虛擬網路層（bridge / tap / VirtIO queue）。

```bash
ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.11 "ping 192.168.0.1"
PING 192.168.0.1 (192.168.0.1) 56(84) bytes of data.
64 bytes from 192.168.0.1: icmp_seq=7 ttl=64 time=0.486 ms
64 bytes from 192.168.0.1: icmp_seq=8 ttl=64 time=0.519 ms
64 bytes from 192.168.0.1: icmp_seq=9 ttl=64 time=0.486 ms
64 bytes from 192.168.0.1: icmp_seq=10 ttl=64 time=0.549 ms
64 bytes from 192.168.0.1: icmp_seq=11 ttl=64 time=0.559 ms
64 bytes from 192.168.0.1: icmp_seq=54 ttl=64 time=0.523 ms
64 bytes from 192.168.0.1: icmp_seq=55 ttl=64 time=0.621 ms
64 bytes from 192.168.0.1: icmp_seq=56 ttl=64 time=0.486 ms
64 bytes from 192.168.0.1: icmp_seq=57 ttl=64 time=0.550 ms
64 bytes from 192.168.0.1: icmp_seq=58 ttl=64 time=0.543 ms
64 bytes from 192.168.0.1: icmp_seq=100 ttl=64 time=0.503 ms
64 bytes from 192.168.0.1: icmp_seq=101 ttl=64 time=0.526 ms
64 bytes from 192.168.0.1: icmp_seq=102 ttl=64 time=0.561 ms
64 bytes from 192.168.0.1: icmp_seq=103 ttl=64 time=0.585 ms
64 bytes from 192.168.0.1: icmp_seq=104 ttl=64 time=0.540 ms
64 bytes from 192.168.0.1: icmp_seq=105 ttl=64 time=0.561 ms
64 bytes from 192.168.0.1: icmp_seq=147 ttl=64 time=0.537 ms
64 bytes from 192.168.0.1: icmp_seq=148 ttl=64 time=0.767 ms
64 bytes from 192.168.0.1: icmp_seq=149 ttl=64 time=0.537 ms
64 bytes from 192.168.0.1: icmp_seq=150 ttl=64 time=0.547 ms
64 bytes from 192.168.0.1: icmp_seq=151 ttl=64 time=0.533 ms
64 bytes from 192.168.0.1: icmp_seq=152 ttl=64 time=0.545 ms
```

```
ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.11 "KUBECONFIG=/tmp/admin.conf sudo kubectl get nodes"
NAME   STATUS   ROLES    AGE     VERSION
vm-1   Ready    <none>   7h58m   v1.32.9
```

