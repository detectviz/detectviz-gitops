# Scripts

這個目錄包含 DetectViz 平台部署和維護過程中使用的腳本。

## 腳本列表

### 部署腳本

#### `install-argocd.sh`
- **用途**: 安裝 ArgoCD 到 Kubernetes 集群
- **使用時機**: Phase 9 - ArgoCD GitOps 控制平面部署
- **參數**: 支援自定義版本和命名空間
- **功能**: 安裝 ArgoCD HA 版本，驗證安裝狀態

#### `cluster-cleanup.sh`
- **用途**: 清理和修復 Kubernetes 集群的各種問題
- **使用時機**: Phase 2 前 - 集群狀態檢查和修復
- **功能**: 檢查 etcd 狀態、清理舊配置、重置集群、修復網路問題
- **動作**: check-etcd, cleanup-etcd, reset-cluster, fix-ssh-keys, manual-ha-fix, network-cleanup, full-recovery
- **改進**:
  - reset-cluster 現在會在重置前自動清理現有的 Kubernetes 資源（如果集群還在運行）
  - network-cleanup 會自動清理 SSH known_hosts 以避免連接問題
  - full-recovery 優先處理 SSH 連接問題

#### `setup-vault-secrets.sh` ⚠️ **已棄用**
- **用途**: 將敏感資訊安全存儲到 Vault 中供 ESO 使用
- **使用時機**: Phase 10 前 - 設置 secrets 管理 (需要 Vault + ESO)
- **功能**: 將 SSH 私鑰等敏感資訊存儲到 Vault 的 `secret/argocd/repo-ssh-key`
- **安全性**: 避免將私鑰明碼存放在 Git 中
- **注意**: 目前使用 `setup-argocd-ssh.sh` 替代，直接設置 ArgoCD secret

#### `setup-argocd-ssh.sh` ✅ **推薦使用**
- **用途**: 安全設置 ArgoCD 的 SSH 倉庫認證
- **使用時機**: Phase 9 後 - ArgoCD SSH 認證配置
- **功能**: 將 SSH 私鑰安全注入到 ArgoCD secret `detectviz-github-ssh-creds` 中
- **安全性**: 避免將私鑰明碼存放在 Git 倉庫中
- **參數**: SSH_KEY_PATH (可選，默認 ~/.ssh/id_ed25519_detectviz)
- **優點**: 不依賴外部系統，設置簡單

#### `test-cluster-dns.sh`
- **用途**: 測試集群內部 DNS 解析功能
- **使用時機**: Phase 2 後 - 集群功能驗證
- **功能**: 運行測試 Pod 驗證 kubernetes.default.svc.cluster.local 解析
- **改進**: 智能連接選擇，自動等待集群就緒，提供詳細的故障排除資訊

#### `render-node-labels.sh`
- **用途**: 從 Terraform 輸出生成 Kubernetes 節點標籤腳本
- **使用時機**: Phase 6 - 節點監控標籤同步
- **依賴**: 需要 Terraform 和 jq
- **輸出**: 生成 `.last-node-labels.sh` 腳本用於應用標籤

#### `vault-setup-observability.sh` ✅ **推薦使用**
- **用途**: 依據 `VAULT_PATH_STRUCTURE.md` 一次性產生 PostgreSQL、Grafana、Keycloak、Minio 等所有 Observability Secrets，並寫入 Vault KV v2。
- **使用時機**: Phase 6.0 - Vault + ESO 初始化。
- **功能**:
  - 自動產生強隨機密碼（含 Pgpool MD5 雜湊）。
  - 將密碼寫入對應的 `secret/<namespace>/...` 路徑，確保 ExternalSecret 讀取一致。
  - 輸出一次性密碼摘要，方便匯入密碼管理器。
- **注意**: 生成後請立刻執行 `./scripts/validate-pre-deployment.sh` 驗證 ExternalSecrets 是否同步成功。

### 驗證腳本

#### `health-check.sh`
- **用途**: 執行基礎的服務健康檢查
- **使用時機**: 快速檢查服務運行狀態
- **功能**: 檢查 Pod 運行狀態、基本連通性
- **參數**: 支援按階段執行 (--phase2, --phase3, --phase9, --phase10)

#### `validation-check.sh`
- **用途**: 執行詳細的驗證檢查，對應 deploy.md 中的「雙重強化檢查」
- **使用時機**: 各 Phase 結束後的深入驗證
- **功能**: 檢查配置正確性、網路設定、證書狀態等，自動等待集群就緒
- **參數**: 支援按階段執行 (--phase2 到 --phase5, --phase9, --final)
- **改進**: 智能連接選擇，自動等待集群 API server 就緒（最多 2 分鐘）

