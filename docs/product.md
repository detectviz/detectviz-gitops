# DetectViz 基礎設施平台

DetectViz Infra 是一個企業級 AI/ML 平台的基礎設施層，採用多層自動化堆疊實現完整的基礎設施管理。

## 核心目標
- 提供高可用 Kubernetes 集群作為 DetectViz AI 平台的運行環境
- 實現基礎設施即程式碼 (IaC) 與 GitOps 自動化部署
- 支援 AI/ML 工作負載的儲存、網路與運算需求
- 提供可觀測性、安全性與秘密管理的完整解決方案

## 技術架構流程
```
KVM/Proxmox (虛擬化層)
    ↓
Terraform (VM 建立)
    ↓  
Ansible (Kubernetes 安裝)
    ↓
Argo CD (GitOps 控制面)
    ↓
Helm (應用部署)
```

## 核心服務
- **ArgoCD**: GitOps 控制面與應用交付
- **Vault**: 秘密管理與安全存儲
- **cert-manager**: TLS 證書自動化管理
- **external-secrets-operator**: 秘密同步與注入
- **MetalLB**: 負載均衡器服務
- **TopoLVM**: 本地儲存管理
- **kube-vip**: 控制平面高可用

## 部署環境
- **控制平面**: 3 個 Master 節點 (HA etcd + API Server)
- **工作節點**: 2 個 Worker 節點 (應用 + AI 專用)
- **網路**: Calico CNI，支援 NetworkPolicy
- **儲存**: NVMe + SSD 混合架構，TopoLVM 管理