#### `test-pod-recovery.sh`
- **用途**: 測試 kube-vip 高可用性下的 Pod 恢復
- **使用時機**: Phase 3 - Kube-VIP 高可用性配置驗證
- **功能**: 模擬節點故障，驗證 VIP 故障轉移

#### `validate-pre-deployment.sh` ✅ **應用部署前驗證**
- **用途**: 驗證應用部署前的基礎設施就緒狀態
- **使用時機**: Phase 7.1 - 應用部署前檢查
- **功能**:
  - 檢查 ArgoCD ApplicationSet 配置 (List generator)
  - 驗證 Vault secrets 初始化狀態 (需要 vault CLI)
  - 檢查 External Secrets Operator 健康狀態
  - 驗證必要的 StorageClass 存在
  - 檢查 ClusterSecretStore 配置
- **依賴**: kubectl, vault (可選)
- **輸出**: 彩色狀態報告，顯示 PASS/FAIL/WARN
- **退出碼**: 0=成功, 1=有問題

#### `validate-post-deployment.sh` ✅ **應用部署後驗證**
- **用途**: 驗證應用部署健康狀態和功能性
- **使用時機**: Phase 7.2 - 應用部署後驗證
- **功能**:
  - 檢查 namespace 創建 (postgresql, keycloak, grafana, monitoring)
  - 驗證 ExternalSecrets 同步狀態
  - 檢查 Pod 健康狀態 (Running)
  - 驗證 Service 可用性
  - 測試跨 namespace 連接性
  - 檢查 Ingress 配置
  - 驗證 PVC 綁定狀態
  - 應用特定檢查:
    - PostgreSQL replication 狀態
    - Minio bucket 創建
- **依賴**: kubectl
- **輸出**: 彩色狀態報告，顯示 PASS/FAIL/WARN
- **退出碼**: 0=成功, 1=有問題

### Secrets 自動化指引

- ✅ **已轉向 Vault → ESO**: 本倉庫已全面改用 `vault-setup-observability.sh` + ExternalSecret。原本的 `bootstrap-app-secrets.sh` 與 `bootstrap-monitoring-secrets.sh` 會直接在 Kubernetes 建立 Secrets，違反 Platform Engineering 要求，因此已移除。請依照 `app-deploy-sop.md` Phase 6.0 的 Vault 流程執行。

## 使用方式

### 基本使用
```bash
# 安裝 ArgoCD
./scripts/install-argocd.sh

# 生成節點標籤
./scripts/render-node-labels.sh > .last-node-labels.sh
bash .last-node-labels.sh

# 健康檢查 (基礎檢查)
./scripts/health-check.sh

# 驗證檢查 (詳細檢查)
./scripts/validation-check.sh

# VIP 高可用性測試
./scripts/test-pod-recovery.sh

# Phase 7: 應用部署驗證
# 部署前驗證
./scripts/validate-pre-deployment.sh

# 部署應用 (via ArgoCD)
argocd app sync postgresql keycloak grafana prometheus loki mimir minio

# 部署後驗證
./scripts/validate-post-deployment.sh
```

### 自定義參數
```bash
# 自定義 ArgoCD 版本
ARGOCD_VERSION=v2.10.0 ./scripts/install-argocd.sh

# 自定義 Terraform 目錄
TF_DIR=../custom-terraform ./scripts/render-node-labels.sh
```

## 腳本依賴

### 系統依賴
- `kubectl`: Kubernetes CLI
- `terraform`: 基礎設施即代碼工具 (僅 `render-node-labels.sh`)
- `jq`: JSON 處理工具 (僅 `render-node-labels.sh`)

### 網路依賴
- Kubernetes API Server 訪問權限
- Terraform Cloud 或本地狀態訪問 (如適用)

## 故障排除

### 常見問題

#### 腳本權限錯誤
```bash
chmod +x scripts/*.sh
```

#### Terraform 狀態不可訪問
```bash
# 確保在正確的目錄運行
cd /path/to/terraform
terraform init
```

#### Kubernetes 權限不足
```bash
# 確保使用具有 cluster-admin 權限的 kubeconfig
kubectl auth can-i '*' '*' --all-namespaces
```

## 開發說明

### 添加新腳本
1. 將腳本放在 `scripts/` 目錄
2. 添加執行權限: `chmod +x script-name.sh`
3. 在此 README.md 中添加文檔
4. 在 `deploy.md` 中引用腳本

### 腳本命名慣例
- 使用小寫字母和連字符: `script-name.sh`
- 添加 `.sh` 擴展名
- 第一行使用 `#!/bin/bash` 或 `#!/usr/bin/env bash`
- 使用 `set -euo pipefail` 確保錯誤處理
